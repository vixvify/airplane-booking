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

    static MessageQueue openSharedQueue();
    static MessageQueue createSharedQueue();
    int id() const { return id_; }
    void remove();

private:
    int id_;
    bool owner_;
};

std::string exchangeCommand(
    int queueId, int clientId, const std::string& command,
    std::chrono::milliseconds timeout = std::chrono::seconds(10)
);

}
