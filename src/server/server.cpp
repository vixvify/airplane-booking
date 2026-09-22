#include "worker.h"
#include "../constants/constants.h"
#include "../ipc/message_queue.h"
#include "../ipc/server_lock.h"
#include "../reservation/reservation.h"
#include "../utils/cli_parser.h"

#include <csignal>
#include <iostream>
#include <pthread.h>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

namespace {
void printUsage(const char* program) {
    std::cerr << "Usage: " << program << " [sync|nosync] [worker_count]\n";
}
}

int main(int argc, char* argv[]) {
    const std::string mode = argc >= 2 ? argv[1] : "sync";
    int workerCount = Constants::DEFAULT_WORKER_COUNT;
    if (argc > 3 || (mode != "sync" && mode != "nosync")) {
        printUsage(argv[0]);
        return 1;
    }
    if (argc == 3 && (!parsePositiveInt(argv[2], workerCount)
                     || workerCount > Constants::MAX_WORKER_COUNT)) {
        std::cerr << "Error: worker_count must be between 1 and "
                  << Constants::MAX_WORKER_COUNT << "\n";
        printUsage(argv[0]);
        return 1;
    }

    try {
        ipc::ServerLock serverLock;
        auto requests = ipc::MessageQueue::createRequests();
        auto responses = ipc::MessageQueue::createResponses();
        setSynchronization(mode == "sync");

        sigset_t signals;
        sigemptyset(&signals);
        sigaddset(&signals, SIGINT);
        sigaddset(&signals, SIGTERM);
        const int maskError = pthread_sigmask(SIG_BLOCK, &signals, nullptr);
        if (maskError != 0) {
            throw std::system_error(maskError, std::generic_category(), "pthread_sigmask");
        }

        std::cout << std::unitbuf
                  << "Airplane Reservation Server started\n"
                  << "Request Queue ID: " << requests.id() << "\n"
                  << "Response Queue ID: " << responses.id() << "\n"
                  << "Workers: " << workerCount << "\n"
                  << "Synchronization: " << (mode == "sync" ? "enabled" : "disabled") << "\n";

        std::vector<std::thread> workers;
        try {
            for (int workerId = 1; workerId <= workerCount; ++workerId) {
                workers.emplace_back(
                    worker, workerId, requests.id(), responses.id()
                );
            }
            int signalNumber = 0;
            const int waitError = sigwait(&signals, &signalNumber);
            if (waitError != 0) {
                throw std::system_error(waitError, std::generic_category(), "sigwait");
            }
            std::cout << "Shutting down server (Signal " << signalNumber << ")...\n";
        } catch (...) {
            requests.remove();
            for (auto& thread : workers) {
                thread.join();
            }
            throw;
        }
        requests.remove();
        for (auto& thread : workers) {
            thread.join();
        }
        responses.remove();
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << "\n";
        return 1;
    }
    return 0;
}
