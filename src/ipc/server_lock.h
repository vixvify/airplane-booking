#pragma once

namespace ipc {

class ServerLock {
public:
    ServerLock();
    ~ServerLock();
    ServerLock(const ServerLock&) = delete;
    ServerLock& operator=(const ServerLock&) = delete;

private:
    int descriptor_ = -1;
};

}
