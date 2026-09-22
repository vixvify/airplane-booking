#include "worker.h"

#include "../constants/constants.h"
#include "../models/message.h"
#include "../reservation/reservation.h"
#include "../utils/logger.h"
#include "../utils/cli_parser.h"

#include <sys/msg.h>

#include <cerrno>
#include <chrono>
#include <climits>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

string processCommand(
    int workerId,
    int clientId,
    const string& command
) {
    stringstream ss(command);
    string action;
    ss >> action;

    if (action == "LIST") {
        if (hasExtraArguments(ss)) {
            return "Usage: LIST";
        }
        return listSeats();
    }

    if (action == "STATUS") {
        int seatId;
        if (!(ss >> seatId) || hasExtraArguments(ss)) {
            return "Usage: STATUS <seat_id>";
        }
        return getSeatStatus(seatId);
    }

    if (action == "RESERVE") {
        vector<int> seatIds;
        if (!parseSeatIds(ss, seatIds)) {
            return "Usage: RESERVE <seat_id> [seat_id...]";
        }
        return reserveSeats(workerId, clientId, seatIds);
    }

    if (action == "CANCEL") {
        vector<int> seatIds;
        if (!parseSeatIds(ss, seatIds)) {
            return "Usage: CANCEL <seat_id> [seat_id...]";
        }
        return cancelSeats(workerId, clientId, seatIds);
    }

    if (action == "QUIT") {
        if (hasExtraArguments(ss)) {
            return "Usage: QUIT";
        }
        return "GOODBYE";
    }

    return "ERROR: Unknown command";
}

}

void worker(
    int workerId,
    int requestQueueId,
    int responseQueueId
) {
    while (true) {
        RequestMessage request{};

        ssize_t received = msgrcv(
            requestQueueId,
            &request,
            sizeof(RequestMessage) - sizeof(long),
            Constants::REQUEST_TYPE,
            MSG_NOERROR
        );

        if (received == -1) {
            if (errno == EIDRM || errno == EINVAL) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            perror("msgrcv");
            continue;
        }

        if (received != sizeof(RequestMessage) - sizeof(long)
            || request.clientId <= 0 || request.requestId == 0
            || request.requestId > static_cast<std::uint64_t>(LONG_MAX)
            || std::memchr(request.command, '\0', sizeof(request.command)) == nullptr) {
            continue;
        }

        string command(request.command);

        logMessage(
            workerId,
            request.clientId,
            "received " + command
        );

        string result = processCommand(
            workerId,
            request.clientId,
            command
        );

        ResponseMessage response{};
        response.mtype = static_cast<long>(request.requestId);
        response.clientId = request.clientId;
        response.requestId = request.requestId;

        strncpy(
            response.response,
            result.c_str(),
            sizeof(response.response) - 1
        );
        response.response[sizeof(response.response) - 1] = '\0';

        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        while (
            msgsnd(
                responseQueueId,
                &response,
                sizeof(ResponseMessage) - sizeof(long),
                IPC_NOWAIT
            ) == -1
        ) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN) {
                if (std::chrono::steady_clock::now() >= deadline) {
                    perror("msgsnd response timeout");
                    break;
                }
                std::this_thread::sleep_for(std::chrono::microseconds(500));
                continue;
            }
            if (errno == EIDRM || errno == EINVAL) {
                break;
            }
            perror("msgsnd");
            break;
        }
    }
}
