#pragma once

#include <atomic>
#include <chrono>
#include <string>

namespace ipc {

class MessageQueue {
public:
    MessageQueue(int id, bool owner) : id_(id), owner_(owner) {}
    ~MessageQueue();
    MessageQueue(const MessageQueue&) = delete;
    MessageQueue& operator=(const MessageQueue&) = delete;

    static MessageQueue openRequests();
    static MessageQueue openResponses();
    static MessageQueue createRequests();
    static MessageQueue createResponses();
    int id() const { return id_; }
    void remove();

private:
    int id_;
    bool owner_;
};

struct InFlightTracker {
    std::atomic<int>* counter = nullptr;
    std::atomic<int>* peak = nullptr;

    void onSent() {
        if (counter) {
            int cur = counter->fetch_add(1, std::memory_order_relaxed) + 1;
            if (peak) {
                int prev = peak->load(std::memory_order_relaxed);
                while (cur > prev && !peak->compare_exchange_weak(prev, cur, std::memory_order_relaxed)) {}
            }
        }
    }

    void onReceived() {
        if (counter) {
            counter->fetch_sub(1, std::memory_order_relaxed);
        }
    }
};

std::string exchangeCommand(
    int requestQueueId, int responseQueueId,
    int clientId, const std::string& command,
    std::chrono::milliseconds timeout = std::chrono::seconds(10),
    InFlightTracker* tracker = nullptr
);

}

