#include "reservation.h"

#include "../constants/constants.h"
#include "../utils/delay.h"
#include "../utils/logger.h"

#include <algorithm>
#include <mutex>
#include <sstream>
#include <vector>

using namespace std;

int seats[Constants::SEAT_COUNT] = {0};

mutex seatMutexes[Constants::SEAT_COUNT];

bool synchronizationEnabled = true;

void setSynchronization(bool enabled) {

    synchronizationEnabled = enabled;
}

bool isValidSeat(int seatId) {

    return seatId >= 1
        && seatId <= Constants::SEAT_COUNT;
}

string listSeats() {

    vector<unique_lock<mutex>> locks;

    if (synchronizationEnabled) {

        for (
            int i = 0;
            i < Constants::SEAT_COUNT;
            i++
        ) {

            locks.emplace_back(
                seatMutexes[i]
            );
        }
    }

    stringstream result;

    result
        << "\n===== Airplane Seat Map =====\n";

    for (
        int i = 0;
        i < Constants::SEAT_COUNT;
        i++
    ) {

        int seatNumber = i + 1;

        result
            << "Seat "
            << seatNumber
            << " : ";

        if (
            seats[i]
            == Constants::AVAILABLE
        ) {

            result << "AVAILABLE";

        } else {

            result
                << "RESERVED by Client-"
                << seats[i];
        }

        result << "\n";
    }

    result
        << "=============================\n";

    return result.str();
}

string getSeatStatus(int seatId) {

    if (!isValidSeat(seatId)) {

        return
            "ERROR: Invalid seat number";
    }

    int index = seatId - 1;

    if (synchronizationEnabled) {

        lock_guard<mutex> lock(
            seatMutexes[index]
        );

        if (
            seats[index]
            == Constants::AVAILABLE
        ) {

            return
                "Seat "
                + to_string(seatId)
                + " is AVAILABLE";
        }

        return
            "Seat "
            + to_string(seatId)
            + " is RESERVED by Client-"
            + to_string(seats[index]);
    }

    if (
        seats[index]
        == Constants::AVAILABLE
    ) {

        return
            "Seat "
            + to_string(seatId)
            + " is AVAILABLE";
    }

    return
        "Seat "
        + to_string(seatId)
        + " is RESERVED by Client-"
        + to_string(seats[index]);
}

string reserveSeats(
    int workerId,
    int clientId,
    const vector<int>& requestedSeats
) {

    if (requestedSeats.empty()) {

        return
            "ERROR: No seats specified";
    }

    vector<int> seatIds =
        requestedSeats;

    sort(
        seatIds.begin(),
        seatIds.end()
    );

    seatIds.erase(
        unique(
            seatIds.begin(),
            seatIds.end()
        ),
        seatIds.end()
    );

    for (int seatId : seatIds) {

        if (!isValidSeat(seatId)) {

            return
                "ERROR: Invalid seat "
                + to_string(seatId);
        }
    }

    if (!synchronizationEnabled) {
        for (int seatId : seatIds) {
            int index = seatId - 1;

            logMessage(
                workerId,
                clientId,
                "checking Seat "
                + to_string(seatId)
            );

            if (
                seats[index]
                != Constants::AVAILABLE
            ) {
                logMessage(
                    workerId,
                    clientId,
                    "RESERVE transaction cancelled: Seat "
                    + to_string(seatId)
                    + " is already reserved"
                );

                return
                    "FAILED: Transaction cancelled because Seat "
                    + to_string(seatId)
                    + " is already reserved";
            }

            logMessage(
                workerId,
                clientId,
                "Seat "
                + to_string(seatId)
                + " is AVAILABLE"
            );
        }

        randomDelay();

        stringstream result;

        for (int seatId : seatIds) {
            int index = seatId - 1;

            seats[index] = clientId;

            logMessage(
                workerId,
                clientId,
                "Seat "
                + to_string(seatId)
                + " reserved"
            );

            result
                << "SUCCESS: Seat "
                << seatId
                << " reserved\n";
        }

        return result.str();
    }

    vector<unique_lock<mutex>> locks;

    for (int seatId : seatIds) {

        int index = seatId - 1;

        logMessage(
            workerId,
            clientId,
            "waiting for Seat "
            + to_string(seatId)
        );

        locks.emplace_back(
            seatMutexes[index]
        );

        logMessage(
            workerId,
            clientId,
            "locked Seat "
            + to_string(seatId)
        );
    }

    logMessage(
        workerId,
        clientId,
        "entering critical section for RESERVE"
    );

    for (int seatId : seatIds) {

        int index = seatId - 1;

        if (
            seats[index]
            != Constants::AVAILABLE
        ) {

            logMessage(
                workerId,
                clientId,
                "leaving critical section: RESERVE transaction cancelled"
            );

            return
                "FAILED: Transaction cancelled because Seat "
                + to_string(seatId)
                + " is already reserved";
        }
    }


    stringstream result;

    for (int seatId : seatIds) {

        int index = seatId - 1;

        logMessage(
            workerId,
            clientId,
            "Seat "
            + to_string(seatId)
            + " is AVAILABLE"
        );

        randomDelay();

        seats[index] = clientId;

        logMessage(
            workerId,
            clientId,
            "Seat "
            + to_string(seatId)
            + " reserved"
        );

        result
            << "SUCCESS: Seat "
            << seatId
            << " reserved\n";
    }

    logMessage(
        workerId,
        clientId,
        "leaving critical section for RESERVE"
    );

    return result.str();
}

string cancelSeats(
    int workerId,
    int clientId,
    const vector<int>& requestedSeats
) {

    if (requestedSeats.empty()) {
        return "ERROR: No seats specified";
    }

    vector<int> seatIds = requestedSeats;

    sort(
        seatIds.begin(),
        seatIds.end()
    );

    seatIds.erase(
        unique(
            seatIds.begin(),
            seatIds.end()
        ),
        seatIds.end()
    );

    for (int seatId : seatIds) {

        if (!isValidSeat(seatId)) {

            return
                "ERROR: Invalid seat "
                + to_string(seatId);
        }
    }

    if (!synchronizationEnabled) {
        for (int seatId : seatIds) {
            int index = seatId - 1;

            logMessage(
                workerId,
                clientId,
                "checking Seat "
                + to_string(seatId)
            );

            if (
                seats[index]
                == Constants::AVAILABLE
            ) {
                logMessage(
                    workerId,
                    clientId,
                    "CANCEL transaction cancelled: Seat "
                    + to_string(seatId)
                    + " is not reserved"
                );

                return
                    "FAILED: Transaction cancelled because Seat "
                    + to_string(seatId)
                    + " is not reserved";
            }

            if (
                seats[index]
                != clientId
            ) {

                logMessage(
                    workerId,
                    clientId,
                    "CANCEL transaction cancelled: Seat "
                    + to_string(seatId)
                    + " belongs to another client"
                );

                return
                    "FAILED: Transaction cancelled because Seat "
                    + to_string(seatId)
                    + " belongs to another client";
            }
        }

        randomDelay();

        stringstream result;

        for (int seatId : seatIds) {
            int index = seatId - 1;

            seats[index] =
                Constants::AVAILABLE;

            logMessage(
                workerId,
                clientId,
                "Seat "
                + to_string(seatId)
                + " cancelled"
            );

            result
                << "SUCCESS: Seat "
                << seatId
                << " cancelled\n";
        }

        return result.str();
    }

    vector<unique_lock<mutex>> locks;

    for (int seatId : seatIds) {

        int index = seatId - 1;

        logMessage(
            workerId,
            clientId,
            "waiting for Seat "
            + to_string(seatId)
        );

        locks.emplace_back(
            seatMutexes[index]
        );

        logMessage(
            workerId,
            clientId,
            "locked Seat "
            + to_string(seatId)
        );
    }

    logMessage(
        workerId,
        clientId,
        "entering critical section for CANCEL"
    );

    for (int seatId : seatIds) {

        int index = seatId - 1;

        if (
            seats[index]
            != clientId
        ) {

            logMessage(
                workerId,
                clientId,
                "leaving critical section: CANCEL transaction cancelled"
            );

            return
                "FAILED: Transaction cancelled because Seat "
                + to_string(seatId)
                + " cannot be cancelled";
        }
    }

    stringstream result;

    for (int seatId : seatIds) {

        int index = seatId - 1;

        randomDelay();

        seats[index] =
            Constants::AVAILABLE;

        logMessage(
            workerId,
            clientId,
            "Seat "
            + to_string(seatId)
            + " cancelled"
        );

        result
            << "SUCCESS: Seat "
            << seatId
            << " cancelled\n";
    }

    logMessage(
        workerId,
        clientId,
        "leaving critical section for CANCEL"
    );

    return result.str();
}
