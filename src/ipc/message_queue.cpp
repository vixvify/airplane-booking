#include "message_queue.h"

#include "../constants/constants.h"
#include "../models/message.h"

#include <sys/msg.h>
#include <atomic>
#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstring>
#include <random>
#include <stdexcept>
#include <system_error>
#include <thread>

namespace ipc {
namespace {

[[noreturn]] void fail(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}

key_t queueKey(int projectId) {
    const key_t key = ftok(Constants::QUEUE_PATH, projectId);
    if (key == -1) {
        fail("ftok (ensure /ipc exists)");
    }
    return key;
}

MessageQueue openQueue(int projectId, const char* operation) {
    const int id = msgget(queueKey(projectId), 0);
    if (id == -1) {
        fail(operation);
    }
    return MessageQueue(id, false);
}

MessageQueue createQueue(int projectId, const char* operation) {
    const key_t key = queueKey(projectId);
    const int staleId = msgget(key, 0);
    if (staleId != -1 && msgctl(staleId, IPC_RMID, nullptr) == -1) {
        fail("remove stale message queue");
    }
    if (staleId == -1 && errno != ENOENT) {
        fail("inspect message queue");
    }

    const int id = msgget(key, IPC_CREAT | IPC_EXCL | 0666);
    if (id == -1) {
        fail(operation);
    }
    return MessageQueue(id, true);
}

std::uint64_t initialRequestId() {
    std::random_device random;
    const std::uint64_t upper = static_cast<std::uint64_t>(random()) << 32;
    const std::uint64_t lower = random();
    const std::uint64_t value = (upper | lower) & static_cast<std::uint64_t>(LONG_MAX);
    return value == 0 ? 1 : value;
}

long nextResponseType() {
    static std::atomic<std::uint64_t> next{initialRequestId()};
    while (true) {
        const std::uint64_t value =
            next.fetch_add(1, std::memory_order_relaxed)
            & static_cast<std::uint64_t>(LONG_MAX);
        if (value != 0) {
            return static_cast<long>(value);
        }
    }
}

void waitForRetry(std::chrono::steady_clock::time_point deadline, const char* message) {
    if (std::chrono::steady_clock::now() >= deadline) {
        throw std::runtime_error(message);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
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

MessageQueue MessageQueue::openRequests() {
    return openQueue(
        Constants::REQUEST_QUEUE_PROJECT_ID,
        "msgget request queue (start the server first)"
    );
}

MessageQueue MessageQueue::openResponses() {
    return openQueue(
        Constants::RESPONSE_QUEUE_PROJECT_ID,
        "msgget response queue (start the server first)"
    );
}

MessageQueue MessageQueue::createRequests() {
    return createQueue(
        Constants::REQUEST_QUEUE_PROJECT_ID,
        "create request queue"
    );
}

MessageQueue MessageQueue::createResponses() {
    return createQueue(
        Constants::RESPONSE_QUEUE_PROJECT_ID,
        "create response queue"
    );
}

std::string exchangeCommand(
    int requestQueueId, int responseQueueId,
    int clientId, const std::string& command,
    std::chrono::milliseconds timeout
) {
    if (command.size() >= sizeof(RequestMessage::command)
        || command.find('\0') != std::string::npos) {
        throw std::invalid_argument("command must contain at most 127 bytes and no NUL bytes");
    }

    const long responseType = nextResponseType();

    RequestMessage request{};
    request.mtype = Constants::REQUEST_TYPE;
    request.clientId = clientId;
    request.requestId = static_cast<std::uint64_t>(responseType);

    std::memcpy(request.command, command.c_str(), command.size() + 1);

    const auto deadline = std::chrono::steady_clock::now() + timeout;

    while (msgsnd(requestQueueId, &request, sizeof(request) - sizeof(long), IPC_NOWAIT) == -1) {
        if (errno != EAGAIN && errno != EINTR) {
            fail("send request");
        }
        waitForRetry(deadline, "request queue timeout (request was not sent)");
    }

    ResponseMessage response{};

    while (msgrcv(responseQueueId, &response, sizeof(response) - sizeof(long),
                  responseType, IPC_NOWAIT) == -1) {
        if (errno != ENOMSG && errno != EINTR) {
            fail("receive response");
        }
        waitForRetry(deadline,
            "response timeout (operation outcome unknown; check STATUS before retrying)");
    }

    if (response.clientId != clientId || response.requestId != request.requestId) {
        throw std::runtime_error("response correlation mismatch");
    }
    
    response.response[sizeof(response.response) - 1] = '\0';
    return response.response;
}

}
