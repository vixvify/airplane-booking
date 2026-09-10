#include "cli_parser.h"

using namespace std;

bool parsePositiveInt(
    const string& value,
    int& result
) {
    try {
        size_t position = 0;
        int parsed = stoi(value, &position);

        if (
            position != value.size()
            || parsed <= 0
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
