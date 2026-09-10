#include "../constants/constants.h"
#include "../models/message.h"

#include <sys/ipc.h>
#include <sys/msg.h>

#include <cstring>
#include <iostream>
#include <sstream>
#include <string>

using namespace std;

namespace {

void printUsage(const char* program) {
    cerr << "Usage: " << program << " <client_id>\n";
}

bool parseClientId(const string& value, int& clientId) {
    try {
        size_t position = 0;
        int parsed = stoi(value, &position);

        if (
            position != value.size()
            || parsed <= 0
        ) {
            return false;
        }

        clientId = parsed;
        return true;
    }
    catch (...) {
        return false;
    }
}

bool isQuitCommand(const string& command) {
    string action;
    stringstream stream(command);
    stream >> action;
    return action == "QUIT";
}

}

int main(int argc, char* argv[]) {
    int clientId = 0;

    if (
        argc != 2
        || !parseClientId(argv[1], clientId)
    ) {
        printUsage(argv[0]);
        return 1;
    }

    key_t key = ftok(
        Constants::QUEUE_PATH,
        Constants::QUEUE_PROJECT_ID
    );

    if (key == -1) {
        perror("ftok");
        return 1;
    }

    int messageQueueId = msgget(key, 0666);

    if (messageQueueId == -1) {
        perror("msgget");
        cerr << "Make sure the server is running first.\n";
        return 1;
    }

    cout
        << "Client-" << clientId
        << " connected. Enter commands (LIST, STATUS, RESERVE, CANCEL, QUIT).\n";

    string command;

    while (getline(cin, command)) {
        if (command.empty()) {
            continue;
        }

        Message request{};
        request.mtype = Constants::REQUEST_TYPE;
        request.clientId = clientId;

        strncpy(
            request.command,
            command.c_str(),
            sizeof(request.command) - 1
        );
        request.command[sizeof(request.command) - 1] = '\0';

        if (
            msgsnd(
                messageQueueId,
                &request,
                sizeof(Message) - sizeof(long),
                0
            ) == -1
        ) {
            perror("msgsnd");
            return 1;
        }

        Message response{};
        long responseType =
            Constants::RESPONSE_TYPE_BASE + clientId;

        if (
            msgrcv(
                messageQueueId,
                &response,
                sizeof(Message) - sizeof(long),
                responseType,
                0
            ) == -1
        ) {
            perror("msgrcv");
            return 1;
        }

        cout << response.response << "\n";

        if (isQuitCommand(command)) {
            break;
        }
    }

    return 0;
}
