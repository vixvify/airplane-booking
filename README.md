# Airplane Reservation System

ระบบจองที่นั่งเครื่องบิน 20 ที่นั่ง เขียนด้วย C++17 ใช้ shared System V request queue และ private reply queue แยกต่อ client โดย server รับ request แล้วส่งต่อให้ worker threads ใช้ per-seat mutex ในโหมด synchronization ทั้งหมดรันใน **Docker container เดียว**; ไม่ต้องใช้ Docker Compose ดูโครงสร้างได้ที่ [docs/architecture.md](docs/architecture.md)

## สิ่งที่ต้องมี

- Docker Desktop ที่เปิด Linux containers หรือ Docker Engine บน Linux
- Git Bash สำหรับสคริปต์ `.sh` บน Windows หรือ Bash บน Linux
- PowerShell สำหรับ `scripts/load-test.ps1` บน Windows

Dockerfile build `server`, `client` และ `load_test` ภายใน Linux image ให้แล้ว ไม่จำเป็นต้องติดตั้ง compiler บน Windows

## 1. การรันผ่าน TUI (แนะนำ)

TUI จะ build image, เริ่ม server, รีเซ็ตสถานะที่นั่ง และรันงานให้ครบอัตโนมัติ จึงไม่ต้องเปิด server แยกก่อน

### เปิด TUI

Windows — ดับเบิลคลิก `run.cmd` หรือเปิด PowerShell ที่โฟลเดอร์โปรเจกต์:

```powershell
.\run.cmd
```

Linux หรือ Git Bash:

```bash
bash scripts/menu.sh
```

ปุ่มควบคุม:

- `↑`/`↓` เลือกรายการหรือช่องตั้งค่า
- `←`/`→` เปลี่ยนค่า
- `Enter` กรอกตัวเลขหรือเริ่มรัน
- `Esc` กลับเมนูก่อนหน้า
- `Q` ออกจากโปรแกรม

เมื่อเริ่มงาน TUI จะออกจากหน้าจอเมนูชั่วคราวแล้วแสดง live logs ของรอบใหม่ใน Terminal ปกติ หลังงานจบสามารถเลื่อนดูย้อนหลังได้ จากนั้นกด `Enter` เพื่อกลับเข้าเมนู ผลลัพธ์ทุกครั้งยังเก็บอยู่ใน `results/`

### Experiment 1 — Sequential baseline

1. เลือก `Experiment 1 - Sequential baseline`
2. ตั้ง `Clients`, `Command` และ `Target seat` ตามต้องการ ค่าเริ่มต้นคือ 5 clients ใช้ `RESERVE` กับ Seat 10
3. เลือก log mode และว่าจะ build image ใหม่หรือไม่
4. เลือก `RUN` แล้วกด `Enter`

Experiment 1 ล็อกจำนวน worker ไว้ที่ 1 จึงประมวลผล request ทีละรายการ ถ้าให้หลาย client จองที่นั่งเดียวกัน จะมีผู้จองสำเร็จหนึ่งรายและรายอื่นแสดง `REJECTED`

### Experiment 2 — Concurrent without synchronization

1. เลือก `Experiment 2 - Concurrent without synchronization`
2. ตั้ง `Workers` (ค่าเริ่มต้น 3), `Clients`, `Command` และ `Target seat`
3. เลือก `RUN` แล้วกด `Enter`

Workers ทำงานพร้อมกันโดยไม่ใช้ mutex หากหลาย client จองที่นั่งเดียวกัน อาจมีมากกว่าหนึ่ง client ได้รับ `SUCCESS` และผังแสดง `[10:RACE]` ผล race ขึ้นกับจังหวะการทำงาน จึงอาจต้องรันซ้ำเพื่อสังเกตอาการ

### Experiment 3 — Concurrent with synchronization

1. เลือก `Experiment 3 - Concurrent with synchronization`
2. ตั้ง `Workers` (ค่าเริ่มต้น 3), `Clients`, `Command` และ `Target seat`
3. เลือก `RUN` แล้วกด `Enter`

Workers ทำงานพร้อมกันแต่ใช้ per-seat mutex เมื่อจองที่นั่งเดียวกันจึงมีผู้สำเร็จหนึ่งราย ส่วนรายอื่นเป็น `REJECTED` และ consistency ต้องเป็น `PASSED`

สำหรับ Experiment 1–3 สามารถเลือก `LIST`, `STATUS`, `RESERVE` หรือ `CANCEL`, จำนวน clients 5–100 และ Seat 1–20 โดย `LIST` ไม่ใช้ target seat

### Demo 1 — Five clients with mixed commands

1. เลือก `Demo 1 - Five clients, mixed commands`
2. ตั้งจำนวน workers และ log mode; จำนวน clients ล็อกไว้ที่ 5
3. เลือก `RUN` แล้วกด `Enter`

หน้า Configuration จะแสดงลำดับคำสั่งของ Client 1–5 ก่อนเริ่มงาน แต่ละ client ใช้ `LIST`, `STATUS`, `RESERVE`, `CANCEL` และ `QUIT` คนละลำดับ โดยจอง 2 ที่นั่ง ยกเลิก 1 ที่นั่ง และเหลือจอง 1 ที่นั่ง ผลสุดท้ายควรเหลือ Seat 2, 3, 6, 7 และ 10 เป็นของ Client 1–5 ตามลำดับ

### Load Test

1. เลือก `Load Test`
2. เลือก `Server mode`: `sequential`, `nosync` หรือ `sync`
3. ตั้ง workers, total requests, concurrency/logical clients และ operation
4. เลือก `round-robin` เพื่อวน Seat 1–20 หรือ `fixed` เพื่อระบุ target seat
5. แนะนำ `Server logs: quiet` เมื่อต้องการวัดประสิทธิภาพ
6. เลือก `RUN` แล้วกด `Enter`

ปุ่ม `←`/`→` ที่ total requests เปลี่ยนค่าครั้งละ 100,000 หรือกด `Enter` เพื่อกรอกเอง ผลลัพธ์แสดง throughput, average latency, total time, completion, transport failures, operation results และ consistency

### การอ่านผลจาก TUI

- เขียว: สำเร็จหรือที่นั่งว่าง เช่น `[01]`
- เหลือง: `REJECTED` จาก contention ซึ่งไม่ใช่ระบบล้มเหลว
- ม่วง: ที่นั่งถูกจองตามปกติ เช่น `[10:C-1]`
- แดง: error, race หรือ consistency failure จริง เช่น `[10:RACE]`

Experiment และ Demo เก็บผลใต้ `results/demos/`; Load Test เก็บใต้ `results/load-tests/` แต่ละรอบมี `report.txt`, server logs, seat map และหลักฐานที่เกี่ยวข้อง รายละเอียดชื่อไฟล์ทั้งหมดดูที่ [results/README.md](results/README.md)

## 2. การรันแบบ Manual

วิธีนี้เหมาะสำหรับการ debug, CI หรือเมื่อต้องการควบคุมแต่ละขั้นตอนเอง ทุกคำสั่งให้รันจากโฟลเดอร์โปรเจกต์

### เตรียม image และคำสั่ง PowerShell

Build image เมื่อรันครั้งแรกหรือเมื่อ source code เปลี่ยน:

Git Bash/Linux:

```bash
bash scripts/container.sh build
```

PowerShell:

```powershell
$gitBash = "$env:ProgramFiles\Git\bin\bash.exe"
& $gitBash -lc "bash scripts/container.sh build"
```

ตัวอย่าง PowerShell ด้านล่างใช้ตัวแปร `$gitBash` นี้ หากติดตั้ง Git Bash ไว้ที่อื่นให้เปลี่ยน path ให้ตรงกับเครื่อง ก่อนเปลี่ยน Experiment ควรสั่ง `stop` เพื่อสร้าง container ใหม่และรีเซ็ตสถานะที่นั่ง:

```bash
bash scripts/container.sh stop
```

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
```

การหยุด server ไม่ลบ image หรือผลลัพธ์ใน `results/`

### Experiment 1 — Sequential baseline

Git Bash/Linux:

```bash
bash scripts/container.sh stop
bash scripts/container.sh start sequential
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
& $gitBash -lc "bash scripts/container.sh start sequential"
& $gitBash -lc "bash scripts/concurrent-test.sh"
```

ค่าเริ่มต้นคือ Client 1–5 แข่ง `RESERVE 10` ผ่าน server 1 worker ผลอยู่ที่ `results/demos/concurrent/<เวลา UTC>/`

### Experiment 2 — Concurrent without synchronization

Git Bash/Linux:

```bash
bash scripts/container.sh stop
bash scripts/container.sh start nosync 3
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
& $gitBash -lc "bash scripts/container.sh start nosync 3"
& $gitBash -lc "bash scripts/concurrent-test.sh"
```

ค่าเริ่มต้นใช้ 3 workers โดยไม่มี mutex และอาจเกิดผู้ชนะหลายรายบน Seat 10 หากยังไม่เห็น race ให้หยุด server แล้วรัน Experiment 2 ใหม่

### Experiment 3 — Concurrent with synchronization

Git Bash/Linux:

```bash
bash scripts/container.sh stop
bash scripts/container.sh start sync 3
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
& $gitBash -lc "bash scripts/container.sh start sync 3"
& $gitBash -lc "bash scripts/concurrent-test.sh"
```

ใช้ 3 workers กับ per-seat mutex จึงควรมีผู้จอง Seat 10 สำเร็จเพียงหนึ่งราย

ถ้าเปิด server ของ Experiment 1, 2 หรือ 3 ไว้แล้ว และต้องการส่ง `RESERVE 10` จาก Client 1–5 พร้อมกันโดยไม่จัดการ server ใช้สคริปต์เดียวกันแทน `concurrent-test.sh`:

```bash
bash scripts/experiments/demo.sh
```

สคริปต์แสดงผลของแต่ละ client พร้อมสรุปจำนวนสำเร็จ/ถูกปฏิเสธ/ผิดพลาด และเตือนเมื่อมีหลาย client จองที่นั่งเดียวกันสำเร็จ โดยไม่บันทึก report เป็นไฟล์ ผลที่ได้ขึ้นกับโหมด server ที่เปิดไว้ก่อนรัน หากจะทดลองซ้ำให้เริ่ม server ใหม่เพื่อรีเซ็ตสถานะที่นั่ง เลือกที่นั่งอื่นได้ด้วย `SEAT_ID=7 bash scripts/experiments/demo.sh`

กำหนดค่าของ concurrent test เองได้ด้วย environment variables:

```bash
CLIENT_COUNT=20 COMMAND=STATUS SEAT_ID=10 bash scripts/concurrent-test.sh
```

```powershell
& $gitBash -lc "CLIENT_COUNT=20 COMMAND=STATUS SEAT_ID=10 bash scripts/concurrent-test.sh"
```

รองรับ `LIST`, `STATUS`, `RESERVE` และ `CANCEL`; `CLIENT_COUNT` ต้องอยู่ระหว่าง 5–100

### Demo 1 — Five clients with mixed commands

Git Bash/Linux:

```bash
bash scripts/container.sh stop
bash scripts/container.sh start sync 3
bash scripts/demo1.sh
```

PowerShell:

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
& $gitBash -lc "bash scripts/container.sh start sync 3"
& $gitBash -lc "bash scripts/demo1.sh"
```

Demo 1 ใช้ client 5 รายแบบตายตัวและแสดง command plan ของแต่ละรายก่อนรัน ผลอยู่ที่ `results/demos/demo1/<เวลา UTC>/`

### Load Test

Load Test ต้องมี server ทำงานอยู่ก่อนเสมอ ตัวอย่างต่อไปนี้ใช้ `sync`, 3 workers และ quiet logs

Git Bash/Linux:

```bash
bash scripts/container.sh stop
AIRPLANE_LOG_MODE=quiet bash scripts/container.sh start sync 3
bash scripts/load-test.sh 50000 100 RESERVE 10
```

PowerShell:

```powershell
& $gitBash -lc "bash scripts/container.sh stop"
& $gitBash -lc "AIRPLANE_LOG_MODE=quiet bash scripts/container.sh start sync 3"
.\scripts\load-test.ps1 50000 100 RESERVE 10
```

รูปแบบคำสั่ง:

```text
load-test <total_requests> <concurrency> <STATUS|RESERVE|CANCEL> [seat_id]
```

ถ้าไม่ระบุ `seat_id` โปรแกรมจะวน Seat 1–20 แบบ round-robin ตัวอย่าง `50000 100` หมายถึง logical clients 100 รายส่งรวม 50,000 requests แต่ละ thread ใช้ client ID และ private reply queue ของตัวเองตลอดการรัน ไม่ได้สร้าง `./client` หรือ container เพิ่ม

`Throughput` นับทุก request ที่ได้รับ response ต่อวินาที รวม response แบบ `REJECTED` ด้วย ดังนั้นการยิง `RESERVE 10` ซ้ำ 50,000 ครั้งในโหมด `sync` จะมีผู้จองสำเร็จอย่างมากหนึ่งราย แต่ request ที่ถูกปฏิเสธยังนับเป็น completed requests

`quiet` ลด overhead จากการพิมพ์ server logs แต่ไม่ปิด random delay 50–500 ms ของ transaction ที่สำเร็จ ค่าเฉลี่ย latency จากการยิง `RESERVE 10` ซ้ำจำนวนมากจึงมักได้รับอิทธิพลจาก request ที่ถูกปฏิเสธอย่างรวดเร็ว ไม่ใช่เฉพาะเวลาของการจองที่สำเร็จ

ผล Load Test อยู่ที่ `results/load-tests/<เวลา UTC>/` และมี `report.txt`, `output.log`, `server.log`, `seat-map.txt` และ `summary.txt`

### กำหนดจำนวน workers เอง

ใส่จำนวน 1–64 ต่อท้ายคำสั่ง `start`:

```bash
bash scripts/container.sh start sync 5
bash scripts/container.sh start nosync 5
```

`sequential` ต้องมี 1 worker เท่านั้น หากใช้ `sync 1` ระบบจะแสดงเป็น sequential ส่วน `nosync 1` รันได้แต่ไม่มีหลาย workers ให้เกิด race

### เปิด client เองในหลาย Terminal

เริ่ม server ก่อน แล้วเปิด Terminal ใหม่ตามจำนวน client ที่ต้องการ:

```powershell
docker exec -it airplane-reservation ./client 1
docker exec -it airplane-reservation ./client 2
docker exec -it airplane-reservation ./client 3
docker exec -it airplane-reservation ./client 4
docker exec -it airplane-reservation ./client 5
```

คำสั่งที่ client รองรับ:

```text
LIST
STATUS <seat_id>
RESERVE <seat_id> [seat_id...]
CANCEL <seat_id> [seat_id...]
QUIT
```

`QUIT` ปิดเฉพาะ client process นั้น หากต้องการดู server logs แบบสดในอีก Terminal ให้รัน:

```powershell
docker logs -f airplane-reservation
```

### ใช้ Docker CLI โดยตรง

ตัวอย่างเปิด server แบบ Experiment 3 โดยไม่ผ่าน wrapper:

```powershell
docker build -t airplane-reservation:latest .
docker run -d --rm --name airplane-reservation airplane-reservation:latest ./server sync 3
```

เมื่อเสร็จให้ใช้ `docker stop airplane-reservation` เพราะ container นี้ไม่ได้เริ่มผ่าน `scripts/container.sh`

## IPC ภายใน container เดียว

Server ใช้ `ftok("/ipc", 'A')` สร้าง key ของ shared request queue ส่วน client แต่ละ process สร้าง private reply queue ด้วย `IPC_PRIVATE` แล้วส่ง queue ID ไปกับ request Server Receiver ส่งงานต่อเข้า internal work queue และ worker ตอบกลับไปยัง private queue ของ client นั้น Client ลบ queue ของตัวเองเมื่อจบการทำงาน Dockerfile สร้าง directory `/ipc` ไว้แล้ว ทุก process ใน container เดียวเห็น path และ IPC namespace เดียวกัน จึง **ไม่ต้องใช้ shared volume หรือ `ipc: host`** ข้อความอยู่ใน System V queues ของ Linux kernel ไม่ได้บันทึกเป็นไฟล์ใต้ `/ipc`

Client รอคำตอบสูงสุด 10 วินาที ถ้า timeout หลังส่ง request แล้ว จะรายงานว่า `operation outcome unknown` และไม่ส่งคำสั่งซ้ำอัตโนมัติ ให้ตรวจ `STATUS` ก่อนตัดสินใจส่งคำสั่งใหม่ ระบบไม่มี response cache

## Tests และ CI

บน Linux หรือใน container ที่มี compiler สามารถรันชุดทดสอบหลัก:

```bash
bash scripts/test.sh
```

ชุดทดสอบที่เปิด Docker container จริง (ต้องมี Docker Engine):

```bash
make test-container
```

CI build image, รัน unit/IPC/integration/regression/script tests และ container smoke tests พร้อมอัปโหลดหลักฐานจาก `results/`. ตำแหน่งไฟล์ผลลัพธ์ทั้งหมดดูที่ [results/README.md](results/README.md)
