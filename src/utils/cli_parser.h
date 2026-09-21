#ifndef CLI_PARSER_H
#define CLI_PARSER_H

#include <string>
#include <sstream>
#include <vector>

bool parseInt(const std::string& value, int& result);
bool parseSeatIds(std::stringstream& stream, std::vector<int>& seatIds);
bool hasExtraArguments(std::stringstream& stream);

bool parsePositiveInt(
    const std::string& value,
    int& result
);

#endif
