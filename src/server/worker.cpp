#include "worker.h"

#include "../constants/constants.h"
#include "../models/message.h"
#include "../reservation/reservation.h"
#include "../utils/logger.h"

#include <sys/msg.h>

#include <cerrno>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

using namespace std;

namespace {

bool parseSeatIds(stringstream& ss, vector<int>& seatIds) {
    int seatId;
    while (ss >> seatId) {
        seatIds.push_back(seatId);
    }
    return ss.eof() && !seatIds.empty();
}

bool hasExtraArguments(stringstream& ss) {
    string extra;
    return static_cast<bool>(ss >> extra);
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
    int messageQueueId
) {

    while (true) {

        RequestMessage request{};

        ssize_t received = msgrcv(
            messageQueueId,
            &request,
            sizeof(RequestMessage)
                - sizeof(long),
            Constants::REQUEST_TYPE,
            0
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

        request.command[sizeof(request.command) - 1] = '\0';

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

        response.mtype =
            Constants::RESPONSE_TYPE_BASE
            + request.clientId;

        response.clientId =
            request.clientId;

        strncpy(
            response.response,
            result.c_str(),
            sizeof(response.response) - 1
        );

        response.response[
            sizeof(response.response) - 1
        ] = '\0';

        if (
            msgsnd(
                messageQueueId,
                &response,
                sizeof(ResponseMessage)
                    - sizeof(long),
                0
            ) == -1
        ) {

            perror("msgsnd");
        }
    }
}
