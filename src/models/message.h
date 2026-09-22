#ifndef MESSAGE_H
#define MESSAGE_H

struct RequestMessage {
    long mtype;
    int clientId;
    long responseType;
    char command[128];
};

struct ResponseMessage {
    long mtype;
    int clientId;
    char response[2048];
};

#endif
