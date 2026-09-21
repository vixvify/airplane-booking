#include "../constants/constants.h"
#include "../ipc/message_queue.h"
#include "../utils/cli_parser.h"
#include <atomic>
#include <chrono>
#include <limits>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

struct LoadTestResult {
    long long completed = 0;
    long long transportFailed = 0;
    long long operationSuccess = 0;
    long long operationFailed = 0;
    long long totalLatencyMicroseconds = 0;
};

mutex resultMutex;

enum class Operation {
    STATUS,
    RESERVE,
    CANCEL
};

bool parseOperation(
    const string& value,
    Operation& operation
) {
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

    return false;
}

string operationName(Operation operation) {
    if (operation == Operation::STATUS) {
        return "STATUS";
    }

    if (operation == Operation::RESERVE) {
        return "RESERVE";
    }

    return "CANCEL";
}

string makeCommand(
    Operation operation,
    int seatId
) {
    return
        operationName(operation)
        + " "
        + to_string(seatId);
}

int getSeatId(
    int requestNumber,
    int fixedSeatId
) {
    if (fixedSeatId > 0) {
        return fixedSeatId;
    }

    return (requestNumber % Constants::SEAT_COUNT) + 1;
}

void recordResponse(
    LoadTestResult& result,
    Operation operation,
    const string& response,
    long long latencyMicroseconds
) {
    lock_guard<mutex> lock(resultMutex);

    result.completed++;
    result.totalLatencyMicroseconds += latencyMicroseconds;

    if (
        operation == Operation::STATUS
        || response.rfind("SUCCESS:", 0) == 0
    ) {
        result.operationSuccess++;
    }
    else {
        result.operationFailed++;
    }
}

void sendRequest(
    int messageQueueId,
    int requestNumber,
    Operation operation,
    int fixedSeatId,
    LoadTestResult& result
) {
    int clientId = 10000 + requestNumber;
    int seatId = getSeatId(requestNumber, fixedSeatId);
    string command = makeCommand(operation, seatId);

    const auto start = chrono::steady_clock::now();
    try {
        const auto response = ipc::exchangeCommand(messageQueueId, clientId, command);
        const auto latency = chrono::duration_cast<chrono::microseconds>(
            chrono::steady_clock::now() - start
        ).count();
        recordResponse(result, operation, response, latency);
    } catch (const exception& error) {
        lock_guard<mutex> lock(resultMutex);
        if (result.transportFailed++ == 0) {
            cerr << "Transport error: " << error.what() << "\n";
        }
    }
}

} // namespace

int main(int argc, char* argv[]) {
    if (argc != 4 && argc != 5) {
        cout
            << "Usage: ./load_test "
            << "<total_requests> "
            << "<concurrency> "
            << "<STATUS|RESERVE|CANCEL> "
            << "[seat_id]\n";

        return 1;
    }

    int totalRequests;
    int concurrency;
    Operation operation;
    int fixedSeatId = 0;

    if (
        !parsePositiveInt(argv[1], totalRequests)
        || !parsePositiveInt(argv[2], concurrency)
        || !parseOperation(argv[3], operation)
    ) {
        cout << "Invalid arguments\n";
        return 1;
    }

    if (argc == 5) {
        if (
            !parsePositiveInt(argv[4], fixedSeatId)
            || fixedSeatId > Constants::SEAT_COUNT
        ) {
            cout
                << "Seat ID must be between 1 and "
                << Constants::SEAT_COUNT
                << "\n";
            return 1;
        }
    }

    if (concurrency > totalRequests) {
        concurrency = totalRequests;
    }

    if (totalRequests > numeric_limits<int>::max() - 10000) {
        cerr << "Too many requests for the client ID range\n";
        return 1;
    }
    int messageQueueId;
    try {
        messageQueueId = ipc::MessageQueue::openRequests().id();
    } catch (const exception& error) {
        cerr << error.what() << "\nMake sure server is running.\n";
        return 1;
    }
    cout << unitbuf;
    cout << "\n";
    cout << "====================================\n";
    cout << " Airplane Reservation Load Test\n";
    cout << "====================================\n";
    cout
        << "Total Requests : "
        << totalRequests
        << "\n";
    cout
        << "Concurrency    : "
        << concurrency
        << "\n";
    cout
        << "Operation      : "
        << operationName(operation)
        << "\n";

    if (fixedSeatId > 0) {
        cout
            << "Target Seat    : "
            << fixedSeatId
            << "\n";
    }
    else {
        cout << "Target Seat    : round-robin 1-20\n";
    }

    cout << "====================================\n\n";

    LoadTestResult result;
    auto testStart = chrono::steady_clock::now();
    atomic<long long> nextRequest{0};
    vector<thread> threads;
    bool launchFailed = false;
    try {
        for (int i = 0; i < concurrency; ++i) {
            threads.emplace_back([&] {
                while (true) {
                    const auto requestNumber = nextRequest.fetch_add(1);
                    if (requestNumber >= totalRequests) {
                        break;
                    }
                    sendRequest(messageQueueId, static_cast<int>(requestNumber),
                                operation, fixedSeatId, result);
                }
            });
        }
    } catch (const exception& error) {
        cerr << "Unable to start load-test threads: " << error.what() << "\n";
        launchFailed = true;
    }
    for (auto& thread : threads) {
        thread.join();
    }

    auto testEnd = chrono::steady_clock::now();
    double totalSeconds = chrono::duration<double>(
        testEnd - testStart
    ).count();

    double throughput = 0;

    if (totalSeconds > 0) {
        throughput = result.completed / totalSeconds;
    }

    double averageLatencyMs = 0;

    if (result.completed > 0) {
        averageLatencyMs =
            (
                static_cast<double>(
                    result.totalLatencyMicroseconds
                )
                / result.completed
            )
            / 1000.0;
    }

    double completionRate =
        (
            static_cast<double>(result.completed)
            / totalRequests
        ) * 100.0;

    cout << "\n";
    cout << "====================================\n";
    cout << " Load Test Result\n";
    cout << "====================================\n";
    cout
        << "Requests        : "
        << totalRequests
        << "\n";
    cout
        << "Completed       : "
        << result.completed
        << "\n";
    cout
        << "Transport Fail  : "
        << result.transportFailed
        << "\n";
    cout
        << "Operation OK    : "
        << result.operationSuccess
        << "\n";
    cout
        << "Operation Fail  : "
        << result.operationFailed
        << "\n";
    cout
        << "Completion Rate : "
        << completionRate
        << "%\n";
    cout
        << "Total Time      : "
        << totalSeconds
        << " sec\n";
    cout
        << "Throughput      : "
        << throughput
        << " req/sec\n";
    cout
        << "Average Latency : "
        << averageLatencyMs
        << " ms\n";
    cout << "====================================\n";

    return launchFailed || result.transportFailed != 0 ? 1 : 0;
}
