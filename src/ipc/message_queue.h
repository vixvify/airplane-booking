#pragma once

#include <chrono>
#include <string>

namespace ipc {

class MessageQueue {
public:
    MessageQueue(int id, bool owner) : id_(id), owner_(owner) {}
    ~MessageQueue();
    MessageQueue(const MessageQueue&) = delete;
    MessageQueue& operator=(const MessageQueue&) = delete;

    static MessageQueue createReply();
    static MessageQueue openRequests();
    static MessageQueue createRequests();
    int id() const { return id_; }
    void remove();

private:
    int id_;
    bool owner_;
};

std::string exchangeCommand(
    int requestQueueId, int clientId, const std::string& command,
    std::chrono::milliseconds timeout = std::chrono::seconds(10)
);

}
