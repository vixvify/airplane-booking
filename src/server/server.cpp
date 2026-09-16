#include "worker.h"

#include "../constants/constants.h"
#include "../reservation/reservation.h"
#include "../utils/cli_parser.h"

#include <sys/ipc.h>
#include <sys/msg.h>

#include <csignal>
#include <iostream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

using namespace std;

namespace {

int g_messageQueueId = -1;

void handleShutdown(int signalNumber) {
    cout << "\nShutting down server (Signal " << signalNumber << ")...\n";
    if (g_messageQueueId != -1) {
        msgctl(g_messageQueueId, IPC_RMID, nullptr);
        cout << "Message Queue " << g_messageQueueId << " removed successfully.\n";
    }
    _exit(0);
}

void printUsage(const char* program) {
    cerr
        << "Usage: " << program
        << " [sync|nosync] [worker_count]\n";
}

}

int main(int argc, char* argv[]) {
    signal(SIGINT, handleShutdown);
    signal(SIGTERM, handleShutdown);

    bool synchronizationEnabled = true;
    int workerCount = Constants::DEFAULT_WORKER_COUNT;

    if (argc > 3) {
        printUsage(argv[0]);
        return 1;
    }

    if (argc >= 2) {
        string mode = argv[1];

        if (mode == "sync") {
            synchronizationEnabled = true;
        }
        else if (mode == "nosync") {
            synchronizationEnabled = false;
        }
        else {
            printUsage(argv[0]);
            return 1;
        }
    }

    if (
        argc == 3
        && (
            !parsePositiveInt(argv[2], workerCount)
            || workerCount > 64
        )
    ) {
        cerr << "Error: worker_count must be between 1 and 64\n";
        printUsage(argv[0]);
        return 1;
    }

    setSynchronization(synchronizationEnabled);

    key_t key = ftok(
        Constants::QUEUE_PATH,
        Constants::QUEUE_PROJECT_ID
    );

    if (key == -1) {
        perror("ftok");
        return 1;
    }

    int oldQueueId = msgget(key, 0666);
    if (oldQueueId != -1) {
        msgctl(oldQueueId, IPC_RMID, nullptr);
    }

    int messageQueueId = msgget(
        key,
        IPC_CREAT | IPC_EXCL | 0666
    );

    if (messageQueueId == -1) {
        perror("msgget");
        return 1;
    }

    g_messageQueueId = messageQueueId;

    cout
        << "Airplane Reservation Server started\n"
        << "Message Queue ID: " << messageQueueId << "\n"
        << "Workers: " << workerCount << "\n"
        << "Synchronization: "
        << (synchronizationEnabled ? "enabled" : "disabled")
        << "\n";

    vector<thread> workers;

    for (int workerId = 1; workerId <= workerCount; workerId++) {
        workers.emplace_back(
            worker,
            workerId,
            messageQueueId
        );
    }

    for (thread& workerThread : workers) {
        workerThread.join();
    }

    return 0;
}
