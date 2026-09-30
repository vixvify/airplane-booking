#include "../src/ipc/message_queue.h"
#include "../src/models/message.h"
#include "../src/constants/constants.h"

#include <sys/msg.h>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

template<class F>
void expectTimeout(F operation, const char* expected) {
    const auto start = std::chrono::steady_clock::now();
    bool caught = false;
    try {
        operation();
    } catch (const std::runtime_error& error) {
        caught = std::strstr(error.what(), expected) != nullptr;
    }
    require(caught, "expected a descriptive timeout");
    require(std::chrono::steady_clock::now() - start < std::chrono::seconds(2),
            "IPC timeout exceeded its bound");
}

RequestMessage receiveRequest(int queueId) {
    RequestMessage request{};
    require(msgrcv(queueId, &request, sizeof(request) - sizeof(long),
                   Constants::REQUEST_TYPE, 0) == sizeof(request) - sizeof(long),
            "test worker could not receive a complete request");
    return request;
}

void sendResponse(const RequestMessage& request, const char* text) {
    ResponseMessage response{};
    response.mtype = static_cast<long>(request.requestId);
    response.clientId = request.clientId;
    response.requestId = request.requestId;
    std::strcpy(response.response, text);
    const auto bytes = offsetof(ResponseMessage, response) - sizeof(long)
        + std::strlen(text) + 1;
    require(msgsnd(request.replyQueueId, &response, bytes, 0) == 0,
            "test worker could not send response to private queue");
}

}

int main() {
    try {
        auto requests = ipc::MessageQueue::createRequests();

        {
            auto replies = ipc::MessageQueue::createPrivateResponse();
            const int replyId = replies.id();
            expectTimeout([&] {
                ipc::exchangeCommand(requests.id(), replyId, 1, "STATUS 1",
                                     std::chrono::milliseconds(30));
            }, "operation outcome unknown");
            const auto original = receiveRequest(requests.id());
            require(original.replyQueueId == replyId,
                    "request must carry the client's private queue ID");
            RequestMessage extra{};
            require(msgrcv(requests.id(), &extra, sizeof(extra) - sizeof(long),
                           Constants::REQUEST_TYPE, IPC_NOWAIT) == -1 && errno == ENOMSG,
                    "timeout must not resend a seat-changing request");
            replies.remove();
            msqid_ds state{};
            require(msgctl(replyId, IPC_STAT, &state) == -1 && errno == EINVAL,
                    "client must remove its private queue on exit");
        }
        std::cout << "[PASS] private queue lifecycle and no automatic retry\n";

        RequestMessage filler{};
        filler.mtype = Constants::REQUEST_TYPE;
        while (msgsnd(requests.id(), &filler,
                      sizeof(filler) - sizeof(long), IPC_NOWAIT) == 0) {}
        {
            auto replies = ipc::MessageQueue::createPrivateResponse();
            expectTimeout([&] {
                ipc::exchangeCommand(requests.id(), replies.id(), 1, "STATUS 1",
                                     std::chrono::milliseconds(30));
            }, "request was not sent");
        }
        while (msgrcv(requests.id(), &filler,
                      sizeof(filler) - sizeof(long),
                      Constants::REQUEST_TYPE, IPC_NOWAIT) >= 0) {}
        std::cout << "[PASS] bounded send when shared request queue is full\n";

        auto reply1 = ipc::MessageQueue::createPrivateResponse();
        auto reply2 = ipc::MessageQueue::createPrivateResponse();
        std::exception_ptr workerError;
        std::thread worker([&] {
            try {
                const auto first = receiveRequest(requests.id());
                const auto second = receiveRequest(requests.id());
                require(first.replyQueueId != second.replyQueueId,
                        "two clients must have different private reply queues");
                sendResponse(second, second.clientId == 7 ? "CLIENT7" : "CLIENT8");
                sendResponse(first, first.clientId == 7 ? "CLIENT7" : "CLIENT8");
            } catch (...) {
                workerError = std::current_exception();
            }
        });
        std::string result1, result2;
        std::thread client1([&] {
            result1 = ipc::exchangeCommand(requests.id(), reply1.id(), 7, "STATUS 7",
                                           std::chrono::milliseconds(500));
        });
        std::thread client2([&] {
            result2 = ipc::exchangeCommand(requests.id(), reply2.id(), 8, "STATUS 8",
                                           std::chrono::milliseconds(500));
        });
        client1.join();
        client2.join();
        worker.join();
        if (workerError) {
            std::rethrow_exception(workerError);
        }
        require(result1 == "CLIENT7" && result2 == "CLIENT8",
                "each client must receive only its own response");
        std::cout << "[PASS] independent reply queues route concurrent clients\n";

        std::thread malformedWorker([&] {
            const auto request = receiveRequest(requests.id());
            ResponseMessage malformed{};
            malformed.mtype = static_cast<long>(request.requestId);
            malformed.clientId = request.clientId;
            malformed.requestId = request.requestId;
            std::memcpy(malformed.response, "BAD", 3);
            msgsnd(request.replyQueueId, &malformed,
                   offsetof(ResponseMessage, response) - sizeof(long) + 3, 0);
        });
        bool invalidPayloadRejected = false;
        try {
            ipc::exchangeCommand(requests.id(), reply1.id(), 7, "STATUS 7",
                                 std::chrono::milliseconds(500));
        } catch (const std::runtime_error& error) {
            invalidPayloadRejected = std::strstr(error.what(), "invalid response payload") != nullptr;
        }
        malformedWorker.join();
        require(invalidPayloadRejected, "response without NUL must be rejected");
        std::cout << "[PASS] malformed compact response is rejected\n";

        ResponseMessage blocked{};
        blocked.mtype = 1;
        std::strcpy(blocked.response, "BLOCKED");
        while (msgsnd(reply1.id(), &blocked,
                      sizeof(blocked) - sizeof(long), IPC_NOWAIT) == 0) {}
        require(errno == EAGAIN, "first private queue should be full");
        std::thread independentWorker([&] {
            const auto request = receiveRequest(requests.id());
            sendResponse(request, "STILL WORKS");
        });
        const auto independent = ipc::exchangeCommand(
            requests.id(), reply2.id(), 8, "STATUS 8",
            std::chrono::milliseconds(500)
        );
        independentWorker.join();
        require(independent == "STILL WORKS",
                "a full private queue must not block another client");
        std::cout << "[PASS] full reply queue does not block another client\n";

        bool rejected = false;
        try {
            ipc::exchangeCommand(requests.id(), reply1.id(), 1,
                                 std::string("STATUS 1\0QUIT", 13));
        } catch (const std::invalid_argument&) {
            rejected = true;
        }
        require(rejected, "embedded NUL must be rejected before transport");
        std::cout << "[PASS] embedded NUL rejection\n";

    } catch (const std::exception& error) {
        std::cerr << "[FAIL] " << error.what() << "\n";
        return 1;
    }
    return 0;
}
