#include "worker.h"

#include "../constants/constants.h"
#include "../models/message.h"
#include "../reservation/reservation.h"
#include "../utils/logger.h"
#include "../utils/cli_parser.h"

#include <sys/msg.h>

#include <chrono>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <deque>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

std::int64_t currentEpochMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

bool responseExpired(const ResponseMessage& response) {
    return response.responseDeadlineEpochMs <= currentEpochMilliseconds();
}

bool requeueLiveResponse(int queueId, const ResponseMessage& response, size_t size) {
    while (!responseExpired(response)) {
        if (msgsnd(queueId, &response, size, IPC_NOWAIT) == 0) {
            return true;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }
        if (errno != EIDRM && errno != EINVAL) {
            perror("msgsnd");
        }
        return false;
    }
    return true;
}

bool discardExpiredResponse(int queueId) {
    ResponseMessage message{};
    const ssize_t received = msgrcv(
        queueId,
        &message,
        sizeof(ResponseMessage) - sizeof(long),
        -Constants::MAX_RESPONSE_TYPE,
        IPC_NOWAIT
    );
    if (received == -1) {
        if (errno == ENOMSG) {
            return true;
        }
        if (errno != EIDRM && errno != EINVAL) {
            perror("msgrcv");
        }
        return false;
    }

    if (responseExpired(message)) {
        return true;
    }
    return requeueLiveResponse(queueId, message, received);
}

bool flushPendingResponses(
    int queueId,
    deque<ResponseMessage>& pendingResponses
) {
    while (!pendingResponses.empty()) {
        ResponseMessage& response = pendingResponses.front();
        if (responseExpired(response)) {
            pendingResponses.pop_front();
            continue;
        }
        if (msgsnd(queueId, &response, sizeof(ResponseMessage) - sizeof(long),
                   IPC_NOWAIT) == 0) {
            pendingResponses.pop_front();
            continue;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN) {
            return true;
        }
        if (errno != EIDRM && errno != EINVAL) {
            perror("msgsnd");
        }
        return false;
    }
    return true;
}

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

        if (
            !(ss >> seatId)
            || hasExtraArguments(ss)
        ) {

            return
                "Usage: STATUS <seat_id>";
        }

        return getSeatStatus(
            seatId
        );
    }

    if (action == "RESERVE") {

        vector<int> seatIds;
        if (!parseSeatIds(ss, seatIds)) {
            return "Usage: RESERVE <seat_id> [seat_id...]";
        }

        return reserveSeats(
            workerId,
            clientId,
            seatIds
        );
    }

    if (action == "CANCEL") {

        vector<int> seatIds;
        if (!parseSeatIds(ss, seatIds)) {
            return "Usage: CANCEL <seat_id> [seat_id...]";
        }

        return cancelSeats(
            workerId,
            clientId,
            seatIds
        );
    }

    if (action == "QUIT") {

        if (hasExtraArguments(ss)) {
            return "Usage: QUIT";
        }

        return "GOODBYE";
    }

    return
        "ERROR: Unknown command";
}
}
void worker(
    int workerId,
    int queueId
) {

    deque<ResponseMessage> pendingResponses;

    while (true) {

        if (!flushPendingResponses(queueId, pendingResponses)) {
            break;
        }
        if (pendingResponses.size() >= Constants::MAX_PENDING_RESPONSES_PER_WORKER) {
            if (!discardExpiredResponse(queueId)) {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }

        RequestMessage request{};

        ssize_t received = msgrcv(
            queueId,
            &request,
            sizeof(RequestMessage)
                - sizeof(long),
            Constants::REQUEST_TYPE,
            MSG_NOERROR | IPC_NOWAIT
        );

        if (received == -1) {
            if (errno == EIDRM || errno == EINVAL) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            if (errno == ENOMSG) {
                if (!discardExpiredResponse(queueId)) {
                    break;
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                continue;
            }
            perror("msgrcv");
            continue;
        }

        if (received != sizeof(RequestMessage) - sizeof(long)
            || request.clientId <= 0 || request.responseType <= Constants::RESPONSE_TYPE_BASE
            || request.responseDeadlineEpochMs <= 0
            || std::memchr(request.command, '\0', sizeof(request.command)) == nullptr) {
            continue;
        }

        string command(
            request.command
        );

        logMessage(
            workerId,
            request.clientId,
            "received "
            + command
        );

        string result =
            processCommand(
                workerId,
                request.clientId,
                command
            );

        ResponseMessage response{};

        response.mtype = request.responseType;

        response.clientId =
            request.clientId;

        response.responseDeadlineEpochMs = request.responseDeadlineEpochMs;

        strncpy(
            response.response,
            result.c_str(),
            sizeof(response.response) - 1
        );

        response.response[
            sizeof(response.response) - 1
        ] = '\0';

        pendingResponses.push_back(response);
    }
}
