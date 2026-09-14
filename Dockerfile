FROM gcc:14-bookworm

WORKDIR /app

COPY Makefile ./
COPY src ./src
COPY scripts ./scripts
COPY tests ./tests

RUN make
RUN mkdir -p /ipc

CMD ["sleep", "infinity"]
