#ifndef CONSTANTS_H
#define CONSTANTS_H

#include <cstddef>
#include <limits>

namespace Constants {

constexpr int SEAT_COUNT = 20;
constexpr int DEFAULT_WORKER_COUNT = 3;
constexpr int MAX_WORKER_COUNT = 64;

constexpr long RESPONSE_TYPE_BASE = 1000;
constexpr long REQUEST_TYPE = std::numeric_limits<long>::max();
constexpr long MAX_RESPONSE_TYPE = REQUEST_TYPE - 1;
constexpr std::size_t MAX_PENDING_RESPONSES_PER_WORKER = 256;

constexpr int MIN_DELAY_MS = 50;
constexpr int MAX_DELAY_MS = 500;

constexpr int AVAILABLE = 0;

constexpr const char* QUEUE_PATH = "/ipc";
constexpr int QUEUE_PROJECT_ID = 'A';

}

#endif
