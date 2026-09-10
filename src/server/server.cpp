#include "worker.h"

#include "../constants/constants.h"
#include "../reservation/reservation.h"
#include "../utils/cli_parser.h"

#include <sys/ipc.h>
#include <sys/msg.h>

#include <iostream>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

void printUsage(const char* program) {
    cerr
        << "Usage: " << program
        << " [sync|nosync] [worker_count]\n";
}

}

int main(int argc, char* argv[]) {
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
        && !parsePositiveInt(argv[2], workerCount)
    ) {
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

    int messageQueueId = msgget(
        key,
        IPC_CREAT | 0666
    );

    if (messageQueueId == -1) {
        perror("msgget");
        return 1;
    }

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
