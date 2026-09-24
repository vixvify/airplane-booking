CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -pthread
CPPFLAGS =
LDLIBS = -pthread

COMMON_SOURCES = src/utils/cli_parser.cpp
IPC_SOURCES = src/ipc/message_queue.cpp
RESERVATION_SOURCES = src/reservation/reservation.cpp src/utils/logger.cpp src/utils/delay.cpp
SERVER_SOURCES = src/server/server.cpp src/server/worker.cpp src/ipc/server_lock.cpp $(IPC_SOURCES) $(RESERVATION_SOURCES) $(COMMON_SOURCES)
CLIENT_SOURCES = src/client/client.cpp $(IPC_SOURCES) $(COMMON_SOURCES)
LOAD_TEST_SOURCES = src/load_test/load_test.cpp $(IPC_SOURCES) $(COMMON_SOURCES)
UNIT_TEST_SOURCES = tests/unit_tests.cpp $(RESERVATION_SOURCES) $(COMMON_SOURCES)
IPC_TEST_SOURCES = tests/ipc_tests.cpp $(IPC_SOURCES)
SOURCES = $(sort $(SERVER_SOURCES) $(CLIENT_SOURCES) $(LOAD_TEST_SOURCES) $(UNIT_TEST_SOURCES) $(IPC_TEST_SOURCES))
OBJECTS = $(SOURCES:%.cpp=build/%.o)
UNIT_TEST_BINARY = tests/bin/unit_tests
IPC_TEST_BINARY = tests/bin/ipc_tests

.PHONY: all clean test test-unit test-integration test-regression test-container
all: server client load_test

server: $(SERVER_SOURCES:%.cpp=build/%.o)
	$(CXX) $(CXXFLAGS) $^ $(LDLIBS) -o $@

client: $(CLIENT_SOURCES:%.cpp=build/%.o)
	$(CXX) $(CXXFLAGS) $^ $(LDLIBS) -o $@

load_test: $(LOAD_TEST_SOURCES:%.cpp=build/%.o)
	$(CXX) $(CXXFLAGS) $^ $(LDLIBS) -o $@

$(UNIT_TEST_BINARY): $(UNIT_TEST_SOURCES:%.cpp=build/%.o)
	mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $^ $(LDLIBS) -o $@

$(IPC_TEST_BINARY): $(IPC_TEST_SOURCES:%.cpp=build/%.o)
	mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $^ $(LDLIBS) -o $@

build/%.o: %.cpp
	mkdir -p $(@D)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -c $< -o $@

-include $(OBJECTS:.o=.d)

test-unit: $(UNIT_TEST_BINARY) $(IPC_TEST_BINARY)
	./$(UNIT_TEST_BINARY)
	./$(IPC_TEST_BINARY)

test-integration: all
	bash tests/integration_tests.sh

# These suites share one IPC namespace; keep them sequential even with make -j.
test: test-unit
	$(MAKE) test-integration
	$(MAKE) test-regression

test-regression: all
	bash tests/regression_tests.sh
	bash tests/script_tests.sh
	bash tests/build_tests.sh

test-container:
	bash tests/container_smoke_tests.sh

clean:
	rm -f server client load_test $(UNIT_TEST_BINARY) $(IPC_TEST_BINARY)
	rm -rf build
