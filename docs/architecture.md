# Current Architecture

เอกสารนี้สรุป architecture จากโค้ดและ manifest ที่มีอยู่ใน repository ณ วันที่ 2026-09-10

## Overview

```mermaid
flowchart LR
    subgraph Pod["Kubernetes Pod: airplane-reservation\nhostIPC: true"]
        subgraph ServerContainer["server container\nairplane-reservation:latest"]
            Server["./server [sync|nosync] [worker_count]\ncreates/opens queue"]
            Workers["Worker threads\nDEFAULT_WORKER_COUNT = 3\nworker.cpp"]
            Reservation["Reservation domain\nseats[20]\nLIST / STATUS / RESERVE / CANCEL"]
            Sync["Per-seat mutexes\noptional synchronization"]
            Logger["Logger\nsequence + worker/client id"]
            Delay["Random delay\n50-500 ms"]
        end

        Queue[("System V message queue\nkey: ftok(/tmp, 'A')\nrequest mtype = 1\nresponse mtype = 1000 + clientId")]

        C1["client-1\n./client 1"]
        C2["client-2\n./client 2"]
        C3["client-3\n./client 3"]
        C4["client-4\n./client 4"]
        C5["client-5\n./client 5"]
    end

    Server -->|set mode + spawn workers| Workers
    C1 -->|msgsnd request| Queue
    C2 -->|msgsnd request| Queue
    C3 -->|msgsnd request| Queue
    C4 -->|msgsnd request| Queue
    C5 -->|msgsnd request| Queue
    Queue -->|msgrcv request type 1| Workers
    Workers -->|processCommand| Reservation
    Reservation --> Sync
    Reservation --> Delay
    Workers --> Logger
    Workers -->|msgsnd response| Queue
    Queue -->|msgrcv type 1000 + clientId| C1
    Queue -->|msgrcv type 1000 + clientId| C2
    Queue -->|msgrcv type 1000 + clientId| C3
    Queue -->|msgrcv type 1000 + clientId| C4
    Queue -->|msgrcv type 1000 + clientId| C5

```

## Request flow

```mermaid
sequenceDiagram
    participant Client as Client process
    participant Queue as System V message queue
    participant Worker as Worker thread
    participant Domain as Reservation state

    Client->>Queue: msgsnd(Message{mtype=1, clientId, command})
    Worker->>Queue: msgrcv(..., mtype=1)
    Worker->>Worker: Parse LIST / STATUS / RESERVE / CANCEL / QUIT
    Worker->>Domain: Execute command
    alt synchronization enabled
        Domain->>Domain: Lock affected seat mutex(es)
        Domain->>Domain: Read/update seats[20]
    else nosync mode
        Domain->>Domain: Read/update seats[20] without mutex
    end
    Worker->>Queue: msgsnd(Message{mtype=1000+clientId, response})
    Client->>Queue: msgrcv(..., mtype=1000+clientId)
```

## Message contract

```text
struct Message {
    long mtype;       // System V routing type
    int  clientId;    // response destination and reservation owner
    char command[128];
    char response[2048];
};
```

Requests use `mtype = 1`. A worker responds with `mtype = 1000 + clientId`, allowing each client to read only its own response from the shared queue.

## Components and responsibilities

| Component | Responsibility | Source |
| --- | --- | --- |
| `server` | Creates/opens the queue, configures sync mode, and spawns the worker pool | `src/server/server.cpp`, `k8s/pod.yaml` |
| Worker pool | Consumes request messages, dispatches commands, sends responses | `src/server/worker.cpp` |
| Reservation domain | In-memory seat state, validation, reserve/cancel/status/list operations | `src/reservation/reservation.cpp` |
| Synchronization | One `std::mutex` per seat when enabled | `src/reservation/reservation.cpp` |
| Message contract | Fixed-size request/response payload and message types | `src/models/message.h`, `src/constants/constants.h` |
| Logger | Serialized console logs with sequence number | `src/utils/logger.cpp` |
| Delay | Simulates 50–500 ms operation delay | `src/utils/delay.cpp` |
| CLI parser | Validates positive integer arguments shared by server and client | `src/utils/cli_parser.cpp` |
| Clients | Command-line clients that send commands and wait for per-client responses; five Kubernetes containers are provisioned | `src/client/client.cpp`, `k8s/pod.yaml` |
| Load test | Concurrently sends `STATUS` requests and measures throughput/latency | `src/load_test/load_test.cpp` |

## Current-state notes

- Seat state is in the server process memory (`seats[20]`); there is no database or persistent storage.
- All workers in the server process share the same seat array and per-seat mutexes.
- Clients communicate through the same System V queue. Responses are routed by `1000 + clientId`.
- The Kubernetes manifest creates one Pod with one server container and five client containers, and sets `hostIPC: true`; client containers wait for a manual `kubectl exec` command.
- The server supports `sync` or `nosync` plus a configurable worker count; the default is synchronized mode with 3 workers.
- The manifest starts the server with `nosync 3`, so the default Kubernetes path is the unsynchronized branch for the race-condition demo.
- `client.cpp` and `server.cpp` implement the executable entrypoints, including queue creation/access and request/response handling.
- `Dockerfile` copies `Makefile`, `src/`, and `scripts/` into the image before running `make`.
- `Makefile` builds `server`, `client`, and `load_test`.
- `load_test` sends concurrent `STATUS` requests and reports success rate, throughput, and average latency.

## Key constants

- 20 seats
- 3 default worker threads
- Request message type `1`
- Response message type `1000 + clientId`
- Queue key source `/tmp` with project id `'A'`
- Simulated delay between 50 and 500 ms
