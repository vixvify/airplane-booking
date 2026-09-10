#include "../constants/constants.h"
#include "../models/message.h"
#include "../utils/cli_parser.h"

#include <sys/ipc.h>
#include <sys/msg.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace std;

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

void recordTransportFailure(LoadTestResult& result) {
    lock_guard<mutex> lock(resultMutex);
    result.transportFailed++;
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

    Message request{};
    request.mtype = Constants::REQUEST_TYPE;
    request.clientId = clientId;

    strncpy(
        request.command,
        command.c_str(),
        sizeof(request.command) - 1
    );
    request.command[sizeof(request.command) - 1] = '\0';

    auto start = chrono::high_resolution_clock::now();

    if (
        msgsnd(
            messageQueueId,
            &request,
            sizeof(Message) - sizeof(long),
            0
        ) == -1
    ) {
        recordTransportFailure(result);
        return;
    }

    Message response{};
    long responseType =
        Constants::RESPONSE_TYPE_BASE + clientId;

    if (
        msgrcv(
            messageQueueId,
            &response,
            sizeof(Message) - sizeof(long),
            responseType,
            0
        ) == -1
    ) {
        recordTransportFailure(result);
        return;
    }

    auto end = chrono::high_resolution_clock::now();
    auto latency = chrono::duration_cast<chrono::microseconds>(
        end - start
    ).count();

    recordResponse(
        result,
        operation,
        response.response,
        latency
    );
}

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

    key_t key = ftok(
        Constants::QUEUE_PATH,
        Constants::QUEUE_PROJECT_ID
    );

    if (key == -1) {
        perror("ftok");
        return 1;
    }

    int messageQueueId = msgget(key, 0666);

    if (messageQueueId == -1) {
        perror("msgget");
        cout << "Make sure server is running.\n";
        return 1;
    }

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
    auto testStart = chrono::high_resolution_clock::now();
    int requestNumber = 0;

    while (requestNumber < totalRequests) {
        vector<thread> threads;
        int batchSize = min(
            concurrency,
            totalRequests - requestNumber
        );

        for (int i = 0; i < batchSize; i++) {
            threads.emplace_back(
                sendRequest,
                messageQueueId,
                requestNumber,
                operation,
                fixedSeatId,
                ref(result)
            );

            requestNumber++;
        }

        for (auto& thread : threads) {
            thread.join();
        }
    }

    auto testEnd = chrono::high_resolution_clock::now();
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

    return 0;
}
