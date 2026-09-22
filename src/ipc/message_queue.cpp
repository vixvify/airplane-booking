#include "message_queue.h"

#include "../constants/constants.h"
#include "../models/message.h"

#include <sys/msg.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <system_error>
#include <thread>

namespace ipc {
namespace {

[[noreturn]] void fail(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}

key_t sharedQueueKey() {
    const key_t key = ftok(Constants::QUEUE_PATH, Constants::QUEUE_PROJECT_ID);
    if (key == -1) {
        fail("ftok (ensure /ipc exists)");
    }
    return key;
}

void waitForRetry(std::chrono::steady_clock::time_point deadline, const char* message) {
    if (std::chrono::steady_clock::now() >= deadline) {
        throw std::runtime_error(message);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
}

long nextResponseType() {
    constexpr unsigned long sequenceBits = 20;
    constexpr unsigned long sequenceLimit = 1UL << sequenceBits;
    static std::atomic<unsigned long> nextSequence{0};

    const unsigned long sequence = nextSequence.fetch_add(1, std::memory_order_relaxed);
    if (sequence >= sequenceLimit) {
        throw std::runtime_error("response type sequence exhausted; restart the client process");
    }

    const unsigned long processId = static_cast<unsigned long>(getpid());
    const unsigned long maxType = static_cast<unsigned long>(Constants::MAX_RESPONSE_TYPE);
    if (processId > (maxType - Constants::RESPONSE_TYPE_BASE - sequence) / sequenceLimit) {
        throw std::runtime_error("process ID cannot be represented in a response message type");
    }

    return static_cast<long>(
        Constants::RESPONSE_TYPE_BASE + (processId * sequenceLimit) + sequence
    );
}

std::int64_t currentEpochMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

}

MessageQueue::~MessageQueue() {
    remove();
}

void MessageQueue::remove() {
    if (owner_ && id_ != -1) {
        msgctl(id_, IPC_RMID, nullptr);
        id_ = -1;
    }
}

MessageQueue MessageQueue::openSharedQueue() {
    const int id = msgget(sharedQueueKey(), 0);
    if (id == -1) {
        fail("msgget shared queue (start the server first)");
    }
    return MessageQueue(id, false);
}

MessageQueue MessageQueue::createSharedQueue() {
    const key_t key = sharedQueueKey();
    const int staleId = msgget(key, 0);
    if (staleId != -1 && msgctl(staleId, IPC_RMID, nullptr) == -1) {
        fail("remove stale shared queue");
    }
    if (staleId == -1 && errno != ENOENT) {
        fail("inspect shared queue");
    }

    const int id = msgget(key, IPC_CREAT | IPC_EXCL | 0666);
    if (id == -1) {
        fail("create shared queue");
    }
    return MessageQueue(id, true);
}

std::string exchangeCommand(
    int queueId, int clientId, const std::string& command,
    std::chrono::milliseconds timeout
) {
    if (command.size() >= sizeof(RequestMessage::command)
        || command.find('\0') != std::string::npos) {
        throw std::invalid_argument("command must contain at most 127 bytes and no NUL bytes");
    }

    RequestMessage request{};
    request.mtype = Constants::REQUEST_TYPE;
    request.clientId = clientId;
    request.responseType = nextResponseType();
    request.responseDeadlineEpochMs = currentEpochMilliseconds() + timeout.count();
    std::memcpy(request.command, command.c_str(), command.size() + 1);
    const auto deadline = std::chrono::steady_clock::now() + timeout;

    while (msgsnd(queueId, &request, sizeof(request) - sizeof(long), IPC_NOWAIT) == -1) {
        if (errno != EAGAIN && errno != EINTR) {
            fail("send request");
        }
        waitForRetry(deadline, "request queue timeout (request was not sent)");
    }

    ResponseMessage response{};
    while (msgrcv(queueId, &response, sizeof(response) - sizeof(long),
                  request.responseType, IPC_NOWAIT) == -1) {
        if (errno != ENOMSG && errno != EINTR) {
            fail("receive response");
        }
        waitForRetry(deadline,
            "response timeout (operation outcome unknown; check STATUS before retrying)");
    }
    response.response[sizeof(response.response) - 1] = '\0';
    return response.response;
}

}
