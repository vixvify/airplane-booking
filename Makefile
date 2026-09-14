CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -pthread

SERVER_SOURCES = \
	src/server/server.cpp \
	src/server/worker.cpp \
	src/reservation/reservation.cpp \
	src/utils/logger.cpp \
	src/utils/delay.cpp \
	src/utils/cli_parser.cpp

CLIENT_SOURCES = \
	src/client/client.cpp \
	src/utils/cli_parser.cpp

LOAD_TEST_SOURCES = \
	src/load_test/load_test.cpp \
	src/utils/cli_parser.cpp

UNIT_TEST_BINARY = tests/bin/unit_tests
UNIT_TEST_SOURCES = \
	tests/unit_tests.cpp \
	src/reservation/reservation.cpp \
	src/utils/logger.cpp \
	src/utils/delay.cpp \
	src/utils/cli_parser.cpp

.PHONY: all clean test test-unit test-integration test-k8s

all: server client load_test

server:
	$(CXX) $(CXXFLAGS) $(SERVER_SOURCES) -o server

client:
	$(CXX) $(CXXFLAGS) $(CLIENT_SOURCES) -o client

load_test:
	$(CXX) $(CXXFLAGS) $(LOAD_TEST_SOURCES) -o load_test

$(UNIT_TEST_BINARY): $(UNIT_TEST_SOURCES)
	mkdir -p tests/bin
	$(CXX) $(CXXFLAGS) $(UNIT_TEST_SOURCES) -o $(UNIT_TEST_BINARY)

test-unit: $(UNIT_TEST_BINARY)
	./$(UNIT_TEST_BINARY)

test-integration: all
	bash tests/integration_tests.sh

test: test-unit test-integration

test-k8s:
	bash tests/k8s_smoke_tests.sh

clean:
	rm -f server client load_test $(UNIT_TEST_BINARY)
