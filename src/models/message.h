#ifndef MESSAGE_H
#define MESSAGE_H

#include <cstdint>

struct RequestMessage {
    long mtype;
    int clientId;
    std::uint64_t requestId;
    char command[128];
};

struct ResponseMessage {
    long mtype;
    int clientId;
    std::uint64_t requestId;
    char response[2048];
};

#endif
