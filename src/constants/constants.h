#ifndef CONSTANTS_H
#define CONSTANTS_H

namespace Constants {

constexpr int SEAT_COUNT = 20;
constexpr int DEFAULT_WORKER_COUNT = 3;
constexpr int MAX_WORKER_COUNT = 64;

constexpr long REQUEST_TYPE = 1;

constexpr int MIN_DELAY_MS = 50;
constexpr int MAX_DELAY_MS = 500;

constexpr int AVAILABLE = 0;

constexpr const char* QUEUE_PATH = "/ipc";
constexpr int REQUEST_QUEUE_PROJECT_ID = 'A';
constexpr int RESPONSE_QUEUE_PROJECT_ID = 'B';

}

#endif
