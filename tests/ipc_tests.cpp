#include "../src/ipc/message_queue.h"
#include "../src/models/message.h"
#include "../src/constants/constants.h"

#include <sys/msg.h>
#include <chrono>
#include <cstring>
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
}

int main() {
    try {
        auto requests = ipc::MessageQueue::createReply();
        // No worker: a successfully sent request must time out, not hang forever.
        expectTimeout([&] {
            ipc::exchangeCommand(requests.id(), 1, "STATUS 1", std::chrono::milliseconds(30));
        }, "operation outcome unknown");
        RequestMessage pending{};
        require(msgrcv(requests.id(), &pending, sizeof(pending) - sizeof(long),
                       Constants::REQUEST_TYPE, IPC_NOWAIT) >= 0, "request was not sent");
        msqid_ds status{};
        require(msgctl(pending.replyQueueId, IPC_STAT, &status) == -1,
                "timed-out request leaked its reply queue");
        std::cout << "[PASS] bounded response wait and private-queue cleanup\n";

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
    } catch (const std::exception& error) {
        std::cerr << "[FAIL] " << error.what() << "\n";
        return 1;
    }
    return 0;
}
