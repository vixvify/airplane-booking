#include "../src/constants/constants.h"
#include "../src/reservation/reservation.h"
#include "../src/utils/cli_parser.h"

#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <condition_variable>
#include <functional>
#include <iostream>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using namespace std;

namespace {

class TestFailure : public runtime_error {
public:
    explicit TestFailure(const string& message)
        : runtime_error(message) {}
};

class SilenceStdout {
public:
    SilenceStdout()
        : previous(cout.rdbuf(buffer.rdbuf())) {}

    ~SilenceStdout() {
        cout.rdbuf(previous);
    }

private:
    ostringstream buffer;
    streambuf* previous;
};

void expect(bool condition, const string& message) {
    if (!condition) {
        throw TestFailure(message);
    }
}

void expectContains(
    const string& actual,
    const string& expected,
    const string& message
) {
    expect(
        actual.find(expected) != string::npos,
        message + " (missing: " + expected + ")"
    );
}

void expectStartsWith(
    const string& actual,
    const string& expected,
    const string& message
) {
    expect(
        actual.rfind(expected, 0) == 0,
        message + " (actual: " + actual + ")"
    );
}

int countOccurrences(
    const string& value,
    const string& needle
) {
    int count = 0;
    size_t position = 0;

    while ((position = value.find(needle, position)) != string::npos) {
        count++;
        position += needle.size();
    }

    return count;
}

void expectAvailable(int seatId) {
    expectContains(
        getSeatStatus(seatId),
        "AVAILABLE",
        "Seat " + to_string(seatId) + " should be available"
    );
}

void expectOwnedBy(int seatId, int clientId) {
    expectContains(
        getSeatStatus(seatId),
        "RESERVED by Client-" + to_string(clientId),
        "Seat " + to_string(seatId) + " should have the expected owner"
    );
}

void testPositiveIntegerParser() {
    int result = 0;

    expect(parsePositiveInt("1", result) && result == 1, "1 should parse");
    expect(parsePositiveInt("42", result) && result == 42, "42 should parse");
    expect(!parsePositiveInt("0", result), "zero should be rejected");
    expect(!parsePositiveInt("-1", result), "negative values should be rejected");
    expect(!parsePositiveInt("", result), "empty values should be rejected");
    expect(!parsePositiveInt("12x", result), "trailing text should be rejected");
    expect(!parsePositiveInt("999999999999999999999", result), "overflow should be rejected");
}

void testInitialStateAndSeatBounds() {
    setSynchronization(true);

    expectAvailable(1);
    expectAvailable(Constants::SEAT_COUNT);
    expectContains(getSeatStatus(0), "ERROR", "Seat 0 should be invalid");
    expectContains(
        getSeatStatus(Constants::SEAT_COUNT + 1),
        "ERROR",
        "Seat above the configured limit should be invalid"
    );

    string seats = listSeats();
    expect(
        countOccurrences(seats, " : AVAILABLE") == Constants::SEAT_COUNT,
        "The initial list should contain 20 available seats"
    );
}

void testSeatTokenParser() {
    for (const string input : {"1 9999999999999999999999999999", "1 2x", "", "1 -999999999999999999999"}) {
        stringstream stream(input);
        vector<int> seats{20};
        expect(!parseSeatIds(stream, seats), "invalid seat tokens must fail");
        expect(seats == vector<int>{20}, "failed parse must not expose a partial list");
    }
    stringstream valid("3 1 3 -1 0 +2");
    vector<int> seats;
    expect(parseSeatIds(valid, seats), "valid integers should parse before domain validation");
    expect(seats == vector<int>({3, 1, 3, -1, 0, 2}), "parser must preserve values");
}

void testDuplicateSeatsAreNormalized() {
    setSynchronization(true);

    string result = reserveSeats(1, 10, {3, 1, 3, 1});

    expect(
        countOccurrences(result, "SUCCESS:") == 2,
        "Duplicate seats should be processed once"
    );
    expectOwnedBy(1, 10);
    expectOwnedBy(3, 10);
}

void testInvalidReservationDoesNotMutateState() {
    setSynchronization(true);

    expectContains(
        reserveSeats(1, 10, {}),
        "ERROR: No seats specified",
        "Empty reservations should fail"
    );
    expectContains(
        reserveSeats(1, 10, {1, 21}),
        "ERROR: Invalid seat 21",
        "Out-of-range reservations should fail"
    );
    expectAvailable(1);

    expectContains(
        cancelSeats(1, 10, {}),
        "ERROR: No seats specified",
        "Empty cancellations should fail"
    );
    expectContains(
        cancelSeats(1, 10, {1, 21}),
        "ERROR: Invalid seat 21",
        "Out-of-range cancellations should fail"
    );
    expectAvailable(1);
}

void testReserveRollback(bool synchronized) {
    setSynchronization(synchronized);

    expectStartsWith(
        reserveSeats(1, 20, {2}),
        "SUCCESS:",
        "Setup reservation should succeed"
    );

    string result = reserveSeats(2, 10, {1, 2, 3});

    expectStartsWith(
        result,
        "FAILED: Transaction cancelled",
        "A multi-seat reservation should fail as one transaction"
    );
    expectAvailable(1);
    expectOwnedBy(2, 20);
    expectAvailable(3);
}

void testSyncReserveRollback() {
    testReserveRollback(true);
}

void testNosyncReserveRollback() {
    testReserveRollback(false);
}

void testCancelRollback(bool synchronized) {
    setSynchronization(synchronized);

    expectStartsWith(
        reserveSeats(1, 10, {4, 5}),
        "SUCCESS:",
        "Setup reservation should succeed"
    );

    string result = cancelSeats(2, 10, {4, 6});

    expectStartsWith(
        result,
        "FAILED: Transaction cancelled",
        "A multi-seat cancellation should fail as one transaction"
    );
    expectOwnedBy(4, 10);
    expectOwnedBy(5, 10);
    expectAvailable(6);
}

void testSyncCancelRollback() {
    testCancelRollback(true);
}

void testNosyncCancelRollback() {
    testCancelRollback(false);
}

void testWrongOwnerCannotCancel() {
    setSynchronization(true);

    reserveSeats(1, 10, {7});
    string result = cancelSeats(2, 11, {7});

    expectStartsWith(
        result,
        "FAILED: Transaction cancelled",
        "A different client should not be able to cancel the seat"
    );
    expectOwnedBy(7, 10);
}

void testSuccessfulMultiSeatLifecycle() {
    setSynchronization(true);

    string reserveResult = reserveSeats(1, 10, {8, 9, 10});
    expect(
        countOccurrences(reserveResult, "SUCCESS:") == 3,
        "All requested seats should be reserved"
    );

    string cancelResult = cancelSeats(1, 10, {8, 9, 10});
    expect(
        countOccurrences(cancelResult, "SUCCESS:") == 3,
        "All owned seats should be cancelled"
    );

    expectAvailable(8);
    expectAvailable(9);
    expectAvailable(10);
}

vector<string> runConcurrentReserve(bool synchronized) {
    constexpr int clientCount = 5;

    setSynchronization(synchronized);

    vector<string> results(clientCount);
    vector<thread> clients;
    mutex startMutex;
    condition_variable startCondition;
    int ready = 0;
    bool start = false;

    for (int index = 0; index < clientCount; index++) {
        clients.emplace_back([&, index]() {
            {
                unique_lock<mutex> lock(startMutex);
                ready++;
                startCondition.notify_all();
                startCondition.wait(lock, [&]() {
                    return start;
                });
            }

            results[index] = reserveSeats(
                index + 1,
                index + 1,
                {15}
            );
        });
    }

    {
        unique_lock<mutex> lock(startMutex);
        startCondition.wait(lock, [&]() {
            return ready == clientCount;
        });
        start = true;
    }
    startCondition.notify_all();

    for (thread& client : clients) {
        client.join();
    }

    return results;
}

void testSyncConcurrentReserve() {
    vector<string> results = runConcurrentReserve(true);

    int successes = count_if(
        results.begin(),
        results.end(),
        [](const string& result) {
            return result.rfind("SUCCESS:", 0) == 0;
        }
    );

    expect(successes == 1, "Synchronized reservation should have one winner");
}

void testNosyncConcurrentReserveExposesRace() {
    vector<string> results = runConcurrentReserve(false);

    int successes = count_if(
        results.begin(),
        results.end(),
        [](const string& result) {
            return result.rfind("SUCCESS:", 0) == 0;
        }
    );

    expect(
        successes > 1,
        "Unsynchronized reservation should expose multiple reported winners"
    );
}

struct TestCase {
    const char* name;
    function<void()> run;
};

bool runIsolated(const TestCase& test) {
    cout.flush();
    cerr.flush();

    pid_t child = fork();

    if (child == -1) {
        cerr << "[FAIL] " << test.name << ": fork failed\n";
        return false;
    }

    if (child == 0) {
        try {
            SilenceStdout silence;
            test.run();
            _exit(0);
        }
        catch (const exception& error) {
            cerr << "[FAIL] " << test.name << ": " << error.what() << "\n";
            _exit(1);
        }
        catch (...) {
            cerr << "[FAIL] " << test.name << ": unknown exception\n";
            _exit(1);
        }
    }

    int status = 0;
    waitpid(child, &status, 0);

    bool passed = WIFEXITED(status) && WEXITSTATUS(status) == 0;

    if (passed) {
        cout << "[PASS] " << test.name << "\n";
    }

    return passed;
}

}

int main() {
    vector<TestCase> tests = {
        {"positive integer parser", testPositiveIntegerParser},
        {"complete seat-token parsing", testSeatTokenParser},
        {"initial state and seat bounds", testInitialStateAndSeatBounds},
        {"duplicate seat normalization", testDuplicateSeatsAreNormalized},
        {"invalid requests preserve state", testInvalidReservationDoesNotMutateState},
        {"sync reserve rollback", testSyncReserveRollback},
        {"nosync reserve rollback", testNosyncReserveRollback},
        {"sync cancel rollback", testSyncCancelRollback},
        {"nosync cancel rollback", testNosyncCancelRollback},
        {"wrong owner cancellation", testWrongOwnerCannotCancel},
        {"successful multi-seat lifecycle", testSuccessfulMultiSeatLifecycle},
        {"sync concurrent reservation", testSyncConcurrentReserve},
        {"nosync concurrent race", testNosyncConcurrentReserveExposesRace}
    };

    int failures = 0;

    cout << "Running " << tests.size() << " unit/transaction tests\n";

    for (const TestCase& test : tests) {
        if (!runIsolated(test)) {
            failures++;
        }
    }

    cout
        << "Unit tests: "
        << (tests.size() - failures)
        << " passed, "
        << failures
        << " failed\n";

    return failures == 0 ? 0 : 1;
}
