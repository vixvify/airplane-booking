#include "../ipc/message_queue.h"
#include "../utils/cli_parser.h"

#include <iostream>
#include <stdexcept>
#include <string>

int main(int argc, char* argv[]) {
    int clientId = 0;
    if (argc != 2 || !parsePositiveInt(argv[1], clientId)) {
        std::cerr << "Usage: " << argv[0] << " <client_id>\n";
        return 1;
    }

    try {
        auto queue = ipc::MessageQueue::openSharedQueue();
        std::cout << std::unitbuf << "Client-" << clientId
                  << " connected. Enter commands (LIST, STATUS, RESERVE, CANCEL, QUIT).\n";

        std::string command;
        while (std::getline(std::cin, command)) {
            if (command.empty()) {
                continue;
            }
            try {
                const auto response = ipc::exchangeCommand(queue.id(), clientId, command);
                std::cout << response << "\n";
                if (response == "GOODBYE") {
                    break;
                }
            } catch (const std::invalid_argument& error) {
                std::cout << "ERROR: " << error.what() << "\n";
            }
        }
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << "\n";
        return 1;
    }
    return 0;
}
