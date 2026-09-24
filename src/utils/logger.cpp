#include "logger.h"

#include <cstdlib>
#include <iostream>
#include <mutex>
#include <string_view>

using namespace std;

mutex logMutex;

int sequenceNumber = 0;

void logMessage(
    int workerId,
    int clientId,
    const string& message
) {
    static const bool verbose = [] {
        const char* mode = std::getenv("AIRPLANE_LOG_MODE");
        return mode == nullptr || std::string_view(mode) != "quiet";
    }();
    if (!verbose) {
        return;
    }

    lock_guard<mutex> lock(logMutex);

    sequenceNumber++;

    cout
        << "[SEQ " << sequenceNumber << "] "
        << "[Worker-" << workerId << "] "
        << "[Client-" << clientId << "] "
        << message
        << endl;
}
