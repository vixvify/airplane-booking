#include "../models/message.h"
#include "../constants/constants.h"

#include <sys/ipc.h>
#include <sys/msg.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>

using namespace std;

struct LoadTestResult {
    int success = 0;
    int failed = 0;
    long long totalLatencyMicroseconds = 0;
};

mutex resultMutex;

void sendRequest(
    int messageQueueId,
    int requestNumber,
    LoadTestResult& result
) {
    int clientId = 10000 + requestNumber;

    int seatId =
        (requestNumber % Constants::SEAT_COUNT) + 1;

    string command =
        "STATUS " + to_string(seatId);

    Message request{};

    request.mtype =
        Constants::REQUEST_TYPE;

    request.clientId =
        clientId;

    strncpy(
        request.command,
        command.c_str(),
        sizeof(request.command) - 1
    );

    request.command[
        sizeof(request.command) - 1
    ] = '\0';

    auto start =
        chrono::high_resolution_clock::now();


    if (
        msgsnd(
            messageQueueId,
            &request,
            sizeof(Message) - sizeof(long),
            0
        ) == -1
    ) {
        lock_guard<mutex> lock(resultMutex);

        result.failed++;

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
        lock_guard<mutex> lock(resultMutex);

        result.failed++;

        return;
    }

    auto end =
        chrono::high_resolution_clock::now();

    auto latency =
        chrono::duration_cast<chrono::microseconds>(
            end - start
        ).count();

   
    {
        lock_guard<mutex> lock(resultMutex);

        result.success++;

        result.totalLatencyMicroseconds += latency;
    }
}

int main(int argc, char* argv[]) {

    if (argc != 3) {
        cout
            << "Usage: ./load_test "
            << "<total_requests> "
            << "<concurrency>\n";

        return 1;
    }

    int totalRequests;
    int concurrency;

    try {
        totalRequests = stoi(argv[1]);
        concurrency = stoi(argv[2]);
    }
    catch (...) {
        cout << "Invalid arguments\n";
        return 1;
    }

    if (
        totalRequests <= 0 ||
        concurrency <= 0
    ) {
        cout
            << "Arguments must be greater than 0\n";

        return 1;
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

    int messageQueueId = msgget(
        key,
        0666
    );

    if (messageQueueId == -1) {
        perror("msgget");

        cout
            << "Make sure server is running.\n";

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

    cout << "====================================\n\n";

    LoadTestResult result;

    auto testStart =
        chrono::high_resolution_clock::now();

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
                ref(result)
            );

            requestNumber++;
        }

        for (auto& thread : threads) {
            thread.join();
        }
    }

    auto testEnd =
        chrono::high_resolution_clock::now();

    double totalSeconds =
        chrono::duration<double>(
            testEnd - testStart
        ).count();

    double throughput = 0;

    if (totalSeconds > 0) {
        throughput =
            result.success / totalSeconds;
    }

    double averageLatencyMs = 0;

    if (result.success > 0) {
        averageLatencyMs =
            (
                static_cast<double>(
                    result.totalLatencyMicroseconds
                )
                / result.success
            )
            / 1000.0;
    }

    double successRate =
        (
            static_cast<double>(result.success)
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
        << "Successful      : "
        << result.success
        << "\n";

    cout
        << "Failed          : "
        << result.failed
        << "\n";

    cout
        << "Success Rate    : "
        << successRate
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
