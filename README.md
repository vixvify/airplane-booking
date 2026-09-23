# Airplane Reservation System

ระบบจองที่นั่งเครื่องบิน 20 ที่นั่ง เขียนด้วย C++17 ใช้ System V message queues สื่อสารระหว่าง client กับ server และใช้ per-seat mutex ในโหมดที่เปิด synchronization

ดูภาพรวมโครงสร้างได้ที่ [docs/architecture.md](docs/architecture.md)

## สิ่งที่ต้องมี

- Docker Desktop และ Docker Compose
- Git Bash สำหรับสคริปต์ .sh ใน Windows หรือ Bash บน Linux
- GNU Make และ C++17 compiler หากต้องการ build/test binary บน Linux โดยตรง

## การทดลอง 3 รูปแบบ

ทุกแบบใช้ client 5 ตัวส่ง `RESERVE 10` พร้อมกัน ต่างกันที่การตั้งค่า server:

| Experiment | ค่า server | ผลที่คาด |
| --- | --- | --- |
| 1. Sequential baseline | `sync 1` | สำเร็จ 1 client เพราะมี worker เดียว |
| 2. Concurrent without synchronization | `nosync 3` | อาจสำเร็จหลาย client เพื่อแสดง race condition |
| 3. Concurrent with synchronization | `sync 3` | สำเร็จ 1 client เพราะมี per-seat mutex |

Compose configuration ของแต่ละแบบอยู่ในโฟลเดอร์ `compose/`: `compose.yaml` เป็นไฟล์หลัก ส่วน `compose.sequential.yaml` และ `compose.sync.yaml` เป็น override สำหรับ Experiment 1 และ 3

## เริ่มระบบและรันการทดลอง

เปิด Git Bash ที่โฟลเดอร์โปรเจกต์ แล้วเลือก experiment ก่อนเริ่ม Compose:

```bash
export COMPOSE_EXPERIMENT=sequential
bash scripts/compose.sh up -d --build
bash scripts/concurrent-test.sh
bash scripts/compose.sh logs --tail=100 server
```

ถ้ารันจาก PowerShell ให้ใช้รูปแบบนี้แทน (`export` เป็นคำสั่งของ Bash):

```powershell
$env:COMPOSE_EXPERIMENT = "sequential"
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh up -d --build
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/concurrent-test.sh
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh logs --tail=100 server
```

ถ้าติดตั้ง Git Bash ไว้ตำแหน่งอื่น ให้เปลี่ยน path ของ `bash.exe` ให้ตรงกับเครื่อง เมื่อต้องการเปลี่ยน experiment ให้ตั้งค่า `$env:COMPOSE_EXPERIMENT` เป็น `nosync` หรือ `sync` ก่อนสั่ง `down` และ `up` ใหม่

เปลี่ยนเป็น Experiment 2 หรือ 3 โดยตั้งค่าแล้วสร้าง services ใหม่:

```bash
export COMPOSE_EXPERIMENT=nosync
bash scripts/compose.sh down
bash scripts/compose.sh up -d --build
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
$env:COMPOSE_EXPERIMENT = "nosync"
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh down
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh up -d --build
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/concurrent-test.sh
```

```bash
export COMPOSE_EXPERIMENT=sync
bash scripts/compose.sh down
bash scripts/compose.sh up -d --build
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
$env:COMPOSE_EXPERIMENT = "sync"
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh down
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh up -d --build
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/concurrent-test.sh
```

`scripts/compose.sh` ใช้ `nosync` เป็นค่าเริ่มต้น และเลือก Compose overlay ตาม `COMPOSE_EXPERIMENT` (`sequential`, `nosync` หรือ `sync`) เมื่อเปลี่ยน experiment ให้ `down` แล้ว `up` ใหม่เพื่อเริ่ม server และ IPC state รอบใหม่

ระหว่าง script ทำงานจะเห็น server log และผลของ client แบบสดใน terminal ผลแต่ละรอบเก็บแยกตามประเภทใน `results/demos/<ชนิด>/<เวลา UTC>/` เปิด `report.txt` เพื่อดูว่า client ไหนจองสำเร็จ (Demo 1 แสดงทั้งจองและยกเลิก) หรือดู `clients/client-<id>/output.log` สำหรับผลเต็มของแต่ละ client รายละเอียด path อยู่ใน [results/README.md](results/README.md)

หยุดและลบ containers เมื่อเสร็จ:

```bash
bash scripts/compose.sh down
```

ถ้าต้องการลบ named volume ที่เก็บไฟล์สำหรับ `ftok` ด้วย:

```bash
bash scripts/compose.sh down -v
```

### Demo 1: หลาย client ส่งหลายคำสั่ง

เริ่มระบบโหมด sync ก่อน จากนั้นตรวจว่าที่นั่ง 1–5 ว่างและรัน demo:

```bash
export COMPOSE_EXPERIMENT=sync
bash scripts/compose.sh up -d --build
bash scripts/demo1.sh
```

PowerShell:

```powershell
$env:COMPOSE_EXPERIMENT = "sync"
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/compose.sh up -d --build
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/demo1.sh
```

client ทั้งห้าส่ง `LIST`, `STATUS`, `RESERVE`, `CANCEL` และ `QUIT` เป็นชุดคำสั่งของตัวเอง สคริปต์ตรวจผลการจอง/ยกเลิกและบันทึกไว้ใน `results/demos/demo1/<เวลา UTC>/`

### ใช้ client แบบโต้ตอบ

เรียก client ใน service ที่ต้องการจาก terminal:

```bash
bash scripts/compose.sh exec client-1 ./client 1
```

คำสั่งที่รองรับ:

```text
LIST
STATUS <seat_id>
RESERVE <seat_id> [seat_id...]
CANCEL <seat_id> [seat_id...]
QUIT
```

## Load test

บน PowerShell ให้เริ่ม Compose ด้วย experiment ที่ต้องการตามขั้นตอนด้านบนก่อน แล้วใช้คำสั่งเดียวกันได้ทุกโหมด wrapper จะตรวจ configuration ของ server และบันทึก experiment ที่ตรวจพบให้อัตโนมัติ:

```powershell
.\scripts\load-test.ps1 50000 100 RESERVE 10
```

argument คือจำนวน request, concurrency, operation และ seat ID (ไม่บังคับ) สคริปต์จะบันทึก `output.log`, `server.log` และ `summary.txt` ในโฟลเดอร์ใหม่ใต้ `results/load-tests/<เวลา UTC>/` โดย output ของโปรแกรมรวมค่า throughput เป็น requests/sec

ตัวอย่าง:

```powershell
.\scripts\load-test.ps1 1000 20 STATUS
.\scripts\load-test.ps1 1000 20 RESERVE
.\scripts\load-test.ps1 1000 20 CANCEL 10
```

หากเรียก executable โดยตรงใน Git Bash:

```bash
bash scripts/compose.sh exec -T client-1 ./load_test 1000 20 STATUS
```

`load_test` แยก transport failure ออกจาก operation failure และใช้ client IDs กับ seat mapping แบบคงที่ หากทดสอบ `CANCEL` ให้ส่ง `RESERVE` ชุดเดียวกันก่อน เพื่อให้ request ใช้ owner และ seat mapping เดิม

## หลักการ IPC ใน Compose

service `server` ใช้ IPC namespace แบบ shareable ส่วน services `client-1` ถึง `client-5` ใช้ namespace เดียวกับ server ผ่าน Compose `ipc: service:server` ทุก service mount named volume เดียวกันที่ `/ipc` เพื่อให้ `ftok("/ipc", 'A')` สร้าง key ตรงกัน

คิว System V จึงแชร์กันเฉพาะระหว่าง services ใน Compose project นี้ ไม่ต้องแชร์ IPC namespace ของ host

## Build และ tests

Build binaries บน Linux:

```bash
make
```

รัน unit, IPC, integration, regression และ script tests:

```bash
bash scripts/test.sh
```

รัน Compose smoke tests เพิ่มเติม (ต้องมี Docker engine ทำงาน):

```bash
make test-compose
```

CI build image และรัน test suite รวม Compose smoke tests พร้อมเก็บ artifacts ใน `results/` รูปแบบโฟลเดอร์และตำแหน่ง log ดูได้ที่ [results/README.md](results/README.md)
