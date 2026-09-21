#include "cli_parser.h"
#include <utility>

using namespace std;

bool parseInt(
    const string& value,
    int& result
) {
    try {
        size_t position = 0;
        int parsed = stoi(value, &position);

        if (
            position != value.size()
        ) {
            return false;
        }

        result = parsed;
        return true;
    }
    catch (...) {
        return false;
    }
}

bool parsePositiveInt(const string& value, int& result) {
    int parsed = 0;
    if (!parseInt(value, parsed) || parsed <= 0) {
        return false;
    }
    result = parsed;
    return true;
}

bool parseSeatIds(stringstream& stream, vector<int>& seatIds) {
    vector<int> parsed;
    string token;
    while (stream >> token) {
        int seatId = 0;
        if (!parseInt(token, seatId)) {
            return false;
        }
        parsed.push_back(seatId);
    }
    if (parsed.empty()) {
        return false;
    }
    seatIds = std::move(parsed);
    return true;
}

bool hasExtraArguments(stringstream& stream) {
    string extra;
    return static_cast<bool>(stream >> extra);
}
