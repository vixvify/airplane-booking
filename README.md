# Airplane Reservation System

ระบบจองที่นั่งเครื่องบิน 20 ที่นั่ง เขียนด้วย C++17 ใช้ System V message queues ระหว่าง client processes กับ server process และใช้ per-seat mutex ในโหมด synchronization ทั้งหมดรันใน **Docker container เดียว**; ไม่ต้องใช้ Docker Compose ดูโครงสร้างได้ที่ [docs/architecture.md](docs/architecture.md)

## สิ่งที่ต้องมี

- Docker Desktop ที่เปิด Linux containers หรือ Docker Engine บน Linux
- Git Bash สำหรับสคริปต์ `.sh` บน Windows หรือ Bash บน Linux
- PowerShell สำหรับ `scripts/load-test.ps1` บน Windows

Dockerfile build `server`, `client` และ `load_test` ภายใน Linux image ให้แล้ว ไม่จำเป็นต้องติดตั้ง compiler บน Windows

## เมนูสำหรับรันโปรเจกต์ (แนะนำ)

บน Windows ให้ดับเบิลคลิก `run.cmd` ที่โฟลเดอร์โปรเจกต์ หรือเปิด PowerShell แล้วรันเพียงครั้งเดียว:

```powershell
.\run.cmd
```

บน Linux หรือ Git Bash:

```bash
bash scripts/menu.sh
```

เมนูทำงานเต็มหน้าจอใน Terminal ใช้ปุ่ม `↑`/`↓` เลือกรายการ, `←`/`→` เปลี่ยนค่า, `Enter` แก้ตัวเลขหรือเริ่มรัน, `Esc` ย้อนกลับ และ `Q` ออก เมนูมี Experiment 1–3, Demo 1, Load test, สถานะ server และหยุด server โดยจัดการ build, restart และรีเซ็ตสถานะที่นั่งให้อัตโนมัติ

เมื่อเริ่มรัน test เมนูจะสลับกลับมายังหน้าจอ Terminal ปกติ ล้างข้อความของการรันก่อนหน้า และแสดงเฉพาะ live logs ของรอบใหม่ซึ่งเลื่อนดูย้อนหลังได้ หลังงานจบให้เลื่อนตรวจ logs ก่อน แล้วกด `Enter` เพื่อกลับเข้าเมนู ส่วนผลรอบเก่ายังอยู่ครบใน `results/`

หลังจบ Experiment, Demo หรือ Load Test จะแสดงผังที่นั่ง 20 ที่นั่งเป็น cabin ยาว 10 แถว 2 คอลัมน์พร้อมทางเดินกลาง โดยฝั่งซ้ายเป็น Seat 1–10 และฝั่งขวาเป็น Seat 11–20 ที่นั่งว่างแสดงเป็นสีเขียว เช่น `[01]` และที่นั่งที่จองแล้วแสดง owner จริงจากสถานะสุดท้ายเป็นสีแดง เช่น `[10:C-1]` หมายถึง Seat 10 มี owner สุดท้ายเป็น Client-1 หากหลาย client ได้รับ `SUCCESS` สำหรับที่นั่งเดียวกัน ผังจะแสดง `[10:RACE]`, ให้ consistency check เป็น `FAILED` และแสดงทั้งรายชื่อ client ที่สำเร็จกับ owner สุดท้ายแยกกัน โดยจะไม่มี owner ตัวอย่างแบบ hard-coded ใน legend หลักฐานดิบถูกเก็บใน `seat-map.txt` และ `seat-conflicts.txt` ของรอบนั้น

- Experiment 1–3 เลือกคำสั่ง `LIST`, `STATUS`, `RESERVE` หรือ `CANCEL`, จำนวน clients, target seat, workers (ยกเว้น Experiment 1 ที่ต้องเป็น 1 worker), log mode และว่าจะ build image ใหม่หรือไม่ โดย `LIST` ไม่ใช้ target seat
- Demo 1 เลือก workers และ log mode; จำนวน clients คงที่ 5 เพราะชุดคำสั่งของเดโมกำหนดไว้ตาม requirement
- Load test เลือก server mode, workers, total requests, concurrency/logical clients, operation, fixed/round-robin seat, log mode และการ build image โดยกด `←`/`→` ที่ total requests จะเปลี่ยนครั้งละ 100,000 หรือกด `Enter` เพื่อกรอกเอง

หัวข้อคำสั่งด้านล่างเก็บไว้เป็นทางเลือกสำหรับ CI, การ debug หรือเครื่องที่ไม่ต้องการใช้เมนู

## เตรียมก่อนทดลอง

Build image ครั้งเดียวจากโฟลเดอร์โปรเจกต์ แล้วเลือกหัวข้อที่จะรันด้านล่าง ไม่ต้องเปิด server แยกก่อน:

Git Bash:

```bash
bash scripts/container.sh build
```

PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh build"
```

ถ้าติดตั้ง Git Bash ไว้ที่อื่น ให้เปลี่ยน path ของ `bash.exe`. ทุกหัวข้อใช้ container ชื่อ `airplane-reservation` และ client เป็น processes ภายใน container เดียว ไม่ได้สร้าง container แยกต่อตัว

**ก่อนเริ่มหัวข้อถัดไป** ให้หยุด server รอบเดิมเพื่อรีเซ็ตที่นั่ง แล้วค่อยรันชุดคำสั่งของหัวข้อนั้น (ถ้ายังไม่ได้เปิด server ให้ข้ามขั้นตอนนี้):

```bash
bash scripts/container.sh stop
```

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh stop"
```

คำสั่ง `stop` ใช้กับ container ที่เริ่มด้วย `scripts/container.sh` เท่านั้น เมื่อหยุดแล้ว Docker จะลบ container นั้นอัตโนมัติ ไม่ลบ image หรือไฟล์ผลลัพธ์ใน `results/`

จำนวน worker เริ่มต้นคือ `sequential` = 1, `nosync` = 3 และ `sync` = 3 หากต้องการกำหนดเอง ให้ใส่จำนวน 1–64 ต่อท้าย `start` เช่น `bash scripts/container.sh start sync 5` หรือใน PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start sync 5"
```

ใช้ `nosync 5` ได้เช่นกัน ส่วน `sequential` ต้องมี 1 worker เท่านั้น หลังเริ่ม server ด้วยจำนวนที่กำหนดเอง คำสั่ง Demo 1, concurrent test และ load test ด้านล่างใช้ได้เหมือนเดิม โดยรายงานจะบันทึกจำนวน worker ที่ตรวจพบจาก container ที่กำลังรันอยู่ หากใช้ `sync 1` ระบบจะแสดงเป็น `sequential`; `nosync 1` รันได้ แต่ไม่มี workers หลายตัวให้เกิด race

## Demo 1: หลาย client ส่งหลายคำสั่ง

เปิด server แบบ 3 workers พร้อม synchronization แล้วให้ client 1–5 ส่งคำสั่งต่างชนิดกันพร้อมกัน

Git Bash:

```bash
bash scripts/container.sh start sync
bash scripts/demo1.sh
```

PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start sync"
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/demo1.sh"
```

ผลที่ควรเห็น: Client 1–5 ส่ง `LIST`, `STATUS`, `RESERVE`, `CANCEL`, `QUIT` คนละลำดับ แต่ละคนจองพร้อมกัน 2 ที่นั่งจากช่วง Seat 1–10 แล้วยกเลิกเพียง 1 ที่นั่ง รวมจองสำเร็จ 10 ที่นั่ง ยกเลิก 5 ที่นั่ง และตอนจบยังเหลือ Seat 2, 3, 6, 7, 10 ถูกจองโดย Client 1–5 ตามลำดับ ผังที่นั่งท้ายรายงานจึงมีทั้งที่นั่งว่างและที่นั่งที่ยังถูกจองอยู่

ผลบันทึก: `results/demos/demo1/<เวลา UTC>/report.txt` สรุปผลราย client และจำนวน workers; โฟลเดอร์เดียวกันมี `server-live.log`, `server.log` และ `clients/`

## Experiment 1: Sequential baseline

เปิด server แบบ 1 worker (`sync 1`) แล้วให้ client 1–5 แข่งจอง Seat 10

Git Bash:

```bash
bash scripts/container.sh start sequential
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start sequential"
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/concurrent-test.sh"
```

ผลที่ควรเห็น: server ประมวลผลทีละ request เพราะมี worker เดียว จอง Seat 10 สำเร็จ 1 client; client ที่เหลือได้ผลล้มเหลวเพราะที่นั่งถูกจองแล้ว ค่าเริ่มต้นคือ 5 clients และเมนูเลือกได้ 5–100

ผลบันทึก: `results/demos/concurrent/<เวลา UTC>/report.txt` ระบุ `Experiment: sequential`, จำนวน workers และผลราย client; โฟลเดอร์เดียวกันมี server logs และ `clients/`

## Experiment 2: Concurrent without synchronization

เปิด server แบบ 3 workers โดยไม่ล็อกที่นั่ง (`nosync 3`) แล้วให้ client 1–5 แข่งจอง Seat 10

Git Bash:

```bash
bash scripts/container.sh start nosync
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start nosync"
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/concurrent-test.sh"
```

ผลที่ควรเห็น: อาจมี client มากกว่า 1 คนได้รับผลจอง Seat 10 สำเร็จ เพราะ workers อ่านสถานะก่อนเขียนทับกัน นี่เป็น race condition; ผลแต่ละรอบไม่รับประกันว่าจะเกิด ถ้ายังเห็นผู้ชนะเพียงคนเดียว ให้หยุด server เริ่ม `nosync` ใหม่ แล้วรันสคริปต์ซ้ำ ค่าเริ่มต้นคือ 5 clients และเมนูเลือกได้ 5–100

ผลบันทึก: `results/demos/concurrent/<เวลา UTC>/report.txt` ระบุ `Experiment: nosync`, จำนวน workers และจำนวนผู้จองสำเร็จ; โฟลเดอร์เดียวกันมี server logs และ `clients/`

## Experiment 3: Concurrent with synchronization

เปิด server แบบ 3 workers พร้อม per-seat mutex (`sync 3`) แล้วให้ client 1–5 แข่งจอง Seat 10

Git Bash:

```bash
bash scripts/container.sh start sync
bash scripts/concurrent-test.sh
```

PowerShell:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start sync"
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/concurrent-test.sh"
```

ผลที่ควรเห็น: จอง Seat 10 สำเร็จ 1 client; client ที่เหลือล้มเหลวเพราะ mutex ทำให้ workers ตรวจและอัปเดตที่นั่งทีละคน เทียบกับ Experiment 2 เพื่อดูผลของ synchronization ค่าเริ่มต้นคือ 5 clients และเมนูเลือกได้ 5–100

ผลบันทึก: `results/demos/concurrent/<เวลา UTC>/report.txt` ระบุ `Experiment: sync`, จำนวน workers และผลราย client; โฟลเดอร์เดียวกันมี server logs และ `clients/`

## เปิด client เองในหลาย Terminal

ถ้าต้องการลองคำสั่งเอง ให้เปิด server ด้วย `bash scripts/container.sh start sync` (หรือโหมดที่ต้องการ) ก่อน จากนั้นเปิด Terminal ใหม่ 5 หน้าต่าง และรันหน้าต่างละหนึ่งบรรทัด:

```powershell
docker exec -it airplane-reservation ./client 1
docker exec -it airplane-reservation ./client 2
docker exec -it airplane-reservation ./client 3
docker exec -it airplane-reservation ./client 4
docker exec -it airplane-reservation ./client 5
```

สามารถเพิ่ม client โดยใช้ ID อื่น เช่น 6, 7, ... คำสั่งใน client มีดังนี้:

```text
LIST
STATUS <seat_id>
RESERVE <seat_id> [seat_id...]
CANCEL <seat_id> [seat_id...]
QUIT
```

`QUIT` ปิดเฉพาะ client process นั้น ไม่ได้หยุด server ถ้าต้องการดู log ของ server สด ๆ ในอีก Terminal ให้รัน `docker logs -f airplane-reservation`

## ใช้ Docker CLI โดยไม่ผ่านสคริปต์

ตัวอย่างเปิด server แบบ Experiment 3 โดยตรง (ไม่ต้องใช้ Compose):

```powershell
docker build -t airplane-reservation:latest .
docker run -d --rm --name airplane-reservation airplane-reservation:latest ./server sync 3
```

สคริปต์ demo และ load test ยังใช้งานกับ container นี้ได้ เมื่อเสร็จแล้วให้ใช้ `docker stop airplane-reservation` แทน `scripts/container.sh stop` ซึ่งตั้งใจหยุดเฉพาะ container ที่สคริปต์สร้างไว้

## Load test

ต้องเปิด server ก่อนเสมอ ตัวอย่างบน PowerShell:

```powershell
.\scripts\load-test.ps1 50000 100 RESERVE 10
```

argument คือจำนวน request, concurrency (จำนวน threads หรือ logical clients), operation `STATUS`/`RESERVE`/`CANCEL` และ seat ID ที่ไม่บังคับ หากไม่ระบุ seat ID โปรแกรมจะวน 1–20 แต่ละ thread ใช้ client ID เดิมตลอดรอบและส่งคำขอของตัวเองทีละรายการ เช่น `50000 100` คือ 100 logical clients ส่งรวม 50,000 requests ไม่ได้เปิด `./client` หรือ containers เพิ่ม

PowerShell/Bash wrapper ตรวจโหมดและจำนวน workers จาก server container ที่กำลังรัน แล้วแสดง dashboard สรุป configuration, throughput, average latency, total time, completion, transport failures, operation results และ consistency แยกเป็นส่วนชัดเจน พร้อมบันทึก `report.txt`, `output.log` ฉบับเต็ม, `server.log` และ `summary.txt` สำหรับ CI ใต้ `results/load-tests/<เวลา UTC>/` หากใช้ Git Bash สามารถเรียก binary โดยตรง:

```bash
bash scripts/load-test.sh 1000 20 STATUS
```

`Throughput` นับคำขอที่ได้รับ response ต่อวินาที รวม response ที่บอกว่าจองไม่สำเร็จด้วย ดังนั้น `RESERVE 10` ซ้ำ 50,000 ครั้งจะมีผู้ชนะอย่างมากหนึ่งรายในโหมด `sync` ส่วนคำขอที่เหลือยังนับเป็น completed requests

### วัดประสิทธิภาพด้วย quiet mode

ค่าเริ่มต้นเป็น `verbose` เพื่อดู worker logs ระหว่าง demo หากต้องการวัด latency โดยลด overhead ของ log ให้เริ่ม container ใหม่ด้วย `AIRPLANE_LOG_MODE=quiet`:

```powershell
$env:AIRPLANE_CONTAINER_NAME = "airplane-perf"
$env:AIRPLANE_LOG_MODE = "quiet"
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh start sync"
.\scripts\load-test.ps1 1000000 100 STATUS
.\scripts\load-test.ps1 50000 100 RESERVE 10
& "$env:ProgramFiles\Git\bin\bash.exe" -lc "bash scripts/container.sh stop"
Remove-Item Env:AIRPLANE_CONTAINER_NAME, Env:AIRPLANE_LOG_MODE
```

ต้อง build image ก่อนตัวอย่างนี้ โหมด `quiet` ไม่ปิด random delay 50–500 ms ของการจองที่สำเร็จ ค่าเฉลี่ย latency ที่ต่ำจากการยิง `RESERVE 10` ซ้ำ ๆ ส่วนใหญ่เป็นเวลาของคำขอที่ถูกปฏิเสธ ไม่ใช่เวลาการจองสำเร็จ

## IPC ภายใน container เดียว

Server ใช้ `ftok("/ipc", 'A')` และ `ftok("/ipc", 'B')` สร้าง keys ของ request/response queues ตามลำดับ Dockerfile สร้าง directory `/ipc` ไว้แล้ว ทุก process ใน container เดียวเห็น path และ IPC namespace เดียวกัน จึง **ไม่ต้องใช้ shared volume หรือ `ipc: host`** ข้อความอยู่ใน System V queues ของ Linux kernel ไม่ได้บันทึกเป็นไฟล์ใต้ `/ipc`

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
