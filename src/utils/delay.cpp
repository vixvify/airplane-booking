#include "delay.h"

#include "../constants/constants.h"

#include <chrono>
#include <cstdlib>
#include <random>
#include <string_view>
#include <thread>

using namespace std;

void randomDelay() {
    static const bool enabled = [] {
        const char* mode = std::getenv("AIRPLANE_RACE_DELAY");
        return mode == nullptr || std::string_view(mode) != "off";
    }();
    if (!enabled) {
        return;
    }

    thread_local random_device rd;
    thread_local mt19937 generator(rd());

    uniform_int_distribution<int> distribution(
        Constants::MIN_DELAY_MS,
        Constants::MAX_DELAY_MS
    );

    int delay = distribution(generator);

    this_thread::sleep_for(
        chrono::milliseconds(delay)
    );
}