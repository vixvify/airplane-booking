CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -pthread

SERVER_SOURCES = \
	src/server/server.cpp \
	src/server/worker.cpp \
	src/reservation/reservation.cpp \
	src/utils/logger.cpp \
	src/utils/delay.cpp

CLIENT_SOURCES = \
	src/client/client.cpp

LOAD_TEST_SOURCES = \
	src/load_test/load_test.cpp

all: server client load_test

server:
	$(CXX) $(CXXFLAGS) $(SERVER_SOURCES) -o server

client:
	$(CXX) $(CXXFLAGS) $(CLIENT_SOURCES) -o client

load_test:
	$(CXX) $(CXXFLAGS) $(LOAD_TEST_SOURCES) -o load_test

clean:
	rm -f server client load_test
