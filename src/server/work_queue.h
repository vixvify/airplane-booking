#pragma once

#include "../models/message.h"

#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>

class WorkQueue {
public:
    bool push(const RequestMessage& request) {
        std::unique_lock<std::mutex> lock(mutex_);
        spaceAvailable_.wait(lock, [&] { return stopped_ || pending_.size() < CAPACITY; });
        if (stopped_) {
            return false;
        }
        pending_.push_back(request);
        workAvailable_.notify_one();
        return true;
    }

    bool pop(RequestMessage& request) {
        std::unique_lock<std::mutex> lock(mutex_);
        workAvailable_.wait(lock, [&] { return stopped_ || !pending_.empty(); });
        if (stopped_) {
            return false;
        }
        request = pending_.front();
        pending_.pop_front();
        spaceAvailable_.notify_one();
        return true;
    }

    void stop() {
        std::lock_guard<std::mutex> lock(mutex_);
        stopped_ = true;
        pending_.clear();
        workAvailable_.notify_all();
        spaceAvailable_.notify_all();
    }

private:
    static constexpr std::size_t CAPACITY = 1024;
    std::mutex mutex_;
    std::condition_variable workAvailable_;
    std::condition_variable spaceAvailable_;
    std::deque<RequestMessage> pending_;
    bool stopped_ = false;
};
