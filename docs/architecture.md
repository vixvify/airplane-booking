# System Architecture

เอกสารนี้อธิบายระบบจองที่นั่งตาม implementation ปัจจุบัน รวมการสื่อสารผ่าน System V message queues, การจัดการ transaction, worker synchronization และการรัน services ด้วย Docker Compose

## ภาพรวม

```mermaid
flowchart LR
    subgraph host["Host"]
        tools["Demo / test / load-test scripts"]
        composeExec["Docker Compose exec"]
        tools --> composeExec
    end

    subgraph project["Docker Compose project"]
        subgraph clients["Client containers"]
            clientServices["client-1 ถึง client-5"]
            clientProcess["client หรือ load_test process"]
            clientServices -->|"เริ่ม process ใน container"| clientProcess
        end

        subgraph ipc["Shared System V IPC namespace"]
            requestQueue[("Request queue (mtype: 1)")]
            responseQueue[("Response queue (mtype: requestId)")]
        end

        subgraph serverContainer["Server container"]
            server["Server process"]
            workers["Worker threads (1 หรือ 3 ตาม experiment)"]
            seatState["สถานะที่นั่ง 20 ที่ (server memory)"]
            seatLocks["Per-seat mutexes (sync only)"]
            server -->|"สร้าง queues และ workers"| workers
            workers -->|"อ่าน / อัปเดต"| seatState
            workers -->|"ล็อกที่นั่งในโหมด sync"| seatLocks
        end

        ipcVolume["Named volume /ipc (ftok key source)"]
    end

    composeExec -->|"สั่งรัน client / load test"| clientServices
    clientProcess -->|"ส่ง request"| requestQueue
    requestQueue -->|"worker รับ request"| workers
    workers -->|"ส่งผลพร้อม requestId"| responseQueue
    responseQueue -->|"รับ response ของ request ตัวเอง"| clientProcess
    clientServices -.->|"mount ร่วมกัน"| ipcVolume
    server -.->|"mount ร่วมกัน"| ipcVolume

    classDef hostNode fill:#EAF2FF,stroke:#3973B9,color:#17365D,stroke-width:1.5px
    classDef clientNode fill:#E8F5E9,stroke:#388E3C,color:#1B4332,stroke-width:1.5px
    classDef ipcNode fill:#FFF3E0,stroke:#EF8F00,color:#663C00,stroke-width:1.5px
    classDef serverNode fill:#F3E8FF,stroke:#7E57C2,color:#45277A,stroke-width:1.5px
    classDef stateNode fill:#E0F2F1,stroke:#00897B,color:#004D40,stroke-width:1.5px

    class tools,composeExec hostNode
    class clientServices,clientProcess clientNode
    class requestQueue,responseQueue,ipcVolume ipcNode
    class server,workers serverNode
    class seatState,seatLocks stateNode
```

Client processes ส่ง request เข้า queue กลาง; worker ตัวหนึ่งรับไปประมวลผลและส่ง response กลับผ่าน queue อีกชุด โดยใช้ `requestId` จับคู่คำตอบกับ request เดิม Worker ทั้งหมดทำงานกับสถานะที่นั่งชุดเดียวกันภายใน server process

> `/ipc` เป็น volume สำหรับให้ `ftok` สร้าง queue keys ไม่ใช่ที่เก็บข้อมูล queue หรือสถานะการจอง ส่วน System V queues อยู่ใน IPC namespace ที่ client containers ใช้ร่วมกับ server

## Compose topology

ไฟล์ `compose/compose.yaml` กำหนด service `server` และ client services 5 ตัว แต่ละ client รอคำสั่งจาก `docker compose exec`:

| Compose service | Process |
| --- | --- |
| `server` | `./server nosync 3` ตามค่าเริ่มต้น |
| `client-1` ถึง `client-5` | `sleep infinity` เพื่อรอรับ client/load-test process |

Server ใช้ IPC namespace แบบ `shareable`; clients ใช้ namespace เดียวกับ server ผ่าน `ipc: service:server`. ทุก service mount named volume เดียวกันที่ `/ipc`, ซึ่งเป็น path ที่ `ftok` ใช้สร้าง key ของ queues และ semaphore

การแบ่ง IPC namespace ของ Compose project ทำให้ System V queues ไม่ปะปนกับ host หรือ Compose project อื่น

### Experiment configurations

Compose overlays เปลี่ยนเฉพาะ server command:

| Experiment | Configuration | Server command |
| --- | --- | --- |
| Sequential baseline | `compose/compose.sequential.yaml` | `./server sync 1` |
| Concurrent without synchronization | `compose/compose.yaml` | `./server nosync 3` |
| Concurrent with synchronization | `compose/compose.sync.yaml` | `./server sync 3` |

`scripts/compose.sh` เลือก overlay จาก `COMPOSE_EXPERIMENT`. เมื่อต้องการเปลี่ยนรูปแบบ ให้หยุด services แล้วเริ่มใหม่เพื่อให้ได้ server และ IPC state ชุดใหม่

## Message flow

1. Client สร้าง `requestId` และส่ง message ไปยัง shared request queue
2. Worker ตัวใดตัวหนึ่งรับ request แล้วประมวลผล operation
3. Server ส่ง response เข้า shared response queue โดยใช้ `requestId` เป็น message type สำหรับ routing
4. Client อ่าน response ที่ตรงกับ request ของตัวเอง

Request และ response แยกคนละ queue; response ไม่ย้อนกลับเข้า request queue และไม่ต้องมี private queue ต่อ client

## Message data

Message มีข้อมูลสำหรับแยกชนิดกับ route งาน:

| Field | Purpose |
| --- | --- |
| `mtype` | System V queue message type; response ใช้ request ID เพื่อให้ client รับ response ของตน |
| `clientId` | ระบุ client และใช้ตรวจ ownership ของ reservation |
| `requestId` | ระบุ request ที่ไม่ซ้ำกันและจับคู่ response |
| `command` | ข้อความคำสั่ง เช่น `RESERVE 3 4` หรือ `STATUS 3` |
| `response` | ข้อความผลการทำงานที่ส่งกลับ client |

รายละเอียดโครงสร้างจริงอยู่ใน `src/models/message.h`; การ parse คำสั่งเป็น operation และ seat IDs เกิดหลังจาก worker รับ request

## Reservation transaction

การจองหรือยกเลิกหลายที่นั่งทำงานแบบ all-or-nothing:

1. ตรวจ syntax และ validate ที่นั่งทั้งหมดก่อนเปลี่ยน state
2. ในโหมด sync ล็อกที่นั่งตามลำดับที่แน่นอนเพื่อลด deadlock
3. ตรวจ availability หรือ ownership ของทุกที่นั่ง
4. หากมีรายการใดไม่ผ่าน ให้ยกเลิก transaction และไม่เปลี่ยนรายการใด
5. หากผ่านทั้งหมด จึง commit state ของทุกที่นั่ง
6. ปลด locks และส่งผลกลับ client

โหมด nosync ตั้งใจข้าม mutex เพื่อให้เห็น race condition ในการทดลอง

## Load test และหลักฐาน

`load_test` ใช้ thread pool ตาม concurrency ที่กำหนด ส่ง `STATUS`, `RESERVE` หรือ `CANCEL` และรายงาน completed requests, transport failures, operation outcomes, throughput และ average latency

PowerShell wrapper `scripts/load-test.ps1` เรียก Compose client service และบันทึก output, server logs และ parameters/exit codes เป็นไฟล์ TXT ใน directory แยกต่อรอบ

Demo scripts เก็บ commands และ output แยกตาม client พร้อม live/final server logs ใน `results/demos/<demo>/<UTC timestamp>/`. Load-test และ test suites ก็แยก directory ตามประเภท ดูรายการไฟล์ทั้งหมดได้ที่ `results/README.md`; CI อัปโหลดผลเหล่านี้เป็น artifact

## Repository map

| Path | Responsibility |
| --- | --- |
| `src/client/` | รับคำสั่งผู้ใช้ ส่ง request และรับ response |
| `src/server/` | สร้าง queues, worker threads และประมวลผล requests |
| `src/ipc/` | System V queue wrappers และป้องกัน server ซ้ำ |
| `src/reservation/` | seat state, validation, transaction และ synchronization |
| `src/load_test/` | concurrent load generator และ throughput/latency summary |
| `src/utils/` | CLI parser, logger และ delay utilities |
| `compose/` | runtime topology และ experiment configurations |
| `scripts/` | Compose wrapper, demos, concurrent test และ result collection |
| `tests/` | unit, IPC, integration, regression, script และ Compose smoke tests |
