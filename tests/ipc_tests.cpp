#include "../src/ipc/message_queue.h"
#include "../src/models/message.h"
#include "../src/constants/constants.h"

#include <sys/msg.h>
#include <chrono>
#include <cstring>
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
template<class F>
void expectTimeout(F operation, const char* expected) {
    const auto start = std::chrono::steady_clock::now();
    bool caught = false;
    try { operation(); }
    catch (const std::runtime_error& error) {
        caught = std::strstr(error.what(), expected) != nullptr;
    }
    require(caught, "expected a descriptive timeout");
    require(std::chrono::steady_clock::now() - start < std::chrono::seconds(2),
            "IPC timeout exceeded its bound");
}

class QueueGuard {
public:
    QueueGuard() : id_(msgget(IPC_PRIVATE, IPC_CREAT | 0600)) {
        if (id_ == -1) throw std::runtime_error("could not create test queue");
    }
    ~QueueGuard() { msgctl(id_, IPC_RMID, nullptr); }
    int id() const { return id_; }

private:
    int id_;
};
}

int main() {
    try {
        QueueGuard requests;
        // No worker: a successfully sent request must time out, not hang forever.
        expectTimeout([&] {
            ipc::exchangeCommand(requests.id(), 1, "STATUS 1", std::chrono::milliseconds(30));
        }, "operation outcome unknown");
        RequestMessage pending{};
        require(msgrcv(requests.id(), &pending, sizeof(pending) - sizeof(long),
                       Constants::REQUEST_TYPE, IPC_NOWAIT) >= 0, "request was not sent");
        require(pending.responseType > Constants::RESPONSE_TYPE_BASE,
                "request did not include a response type");
        std::cout << "[PASS] bounded response wait on the shared queue\n";

        RequestMessage filler{};
        filler.mtype = Constants::REQUEST_TYPE;
        while (msgsnd(requests.id(), &filler, sizeof(filler) - sizeof(long), IPC_NOWAIT) == 0) {}
        expectTimeout([&] {
            ipc::exchangeCommand(requests.id(), 1, "STATUS 1", std::chrono::milliseconds(30));
        }, "request was not sent");
        std::cout << "[PASS] bounded request wait when queue is full\n";

        bool rejected = false;
        try { ipc::exchangeCommand(requests.id(), 1, std::string("STATUS 1\0QUIT", 13)); }
        catch (const std::invalid_argument&) { rejected = true; }
        require(rejected, "embedded NUL must be rejected before transport");
        std::cout << "[PASS] embedded NUL rejection\n";

        QueueGuard sharedQueue;
        auto first = std::async(std::launch::async, [&] {
            return ipc::exchangeCommand(sharedQueue.id(), 42, "STATUS 1");
        });
        auto second = std::async(std::launch::async, [&] {
            return ipc::exchangeCommand(sharedQueue.id(), 42, "STATUS 2");
        });
        for (int i = 0; i < 2; ++i) {
            RequestMessage request{};
            require(msgrcv(sharedQueue.id(), &request, sizeof(request) - sizeof(long),
                           Constants::REQUEST_TYPE, 0) >= 0, "request was not received");
            ResponseMessage response{};
            response.mtype = request.responseType;
            response.clientId = request.clientId;
            std::strncpy(response.response, request.command, sizeof(response.response) - 1);
            require(msgsnd(sharedQueue.id(), &response, sizeof(response) - sizeof(long), 0) == 0,
                    "response was not sent");
        }
        require(first.get() == "STATUS 1", "first concurrent response was misrouted");
        require(second.get() == "STATUS 2", "second concurrent response was misrouted");
        std::cout << "[PASS] shared queue routes concurrent commands for the same client ID\n";
    } catch (const std::exception& error) {
        std::cerr << "[FAIL] " << error.what() << "\n";
        return 1;
    }
    return 0;
}
