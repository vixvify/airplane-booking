FROM gcc:14-bookworm

WORKDIR /app

COPY Makefile ./
COPY src ./src
COPY scripts ./scripts

RUN make

CMD ["sleep", "infinity"]
