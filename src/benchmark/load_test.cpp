#include "../constants/constants.h"
#include "../ipc/message_queue.h"
#include "../utils/cli_parser.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

enum class Operation {
    STATUS,
    RESERVE,
    CANCEL,
    MIXED
};

bool parseOperation(const string& value, Operation& operation) {
    if (value == "STATUS") {
        operation = Operation::STATUS;
        return true;
    }
    if (value == "RESERVE") {
        operation = Operation::RESERVE;
        return true;
    }
    if (value == "CANCEL") {
        operation = Operation::CANCEL;
        return true;
    }
    if (value == "MIXED") {
        operation = Operation::MIXED;
        return true;
    }
    return false;
}

string operationName(Operation operation) {
    switch (operation) {
        case Operation::STATUS:  return "STATUS";
        case Operation::RESERVE: return "RESERVE";
        case Operation::CANCEL:  return "CANCEL";
        case Operation::MIXED:   return "MIXED";
    }
    return "UNKNOWN";
}

string makeCommand(Operation operation, int seatId) {
    return operationName(operation) + " " + to_string(seatId);
}

struct ThreadStats {
    long long completed = 0;
    long long opSuccess = 0;
    long long businessRejected = 0;
    long long timeouts = 0;
    long long transportErrors = 0;
    vector<long long> latenciesUs;
};

void printUsage(const char* prog) {
    cout << "Usage:\n"
         << "  " << prog << " <total_requests> <concurrency> <STATUS|RESERVE|CANCEL|MIXED> [seat_id]\n"
         << "Or with flags:\n"
         << "  " << prog << " --clients <N> --requests <R> --workload <STATUS|RESERVE|CANCEL|MIXED> [--seat <id>]\n";
}

} // namespace

int main(int argc, char* argv[]) {
    if (argc < 4) {
        printUsage(argv[0]);
        return 1;
    }

    int logicalClients = 0;
    int requestsPerClient = 0;
    int totalRequests = 0;
    Operation operation = Operation::STATUS;
    int fixedSeatId = 0;

    bool useFlags = false;
    for (int i = 1; i < argc; ++i) {
        string arg = argv[i];
        if (arg == "--clients" || arg == "-c" || arg == "--requests" || arg == "-r" || arg == "--workload" || arg == "--operation") {
            useFlags = true;
            break;
        }
    }

    if (useFlags) {
        for (int i = 1; i < argc; ++i) {
            string arg = argv[i];
            if ((arg == "--clients" || arg == "-c") && i + 1 < argc) {
                if (!parsePositiveInt(argv[++i], logicalClients)) {
                    cerr << "Invalid --clients\n";
                    return 1;
                }
            } else if ((arg == "--requests" || arg == "-r" || arg == "--requests-per-client") && i + 1 < argc) {
                if (!parsePositiveInt(argv[++i], requestsPerClient)) {
                    cerr << "Invalid --requests\n";
                    return 1;
                }
            } else if ((arg == "--workload" || arg == "--operation" || arg == "-w") && i + 1 < argc) {
                if (!parseOperation(argv[++i], operation)) {
                    cerr << "Invalid workload (choose STATUS, RESERVE, CANCEL, MIXED)\n";
                    return 1;
                }
            } else if ((arg == "--seat" || arg == "-s") && i + 1 < argc) {
                if (!parsePositiveInt(argv[++i], fixedSeatId) || fixedSeatId > Constants::SEAT_COUNT) {
                    cerr << "Seat ID must be between 1 and " << Constants::SEAT_COUNT << "\n";
                    return 1;
                }
            } else {
                cerr << "Unknown argument: " << arg << "\n";
                printUsage(argv[0]);
                return 1;
            }
        }
        if (logicalClients <= 0 || requestsPerClient <= 0) {
            cerr << "Both --clients and --requests must be positive\n";
            return 1;
        }
        totalRequests = logicalClients * requestsPerClient;
    } else {
        if (argc != 4 && argc != 5) {
            printUsage(argv[0]);
            return 1;
        }
        int arg1 = 0;
        int arg2 = 0;
        if (!parsePositiveInt(argv[1], arg1)
            || !parsePositiveInt(argv[2], arg2)
            || !parseOperation(argv[3], operation)) {
            cout << "Invalid arguments\n";
            return 1;
        }
        if (argc == 5) {
            if (!parsePositiveInt(argv[4], fixedSeatId) || fixedSeatId > Constants::SEAT_COUNT) {
                cout << "Seat ID must be between 1 and " << Constants::SEAT_COUNT << "\n";
                return 1;
            }
        }

        totalRequests = arg1;
        logicalClients = arg2;
        if (logicalClients > totalRequests) {
            logicalClients = totalRequests;
        }
        requestsPerClient = totalRequests / logicalClients;
        // Adjust totalRequests to match logicalClients * requestsPerClient
        totalRequests = logicalClients * requestsPerClient;
    }

    if (logicalClients > 100000) {
        cerr << "Too many logical clients for the client ID range\n";
        return 1;
    }

    int requestQueueId;
    try {
        requestQueueId = ipc::MessageQueue::openRequests().id();
    } catch (const exception& error) {
        cerr << error.what() << "\nMake sure server is running.\n";
        return 1;
    }

    cout << unitbuf;
    cout << "\n";
    cout << "====================================\n";
    cout << " Airplane Reservation Load Test\n";
    cout << "====================================\n";
    cout << "Logical Clients : " << logicalClients << "\n";
    cout << "Requests/Client : " << requestsPerClient << "\n";
    cout << "Planned Requests: " << totalRequests << "\n";
    cout << "Operation       : " << operationName(operation) << "\n";
    if (fixedSeatId > 0) {
        cout << "Target Seat     : " << fixedSeatId << "\n";
    } else {
        cout << "Target Seat     : round-robin 1-20\n";
    }
    cout << "====================================\n\n";

    // In-Flight tracking
    // Strict definition:
    // Increment: strictly AFTER msgsnd() succeeds.
    // Decrement: AFTER matching response received.
    atomic<int> currentInFlight{0};
    atomic<int> peakInFlight{0};
    ipc::InFlightTracker inFlightTracker{&currentInFlight, &peakInFlight};

    // Sampling thread for avg_in_flight
    atomic<bool> stopSampling{false};
    atomic<long long> inFlightSampleSum{0};
    atomic<long long> inFlightSampleCount{0};

    thread samplerThread([&] {
        while (!stopSampling.load(memory_order_relaxed)) {
            inFlightSampleSum.fetch_add(currentInFlight.load(memory_order_relaxed), memory_order_relaxed);
            inFlightSampleCount.fetch_add(1, memory_order_relaxed);
            this_thread::sleep_for(chrono::microseconds(100));
        }
    });

    // Start gate to ensure all logical client threads begin concurrently
    atomic<int> threadsReady{0};
    atomic<bool> startGate{false};

    vector<ThreadStats> threadStats(logicalClients);
    vector<thread> threads;
    threads.reserve(logicalClients);

    bool threadCreationFailure = false;
    string threadCreationError;

    for (int i = 0; i < logicalClients; ++i) {
        try {
            threads.emplace_back([&, i] {
                const int clientId = 10000 + i;
                auto& stats = threadStats[i];
                stats.latenciesUs.reserve(requestsPerClient);

                std::unique_ptr<ipc::MessageQueue> replies;
                try {
                    replies = std::make_unique<ipc::MessageQueue>(ipc::MessageQueue::createPrivateResponse());
                } catch (const exception& error) {
                    stats.transportErrors = requestsPerClient;
                    threadsReady.fetch_add(1, memory_order_release);
                    cerr << "Client " << clientId << ": " << error.what() << "\n";
                    return;
                }

                // Wait at the barrier until all threads are created and ready
                threadsReady.fetch_add(1, memory_order_release);
                while (!startGate.load(memory_order_acquire)) {
                    this_thread::yield();
                }

                // Execute client workload
                for (int req = 0; req < requestsPerClient; ++req) {
                    Operation currentOp = operation;
                    int seatId = 0;

                    if (operation == Operation::MIXED) {
                        currentOp = (req % 2 == 0) ? Operation::RESERVE : Operation::CANCEL;
                        int seatStep = req / 2;
                        seatId = (fixedSeatId > 0) ? fixedSeatId : ((i + seatStep) % Constants::SEAT_COUNT) + 1;
                    } else {
                        int requestNumber = i + req * logicalClients;
                        seatId = (fixedSeatId > 0) ? fixedSeatId : (requestNumber % Constants::SEAT_COUNT) + 1;
                    }

                    string command = makeCommand(currentOp, seatId);

                    const auto start = chrono::steady_clock::now();
                    try {
                        const auto response = ipc::exchangeCommand(
                            requestQueueId, replies->id(),
                            clientId, command,
                            chrono::seconds(10),
                            &inFlightTracker
                        );
                        const auto end = chrono::steady_clock::now();
                        const auto latencyUs = chrono::duration_cast<chrono::microseconds>(end - start).count();

                        stats.completed++;
                        stats.latenciesUs.push_back(latencyUs);

                        if (currentOp == Operation::STATUS || response.rfind("SUCCESS:", 0) == 0) {
                            stats.opSuccess++;
                        } else {
                            // Business rejection (e.g. seat already reserved, or wrong owner on cancel)
                            stats.businessRejected++;
                        }
                    } catch (const exception& err) {
                        string errMsg = err.what();
                        if (errMsg.find("timeout") != string::npos) {
                            stats.timeouts++;
                        } else {
                            stats.transportErrors++;
                        }
                    }
                }
            });
        } catch (const exception& err) {
            threadCreationFailure = true;
            threadCreationError = err.what();
            cerr << "Failed to create thread " << i << ": " << err.what() << "\n";
            break;
        }
    }

    const int osClientThreads = static_cast<int>(threads.size());

    // Wait until all spawned threads are at the barrier
    while (threadsReady.load(memory_order_acquire) < osClientThreads) {
        this_thread::sleep_for(chrono::microseconds(50));
    }

    // Release the barrier gate and start timer
    const auto testStart = chrono::steady_clock::now();
    startGate.store(true, memory_order_release);

    for (auto& t : threads) {
        if (t.joinable()) {
            t.join();
        }
    }

    const auto testEnd = chrono::steady_clock::now();
    stopSampling.store(true, memory_order_relaxed);
    if (samplerThread.joinable()) {
        samplerThread.join();
    }

    const double totalSeconds = chrono::duration<double>(testEnd - testStart).count();

    // Aggregate statistics
    long long totalCompleted = 0;
    long long totalOpSuccess = 0;
    long long totalBusinessRejected = 0;
    long long totalTimeouts = 0;
    long long totalTransportErrors = 0;
    vector<long long> allLatenciesUs;
    allLatenciesUs.reserve(totalRequests);

    for (int i = 0; i < osClientThreads; ++i) {
        const auto& s = threadStats[i];
        totalCompleted += s.completed;
        totalOpSuccess += s.opSuccess;
        totalBusinessRejected += s.businessRejected;
        totalTimeouts += s.timeouts;
        totalTransportErrors += s.transportErrors;
        allLatenciesUs.insert(allLatenciesUs.end(), s.latenciesUs.begin(), s.latenciesUs.end());
    }

    const long long totalTransportFailed = totalTimeouts + totalTransportErrors;
    const long long skippedRequests = totalRequests - (totalCompleted + totalTransportFailed);

    double throughput = (totalSeconds > 0) ? (static_cast<double>(totalCompleted) / totalSeconds) : 0.0;

    double avgLatencyMs = 0.0;
    double p95LatencyMs = 0.0;
    double p99LatencyMs = 0.0;
    double maxLatencyMs = 0.0;

    if (!allLatenciesUs.empty()) {
        sort(allLatenciesUs.begin(), allLatenciesUs.end());
        long long sumLatencies = std::accumulate(allLatenciesUs.begin(), allLatenciesUs.end(), 0LL);
        avgLatencyMs = (static_cast<double>(sumLatencies) / allLatenciesUs.size()) / 1000.0;

        size_t p95Idx = static_cast<size_t>(allLatenciesUs.size() * 0.95);
        if (p95Idx >= allLatenciesUs.size()) p95Idx = allLatenciesUs.size() - 1;
        p95LatencyMs = allLatenciesUs[p95Idx] / 1000.0;

        size_t p99Idx = static_cast<size_t>(allLatenciesUs.size() * 0.99);
        if (p99Idx >= allLatenciesUs.size()) p99Idx = allLatenciesUs.size() - 1;
        p99LatencyMs = allLatenciesUs[p99Idx] / 1000.0;

        maxLatencyMs = allLatenciesUs.back() / 1000.0;
    }

    double completionRate = (totalRequests > 0)
        ? (static_cast<double>(totalCompleted) / totalRequests) * 100.0
        : 0.0;

    const long long sampleCount = inFlightSampleCount.load();
    const double avgInFlight = (sampleCount > 0)
        ? static_cast<double>(inFlightSampleSum.load()) / sampleCount
        : 0.0;

    cout << "\n";
    cout << "====================================\n";
    cout << " Load Test Result\n";
    cout << "====================================\n";
    cout << "Requests        : " << totalRequests << "\n";
    cout << "Completed       : " << totalCompleted << "\n";
    cout << "Transport Fail  : " << totalTransportFailed << "\n";
    cout << "Operation OK    : " << totalOpSuccess << "\n";
    cout << "Operation Fail  : " << totalBusinessRejected << "\n";
    cout << fixed << setprecision(2);
    cout << "Completion Rate : " << completionRate << "%\n";
    cout << fixed << setprecision(3);
    cout << "Total Time      : " << totalSeconds << " sec\n";
    cout << fixed << setprecision(2);
    cout << "Throughput      : " << throughput << " req/sec\n";
    cout << "Average Latency : " << avgLatencyMs << " ms\n";
    cout << "------------------------------------\n";
    cout << "Logical Clients : " << logicalClients << "\n";
    cout << "OS Client Threads: " << osClientThreads << (threadCreationFailure ? " (PARTIAL CREATION)" : "") << "\n";
    cout << "Requests/Client : " << requestsPerClient << "\n";
    cout << "Planned Requests: " << totalRequests << "\n";
    cout << "Completed       : " << totalCompleted << "\n";
    cout << "Succeeded       : " << totalOpSuccess << "\n";
    cout << "Business Reject : " << totalBusinessRejected << "\n";
    cout << "Timeouts        : " << totalTimeouts << "\n";
    cout << "Transport Errors: " << totalTransportErrors << "\n";
    cout << "Skipped Requests: " << skippedRequests << "\n";
    cout << "Peak In-Flight  : " << peakInFlight.load() << "\n";
    cout << "Avg In-Flight   : " << avgInFlight << "\n";
    cout << "p95 Latency     : " << p95LatencyMs << " ms\n";
    cout << "p99 Latency     : " << p99LatencyMs << " ms\n";
    cout << "Max Latency     : " << maxLatencyMs << " ms\n";
    cout << "Server Parallel : 3 (Workers)\n";
    cout << "====================================\n";

    if (threadCreationFailure) {
        cerr << "Setup failure: " << threadCreationError << "\n";
        return 1;
    }

    return (totalTransportFailed != 0 || totalCompleted != totalRequests) ? 1 : 0;
}
