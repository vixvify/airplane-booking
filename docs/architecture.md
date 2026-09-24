# System Architecture

ระบบจองที่นั่งนี้รันบน Linux ภายใน Docker Compose โดยมี client containers 5 ตัวและ server container 1 ตัว Client กับ server คุยกันผ่าน **System V message queues สองชุด** ส่วน worker threads และสถานะที่นั่งอยู่ภายใน server process เดียวกัน

## ภาพรวม

[![แผนภาพระบบ: client 1–5, request/response queues, server และ worker 1–3 พร้อมรายละเอียดภายใน](architecture.svg)](architecture.svg)

อ่านภาพจากซ้ายไปขวา: client ส่งคำสั่งเข้า **request queue** → worker ตัวหนึ่งรับไปทำงานกับสถานะที่นั่ง → ส่งผลเข้า **response queue** → client รับเฉพาะคำตอบที่ตรงกับ `requestId` ของตัวเอง เส้นสีน้ำเงินคือ request, สีเขียวคือ response, สีเทาคือการเริ่ม service หรือการเข้าถึง state ภายใน server

### แต่ละส่วนทำอะไร

| ส่วนในภาพ | สิ่งที่ใช้จริง | หน้าที่ |
| --- | --- | --- |
| Host scripts | `scripts/`, `tests/` และ Docker Compose | เริ่ม/หยุด services, เปิด client, รัน demo/load test และเก็บผลลง `results/` บน host |
| Client 1–5 | Compose services `client-1` ถึง `client-5` | แต่ละ container รอด้วย `sleep infinity`; เมื่อสั่ง `docker compose exec` จึงเริ่ม `./client <client_id>` หรือ `./load_test` ภายใน container |
| Request queue | System V `msgget`/`msgsnd`/`msgrcv` | รับคำสั่งจากทุก client ร่วมกัน; request ทุกอันใช้ `mtype = 1` |
| Response queue | System V message queue อีกชุด | รับคำตอบจาก workers; `mtype = requestId` เพื่อให้แต่ละคำขออ่านผลของตนเองได้ ไม่ต้องมี private queue |
| Server process | `./server <sync|nosync> <worker_count>` | กัน server ซ้ำด้วย `flock`, สร้าง queues, เปิด worker threads, ถือ seat state และลบ queues เมื่อปิดตามปกติ |
| Worker 1–3 | C++ `std::thread` ภายใน server process | แย่งกันรับ request จากคิวเดียว, parse/validate คำสั่ง, เรียก reservation logic และส่ง response |
| Seat state | `int seats[20]` ใน memory ของ server | `0` หมายถึงว่าง; ค่า `clientId` ที่เป็นบวกหมายถึง client นั้นจองไว้; รีเซ็ตเมื่อเริ่ม server ใหม่ |
| Seat locks | `std::mutex seatMutexes[20]` | ล็อกแยกตามที่นั่งในโหมด `sync`; โหมด `nosync` ตั้งใจไม่ใช้เพื่อสาธิต race condition |

## Container และ IPC ใช้ร่วมกันอย่างไร

`compose/compose.yaml` ให้ server ใช้ `ipc: shareable` และ clients ใช้ `ipc: service:server` จึงมองเห็น System V queues ชุดเดียวกัน ทุก container ยัง mount named volume เดียวกันที่ `/ipc` เพื่อให้ `ftok("/ipc", 'A')` และ `ftok("/ipc", 'B')` ได้ key สำหรับ request/response queue ตามลำดับ

**Queue messages ไม่ได้ถูกเก็บใน volume**: ตัว queue อยู่ใน kernel ของ IPC namespace ส่วน `/ipc` เป็นเพียง path อ้างอิงเพื่อสร้าง key และมีไฟล์ `/ipc/server.lock` สำหรับ `flock` ป้องกันการเปิด server ซ้ำ ระบบนี้ไม่ได้ใช้ System V semaphore; ตัวป้องกัน race ของที่นั่งคือ C++ `std::mutex` ใน server process

## เส้นทางของหนึ่งคำสั่ง

ตัวอย่าง client ส่ง `RESERVE 10`:

1. `./client` สร้าง `RequestMessage` ที่มี `clientId`, `requestId`, `command` แล้วส่งเข้า request queue โดยกำหนด `mtype = 1`.
2. Worker ตัวใดตัวหนึ่งรับ message จากคิว ตรวจรูปแบบ message แล้ว parse คำสั่งเป็น operation กับ seat ID.
3. Reservation logic ตรวจช่วงที่นั่ง 1–20 และสถานะการจอง หากเป็นโหมด `sync` จะใช้ mutex ของที่นั่งก่อนตรวจและแก้ค่า; หากเป็น `nosync` จะข้าม lock เพื่อให้เห็น race.
4. Worker ส่ง `ResponseMessage` เข้า response queue โดยกำหนด `mtype` เป็น `requestId` ของคำขอ และส่งเฉพาะจำนวน bytes ที่มีข้อความตอบกลับจริง.
5. Client อ่านด้วย `msgrcv(..., requestId, ...)` แล้วตรวจ `clientId` และ `requestId` ใน payload อีกครั้งก่อนแสดงผล.

คำสั่งที่ worker รองรับคือ `LIST` (ทุกที่นั่ง), `STATUS <seat_id>`, `RESERVE <seat_id> [seat_id...]`, `CANCEL <seat_id> [seat_id...]` และ `QUIT`. `QUIT` ส่ง `GOODBYE` กลับและจบ client นั้น ไม่ได้ปิด server

### Message ที่วิ่งในคิว

โครงสร้างจริงอยู่ใน [`src/models/message.h`](../src/models/message.h); ค่าคงที่อยู่ใน [`src/constants/constants.h`](../src/constants/constants.h)

| Field | Request | Response |
| --- | --- | --- |
| `mtype` | `1` สำหรับทุก request | `requestId` ของ request ต้นทาง |
| `clientId` | เจ้าของคำสั่ง/ใช้ตรวจสิทธิ์ยกเลิก | ส่งกลับเพื่อยืนยันว่าตอบถูก client |
| `requestId` | เลขระบุคำขอแต่ละครั้ง | ส่งกลับเพื่อยืนยันการจับคู่ |
| `command[128]` | ข้อความคำสั่งไม่เกิน 127 bytes + NUL | — |
| `response[2048]` | — | ข้อความผลลัพธ์ + NUL; ส่งเฉพาะความยาวที่ใช้จริง |

ระบบมี **สอง shared queues** ไม่ใช่หนึ่งคิวต่อ client หรือหนึ่งคิวต่อ worker. Client มี deadline 10 วินาทีในการส่ง request/รอ response; หากรอ response จน timeout ผลของ operation อาจยังไม่แน่นอน จึงควรตรวจ `STATUS` ก่อนส่งคำสั่งซ้ำ

## ที่นั่ง, transaction และการล็อก

ทุก worker เรียก reservation logic ใน server process เดียวกัน จึงเห็น `seats[20]` ชุดเดียวกัน การจอง/ยกเลิกหลายที่นั่งจะ sort และตัด seat ID ซ้ำ ตรวจข้อมูลและสถานะของทุกที่ก่อนอัปเดต; ถ้าตรวจไม่ผ่านจะไม่เปลี่ยนที่นั่งใดของคำขอนั้น

ในโหมด `sync` worker ล็อก mutex ของที่นั่งเป้าหมายตามลำดับ seat ID และถือไว้ตลอดช่วงตรวจจนถึงอัปเดต จึงทำ `RESERVE`/`CANCEL` หลายที่นั่งแบบ all-or-nothing เมื่อมีหลาย worker แข่งกันได้; การล็อกเรียงลำดับช่วยเลี่ยง deadlock. `STATUS` ล็อกที่นั่งเดียว และ `LIST` ล็อกครบทั้ง 20 ที่นั่งเพื่ออ่าน snapshot ที่สอดคล้องกัน

ในโหมด `nosync` worker ตรวจทุกที่นั่งก่อนอัปเดต แต่ **ไม่มี mutex รับประกันผลเมื่อหลาย worker ทำพร้อมกัน**: worker อื่นอาจเห็นที่นั่งว่างพร้อมกันและจองทับกันได้ มีการหน่วงสุ่ม 50–500 ms ระหว่างตรวจและอัปเดตเพื่อทำให้ race สังเกตได้ง่ายขึ้น โหมดนี้มีไว้สำหรับการทดลอง ไม่ควรใช้ยืนยันความถูกต้องของการจองจริง

## โหมดทดลอง

Compose overlay เปลี่ยนคำสั่งเริ่ม server โดยไม่เปลี่ยน topology ของ client และ queues:

| Experiment | Compose configuration | Server command | จุดที่สังเกต |
| --- | --- | --- | --- |
| 1: Sequential baseline | `compose/compose.sequential.yaml` | `./server sync 1` | มี worker เดียว จึงประมวลผลทีละ request |
| 2: Concurrent nosync | `compose/compose.yaml` | `./server nosync 3` | มีสาม worker และตั้งใจไม่ล็อกเพื่อแสดง race |
| 3: Concurrent sync | `compose/compose.sync.yaml` | `./server sync 3` | มีสาม worker พร้อม per-seat mutex |

`scripts/compose.sh` เลือก overlay จาก `COMPOSE_EXPERIMENT` (ค่าเริ่มต้น `nosync`). เมื่อต้องการเปลี่ยน experiment ให้หยุดแล้วเริ่ม Compose ใหม่ เพื่อให้ server และสถานะใน memory เป็นชุดใหม่ ดูคำสั่งรันจริงใน [README](../README.md)

## Logs, load test และหลักฐาน

Server log ในโหมดปกติมี `[SEQ n] [Worker-x] [Client-y]` จึงตามลำดับการรับคำสั่ง, การรอ/ได้ lock และการเข้า/ออก critical section ได้ `AIRPLANE_LOG_MODE=quiet` ลด log ระดับ worker สำหรับ benchmark แต่ไม่เปลี่ยน message flow หรือ reservation logic

`./load_test` เรียก exchange เดียวกับ client แต่สร้างหลาย threads ตามค่า concurrency และสรุป completed, transport failures, operation outcomes, throughput และ average latency. Script `scripts/load-test.ps1` เก็บ output, parameters และ server logs เป็น TXT แยกต่อรอบที่ `results/load-tests/`; demo scripts เก็บ output แยกตาม client พร้อม server logs ที่ `results/demos/`. รายชื่อไฟล์ผลลัพธ์ดูได้ใน [`results/README.md`](../results/README.md)

## แผนที่โค้ด

| Path | Responsibility |
| --- | --- |
| `src/client/` | อ่านคำสั่งจากผู้ใช้และแสดง response |
| `src/ipc/` | สร้าง/เปิด message queues, ส่งและจับคู่ message, กัน server ซ้ำ |
| `src/server/` | lifecycle ของ server, worker threads และ dispatch คำสั่ง |
| `src/reservation/` | seat state, validation, reserve/cancel และ mutex |
| `src/load_test/` | concurrent load generator และตัวเลขผลการทดสอบ |
| `src/utils/` | parser, logger และ random delay |
| `compose/` | services และ overlays ของสาม experiment |
| `scripts/`, `tests/` | คำสั่ง demo/เก็บผล และชุดทดสอบ |
