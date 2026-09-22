#ifndef MESSAGE_H
#define MESSAGE_H

#include <cstdint>

struct RequestMessage {
    long mtype;
    int clientId;
    long responseType;
    std::int64_t responseDeadlineEpochMs;
    char command[128];
};

struct ResponseMessage {
    long mtype;
    int clientId;
    std::int64_t responseDeadlineEpochMs;
    char response[2048];
};

#endif
