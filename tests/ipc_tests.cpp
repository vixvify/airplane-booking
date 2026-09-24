#include "../src/ipc/message_queue.h"
#include "../src/models/message.h"
#include "../src/constants/constants.h"

#include <sys/msg.h>
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
    require(
        std::chrono::steady_clock::now() - start < std::chrono::seconds(2),
        "IPC timeout exceeded its bound"
    );
}

}

int main() {
    try {
        auto requests = ipc::MessageQueue::createRequests();
        auto responses = ipc::MessageQueue::createResponses();

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

        // Drain the filler messages so the queue can be reused.
        while (
            msgrcv(
                requests.id(), &filler, sizeof(filler) - sizeof(long),
                Constants::REQUEST_TYPE, IPC_NOWAIT
            ) >= 0
        ) {}

        // The response mtype is the request ID, so an unrelated response remains
        // in the shared response queue and cannot be consumed by this request.
        std::exception_ptr workerError;
        std::thread worker([&] {
            try {
                RequestMessage request{};
                require(
                    msgrcv(
                        requests.id(), &request,
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
                        responses.id(), &unrelated,
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
                        responses.id(), &expected,
                        offsetof(ResponseMessage, response) - sizeof(long)
                            + std::strlen(expected.response) + 1,
                        0
                    ) == 0,
                    "test worker could not send compact response"
                );
            } catch (...) {
                workerError = std::current_exception();
            }
        });

        const auto result = ipc::exchangeCommand(
            requests.id(), responses.id(), 7, "STATUS 7",
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
                responses.id(), &leftover,
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

        // A shortened response is valid only if its transmitted text is NUL-terminated.
        std::thread malformedWorker([&] {
            RequestMessage request{};
            if (msgrcv(requests.id(), &request,
                       sizeof(request) - sizeof(long),
                       Constants::REQUEST_TYPE, 0) < 0) {
                return;
            }
            ResponseMessage malformed{};
            malformed.mtype = static_cast<long>(request.requestId);
            malformed.clientId = request.clientId;
            malformed.requestId = request.requestId;
            std::memcpy(malformed.response, "BAD", 3);
            msgsnd(responses.id(), &malformed,
                   offsetof(ResponseMessage, response) - sizeof(long) + 3, 0);
        });
        bool invalidPayloadRejected = false;
        try {
            ipc::exchangeCommand(requests.id(), responses.id(), 7, "STATUS 7",
                                 std::chrono::milliseconds(500));
        } catch (const std::runtime_error& error) {
            invalidPayloadRejected = std::strstr(error.what(), "invalid response payload") != nullptr;
        }
        malformedWorker.join();
        require(invalidPayloadRejected, "response without a NUL terminator must be rejected");
        std::cout << "[PASS] malformed compact response is rejected\n";

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
