#include "../src/ipc/message_queue.h"
#include "../src/models/message.h"
#include "../src/constants/constants.h"

#include <sys/msg.h>
#include <chrono>
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
    require(
        std::chrono::steady_clock::now() - start < std::chrono::seconds(2),
        "IPC timeout exceeded its bound"
    );
}

}

int main() {
    try {
        auto requests = ipc::MessageQueue::createPrivate();
        auto responses = ipc::MessageQueue::createPrivate();

        // No worker: a sent request must time out instead of waiting forever.
        expectTimeout([&] {
            ipc::exchangeCommand(
                requests.id(), responses.id(), 1, "STATUS 1",
                std::chrono::milliseconds(30)
            );
        }, "operation outcome unknown");

        RequestMessage pending{};
        require(
            msgrcv(
                requests.id(), &pending, sizeof(pending) - sizeof(long),
                Constants::REQUEST_TYPE, IPC_NOWAIT
            ) >= 0,
            "request was not sent"
        );
        require(pending.requestId != 0, "request ID must be positive");
        std::cout << "[PASS] bounded response wait on the shared response queue\n";

        RequestMessage filler{};
        filler.mtype = Constants::REQUEST_TYPE;
        while (
            msgsnd(
                requests.id(), &filler, sizeof(filler) - sizeof(long),
                IPC_NOWAIT
            ) == 0
        ) {}
        expectTimeout([&] {
            ipc::exchangeCommand(
                requests.id(), responses.id(), 1, "STATUS 1",
                std::chrono::milliseconds(30)
            );
        }, "request was not sent");
        std::cout << "[PASS] bounded request wait when queue is full\n";

        // The response mtype is the request ID, so an unrelated response remains
        // in the shared response queue and cannot be consumed by this request.
        auto routingRequests = ipc::MessageQueue::createPrivate();
        auto routingResponses = ipc::MessageQueue::createPrivate();
        std::exception_ptr workerError;
        std::thread worker([&] {
            try {
                RequestMessage request{};
                require(
                    msgrcv(
                        routingRequests.id(), &request,
                        sizeof(request) - sizeof(long),
                        Constants::REQUEST_TYPE, 0
                    ) >= 0,
                    "test worker could not receive request"
                );

                const std::uint64_t unrelatedId =
                    request.requestId == 1 ? 2 : request.requestId - 1;
                ResponseMessage unrelated{};
                unrelated.mtype = static_cast<long>(unrelatedId);
                unrelated.clientId = request.clientId;
                unrelated.requestId = unrelatedId;
                std::strcpy(unrelated.response, "WRONG");
                require(
                    msgsnd(
                        routingResponses.id(), &unrelated,
                        sizeof(unrelated) - sizeof(long), 0
                    ) == 0,
                    "test worker could not send unrelated response"
                );

                ResponseMessage expected{};
                expected.mtype = static_cast<long>(request.requestId);
                expected.clientId = request.clientId;
                expected.requestId = request.requestId;
                std::strcpy(expected.response, "EXPECTED");
                require(
                    msgsnd(
                        routingResponses.id(), &expected,
                        sizeof(expected) - sizeof(long), 0
                    ) == 0,
                    "test worker could not send expected response"
                );
            } catch (...) {
                workerError = std::current_exception();
            }
        });

        const auto result = ipc::exchangeCommand(
            routingRequests.id(), routingResponses.id(), 7, "STATUS 7",
            std::chrono::milliseconds(500)
        );
        worker.join();
        if (workerError) {
            std::rethrow_exception(workerError);
        }
        require(result == "EXPECTED", "request consumed the wrong response");

        ResponseMessage leftover{};
        require(
            msgrcv(
                routingResponses.id(), &leftover,
                sizeof(leftover) - sizeof(long),
                0, IPC_NOWAIT
            ) >= 0,
            "unrelated response should remain queued"
        );
        require(
            std::strcmp(leftover.response, "WRONG") == 0,
            "unexpected response remained in the queue"
        );
        std::cout << "[PASS] request ID routes responses on a shared queue\n";

        bool rejected = false;
        try {
            ipc::exchangeCommand(
                requests.id(), responses.id(), 1,
                std::string("STATUS 1\0QUIT", 13)
            );
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
