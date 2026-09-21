#include "server_lock.h"

#include "../constants/constants.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <stdexcept>
#include <string>
#include <system_error>

namespace ipc {

ServerLock::ServerLock() {
    const std::string path = std::string(Constants::QUEUE_PATH) + "/server.lock";
    descriptor_ = open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC, 0666);
    if (descriptor_ == -1) {
        throw std::system_error(errno, std::generic_category(), "open server lock");
    }
    if (flock(descriptor_, LOCK_EX | LOCK_NB) == -1) {
        const int error = errno;
        close(descriptor_);
        descriptor_ = -1;
        if (error == EWOULDBLOCK || error == EAGAIN) {
            throw std::runtime_error("Another server is already running for this /ipc directory");
        }
        throw std::system_error(error, std::generic_category(), "lock server");
    }
}

ServerLock::~ServerLock() {
    if (descriptor_ != -1) {
        close(descriptor_);
    }
}

}
