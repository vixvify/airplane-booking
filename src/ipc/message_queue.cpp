#include "message_queue.h"

#include "../constants/constants.h"
#include "../models/message.h"

#include <sys/msg.h>
#include <cerrno>
#include <cstring>
#include <stdexcept>
#include <system_error>
#include <thread>

namespace ipc {
namespace {

[[noreturn]] void fail(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}

key_t requestKey() {
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

MessageQueue MessageQueue::createReply() {
    const int id = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
    if (id == -1) {
        fail("msgget reply queue");
    }
    return MessageQueue(id, true);
}

MessageQueue MessageQueue::openRequests() {
    const int id = msgget(requestKey(), 0);
    if (id == -1) {
        fail("msgget request queue (start the server first)");
    }
    return MessageQueue(id, false);
}

MessageQueue MessageQueue::createRequests() {
    const key_t key = requestKey();
    const int staleId = msgget(key, 0);
    if (staleId != -1 && msgctl(staleId, IPC_RMID, nullptr) == -1) {
        fail("remove stale request queue");
    }
    if (staleId == -1 && errno != ENOENT) {
        fail("inspect request queue");
    }

    const int id = msgget(key, IPC_CREAT | IPC_EXCL | 0666);
    if (id == -1) {
        fail("create request queue");
    }
    return MessageQueue(id, true);
}

std::string exchangeCommand(
    int requestQueueId, int clientId, const std::string& command,
    std::chrono::milliseconds timeout
) {
    if (command.size() >= sizeof(RequestMessage::command)
        || command.find('\0') != std::string::npos) {
        throw std::invalid_argument("command must contain at most 127 bytes and no NUL bytes");
    }

    auto replyQueue = MessageQueue::createReply();
    RequestMessage request{};
    request.mtype = Constants::REQUEST_TYPE;
    request.clientId = clientId;
    request.replyQueueId = replyQueue.id();
    std::memcpy(request.command, command.c_str(), command.size() + 1);
    const auto deadline = std::chrono::steady_clock::now() + timeout;

    while (msgsnd(requestQueueId, &request, sizeof(request) - sizeof(long), IPC_NOWAIT) == -1) {
        if (errno != EAGAIN && errno != EINTR) {
            fail("send request");
        }
        waitForRetry(deadline, "request queue timeout (request was not sent)");
    }

    ResponseMessage response{};
    while (msgrcv(replyQueue.id(), &response, sizeof(response) - sizeof(long),
                  Constants::RESPONSE_TYPE_BASE + clientId, IPC_NOWAIT) == -1) {
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
