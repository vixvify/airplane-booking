# Airplane Reservation System — Experiment Report

วันที่ทดลอง: 1 ตุลาคม 2026

รายงานนี้สรุปผลการทดลอง Experiment 1–3 และ Demo 1 จากหลักฐานจริงใน `docs/evidence/2026-10-01/experiment-transcripts.txt` โดยแยก configuration, ผลรายรอบ, ผลรายคน และหลักฐาน log อ้างอิงสำหรับแต่ละค่า

> **การอ่านผล:** `REJECTED` ในการทดสอบแย่งจองที่นั่งเดียวกันเป็น expected contention ไม่ใช่ความผิดพลาดของ test script ส่วน `SUCCESS - RACE` หมายถึง client ได้รับ SUCCESS แต่เกิด seat conflict จริง (มีผู้อื่นได้ SUCCESS บน seat เดียวกัน)

---

## 1. Environment และเกณฑ์การทดลอง

### Environment

| Configuration | Value |
| --- | --- |
| Source commit | `d6dab3528f354159668039bc5d011c14ca7de717` |
| Branch ขณะทดลอง | `task/concurrency-updates` |
| Container image | `airplane-reservation:study-2026-10-01` (`sha256:6272f86561cd...`) |
| Docker | Docker Desktop 29.7.2 |
| Runtime kernel | Linux 6.18.33.1-microsoft-standard-WSL2 |
| Host resources | 12 CPUs, RAM 15.58 GiB (16,729,645,056 bytes) |
| Architecture | x86_64 |
| IPC | System V shared request queue + private reply queue per client |
| Compiler | GCC 14.3.0, `-std=c++17 -Wall -Wextra -pthread` |
| Application timeout | 10 วินาทีต่อ request/response |
| External run guard | 180 วินาทีต่อรอบ |
| Started UTC | 2026-10-01T14:39:06.339273Z |

**หลักฐาน:** `docs/evidence/2026-10-01/environment.json`

### Common controls

| Control | Value | เหตุผล |
| --- | --- | --- |
| Fresh server | Restart container + ที่นั่งว่างใหม่ก่อนทุกรอบ | ป้องกัน seat state, IPC queue และ log ค้างจากรอบก่อน |
| Concurrent target | 5 clients จอง Seat 10 พร้อมกัน | ให้ทุก client แข่งบน resource เดียวกัน |
| Delay | 50–500 ms artificial delay ใน transaction | ขยายหน้าต่าง race condition ให้สังเกตได้ |
| Server logging | Verbose — log ทุก request | บันทึกลำดับการประมวลผล |
| Formal repetitions | 3 fresh-container runs ต่อการทดลอง | ตรวจความสม่ำเสมอของผล |

### ความหมายของ metrics

| Metric | ความหมาย |
| --- | --- |
| Success | Client ได้รับ `SUCCESS` จาก server |
| Rejected | Client ได้รับ `FAILED` เพราะ seat ถูกจองแล้ว (business rejection) |
| Consistency | ตรวจว่ามี client มากกว่าหนึ่งรายได้ SUCCESS บน seat เดียวกันหรือไม่ |
| RACE | Client ได้ SUCCESS แต่ seat-conflicts.txt บันทึก conflict — หมายถึง race condition เกิดขึ้น |
| Final owner | Client ที่ seat map บันทึกเป็น owner หลังรอบจบ (last-write-wins) |

---

## 2. Experiment 1 — Sequential baseline

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `sequential` |
| Server mode | `sync` |
| Workers | 1 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Synchronization | Enabled (per-seat lock) — แต่ใช้เพียง 1 worker จึงไม่มีการ contend lock |
| Server logging | Verbose |
| Artificial delay | 50–500 ms |
| Repetitions | 3 fresh-container runs |

Baseline ใช้ worker เพียงหนึ่งตัว จึงประมวลผล request ทีละรายการ แม้ clients ทั้ง 5 จะเริ่มพร้อมกัน

### Result summary

| Run | Started UTC | Success | Rejected | Transport Fail | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 1 | 2026-10-01T14:39:07.066916957Z | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 2 | 2026-10-01T14:39:08.574695087Z | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 3 | 2026-10-01T14:39:10.089449998Z | 1/5 | 4/5 | 0 | Client-2 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 2 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 3 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |

### หลักฐาน log (Experiment 1)

**Run 1** — `experiment1-sync-w1-verbose-c5-r1` ใน `experiment-transcripts.txt`
```
artifacts\demos\concurrent\2026-10-01_14-39-07\clients\client-2\output.log
  Client-2 connected. Enter commands (LIST, STATUS, RESERVE, CANCEL, QUIT).
  SUCCESS: Seat 10 reserved

artifacts\demos\concurrent\2026-10-01_14-39-07\clients\client-1\output.log
  FAILED: Transaction cancelled because Seat 10 is already reserved

artifacts\demos\concurrent\2026-10-01_14-39-07\seat-map.txt
  Seat 10 : RESERVED by Client-2

artifacts\demos\concurrent\2026-10-01_14-39-07\report.txt
  Successful reservations: 1/5
  Failed reservations: 4/5
  Consistency check: PASSED
```

**Run 2** — `experiment1-sync-w1-verbose-c5-r2`
```
artifacts\demos\concurrent\2026-10-01_14-39-08\clients\client-2\output.log
  SUCCESS: Seat 10 reserved
  Seat map: Seat 10 : RESERVED by Client-2
  Consistency check: PASSED
```

**Run 3** — `experiment1-sync-w1-verbose-c5-r3`
```
artifacts\demos\concurrent\2026-10-01_14-39-10\clients\client-2\output.log
  SUCCESS: Seat 10 reserved
  Seat map: Seat 10 : RESERVED by Client-2
  Consistency check: PASSED
```

**IPC หลังจบทุกรอบ:** private reply queues ถูกลบครบ — `key 0x41e82bde msqid 0 used-bytes 0 messages 0`

**สรุป:** ผลตรงตาม baseline ทั้ง 3 รอบ Client-2 ชนะทุกรอบ (ได้รับ queue ก่อนในระบบ sequential) ไม่พบ seat conflict ใดๆ

---

## 3. Experiment 2 — Concurrent without synchronization

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `nosync` |
| Server mode | `nosync` |
| Workers | 3 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Synchronization | **Disabled** — ไม่มี lock ครอบ check/write |
| Server logging | Verbose |
| Artificial delay | 50–500 ms |
| Repetitions | 3 fresh-container runs |

Workers 3 ตัวทำงานพร้อมกันโดยไม่ล็อก critical section เพื่อสาธิต race condition ระหว่างการ check และ write Seat 10

### Result summary

| Run | Started UTC | Success (RACE) | Rejected | Transport Fail | Clients ที่ได้ SUCCESS | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 2026-10-01T14:39:11.436952193Z | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-1 | FAILED — 1 conflict |
| 2 | 2026-10-01T14:39:13.135150202Z | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-2 | FAILED — 1 conflict |
| 3 | 2026-10-01T14:39:14.802144602Z | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-1 | FAILED — 1 conflict |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |
| 2 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |
| 3 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |

### หลักฐาน log (Experiment 2)

**Run 1** — `experiment2-nosync-w3-verbose-c5-r1`
```
artifacts\demos\concurrent\2026-10-01_14-39-11\clients\client-1\output.log
  SUCCESS: Seat 10 reserved
artifacts\demos\concurrent\2026-10-01_14-39-11\clients\client-2\output.log
  SUCCESS: Seat 10 reserved
artifacts\demos\concurrent\2026-10-01_14-39-11\clients\client-3\output.log
  SUCCESS: Seat 10 reserved
artifacts\demos\concurrent\2026-10-01_14-39-11\clients\client-4\output.log
  FAILED: Transaction cancelled because Seat 10 is already reserved

artifacts\demos\concurrent\2026-10-01_14-39-11\seat-conflicts.txt
  10|Client-1, Client-2, Client-3|Client-1

artifacts\demos\concurrent\2026-10-01_14-39-11\seat-map.txt
  Seat 10 : RESERVED by Client-1

artifacts\demos\concurrent\2026-10-01_14-39-11\report.txt
  Successful reservations: 3/5
  Failed reservations: 2/5
  Consistency check: FAILED (1 seat conflict detected)
```

> **อ่าน seat-conflicts.txt:** `10|Client-1, Client-2, Client-3|Client-1`  
> หมายถึง Seat 10 มี 3 clients ได้รับ SUCCESS (Client-1, 2, 3) แต่ seat map บันทึก Client-1 เป็น final owner

**Run 2** — `experiment2-nosync-w3-verbose-c5-r2`
```
seat-conflicts.txt: 10|Client-1, Client-2, Client-3|Client-2
seat-map.txt: Seat 10 : RESERVED by Client-2
report.txt: Consistency check: FAILED (1 seat conflict detected)
```

**Run 3** — `experiment2-nosync-w3-verbose-c5-r3`
```
seat-conflicts.txt: 10|Client-1, Client-2, Client-3|Client-1
seat-map.txt: Seat 10 : RESERVED by Client-1
report.txt: Consistency check: FAILED (1 seat conflict detected)
```

**สรุป:** เกิด race condition ครบ 3/3 รอบ Client-1, 2, 3 ได้รับ SUCCESS ทุกรอบ แต่ final owner เปลี่ยนตาม thread scheduling (non-deterministic) แสดงให้เห็นว่าการดูเฉพาะ seat map ท้ายรอบไม่เพียงพอ — ต้องตรวจ response ที่แต่ละ client ได้รับด้วย

---

## 4. Experiment 3 — Concurrent with synchronization

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `sync` |
| Server mode | `sync` |
| Workers | 3 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Synchronization | **Enabled** — per-seat mutex ครอบ check/write |
| Server logging | Verbose |
| Artificial delay | 50–500 ms |
| Repetitions | 3 fresh-container runs |

ใช้ configuration เดียวกับ nosync แต่เพิ่ม per-seat mutex ครอบ critical section

### Result summary

| Run | Started UTC | Success | Rejected | Transport Fail | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 1 | 2026-10-01T14:39:16.560856575Z | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 2 | 2026-10-01T14:39:18.168378780Z | 1/5 | 4/5 | 0 | Client-4 | PASSED |
| 3 | 2026-10-01T14:39:19.955419239Z | 1/5 | 4/5 | 0 | Client-3 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 2 | REJECTED | REJECTED | REJECTED | **SUCCESS** | REJECTED |
| 3 | REJECTED | REJECTED | **SUCCESS** | REJECTED | REJECTED |

### หลักฐาน log (Experiment 3)

**Run 1** — `experiment3-sync-w3-verbose-c5-r1`
```
artifacts\demos\concurrent\2026-10-01_14-39-16\clients\client-2\output.log
  SUCCESS: Seat 10 reserved
artifacts\demos\concurrent\2026-10-01_14-39-16\clients\client-1\output.log
  FAILED: Transaction cancelled because Seat 10 is already reserved

artifacts\demos\concurrent\2026-10-01_14-39-16\seat-conflicts.txt
  (empty — ไม่มี conflict)

artifacts\demos\concurrent\2026-10-01_14-39-16\seat-map.txt
  Seat 10 : RESERVED by Client-2

artifacts\demos\concurrent\2026-10-01_14-39-16\report.txt
  Successful reservations: 1/5
  Failed reservations: 4/5
  Consistency check: PASSED
```

**Run 2** — `experiment3-sync-w3-verbose-c5-r2`
```
artifacts\demos\concurrent\2026-10-01_14-39-18\clients\client-4\output.log
  SUCCESS: Seat 10 reserved
seat-map.txt: Seat 10 : RESERVED by Client-4
seat-conflicts.txt: (empty)
report.txt: Consistency check: PASSED
```

**Run 3** — `experiment3-sync-w3-verbose-c5-r3`
```
artifacts\demos\concurrent\2026-10-01_14-39-19\clients\client-3\output.log
  SUCCESS: Seat 10 reserved
seat-map.txt: Seat 10 : RESERVED by Client-3
seat-conflicts.txt: (empty)
report.txt: Consistency check: PASSED
```

**สรุป:** ผ่าน 3/3 รอบ ไม่พบ seat conflict ใดๆ แม้มี 3 workers ทำงานพร้อมกัน ผู้ชนะเปลี่ยนในแต่ละรอบ (C2→C4→C3) แตกต่างจาก Experiment 1 ที่ Client-2 ชนะทุกรอบ เพราะ mutex ไม่ lock priority — แค่รับประกันว่ามีเพียงคนเดียวที่สำเร็จ

---

## 5. Demo 1 — Mixed commands

### Configuration

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Clients | 5 |
| Commands covered | `LIST`, `STATUS`, `RESERVE`, `CANCEL`, `QUIT` |
| Workload per client | จอง 2 ที่นั่ง ยกเลิก 1 ที่นั่ง เหลือ 1 ที่นั่งต่อ client |
| Seat range | Seats 1–10 |
| Server logging | Verbose |
| Repetitions | 3 fresh-container runs |
| Expected final seats | Seat 2:C1, 3:C2, 6:C3, 7:C4, 10:C5 |

### Fixed command plan per client

| Client | Command sequence | Expected final reservation |
| --- | --- | --- |
| Client-1 | `LIST → RESERVE 1 2 → STATUS 1 → CANCEL 1 → STATUS 2 → QUIT` | Seat 2 |
| Client-2 | `STATUS 3 → RESERVE 3 4 → CANCEL 4 → STATUS 3 → LIST → QUIT` | Seat 3 |
| Client-3 | `RESERVE 5 6 → LIST → CANCEL 5 → STATUS 6 → QUIT` | Seat 6 |
| Client-4 | `RESERVE 7 8 → STATUS 8 → CANCEL 8 → LIST → STATUS 7 → QUIT` | Seat 7 |
| Client-5 | `LIST → RESERVE 9 10 → CANCEL 9 → STATUS 10 → QUIT` | Seat 10 |

**หมายเหตุ:** Commands สำหรับ client ทุกรายถูกกำหนดตายตัวใน `scripts/demo1.sh` และเหมือนกันทั้ง 3 รอบ

### Result summary

| Run | Started UTC | Reservations | Failed | Cancellations | Remaining | Consistency |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | 2026-10-01T14:39:21.550129249Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 2 | 2026-10-01T14:39:24.407257109Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 3 | 2026-10-01T14:39:27.Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |

### Client results (เหมือนกันทั้ง Run 1, 2 และ 3)

| Client | Reserved seats | Cancelled seat | Remains reserved | ตรงแผน |
| --- | --- | --- | --- | --- |
| Client-1 | SUCCESS — Seats 1, 2 | SUCCESS — Seat 1 | SUCCESS — Seat 2 | ✅ |
| Client-2 | SUCCESS — Seats 3, 4 | SUCCESS — Seat 4 | SUCCESS — Seat 3 | ✅ |
| Client-3 | SUCCESS — Seats 5, 6 | SUCCESS — Seat 5 | SUCCESS — Seat 6 | ✅ |
| Client-4 | SUCCESS — Seats 7, 8 | SUCCESS — Seat 8 | SUCCESS — Seat 7 | ✅ |
| Client-5 | SUCCESS — Seats 9, 10 | SUCCESS — Seat 9 | SUCCESS — Seat 10 | ✅ |

### หลักฐาน log (Demo 1)

**Run 1** — `demo1-sync-w3-verbose-c5-r1`
```
artifacts\demos\demo1\2026-10-01_14-39-21\clients\client-1\output.log
  SUCCESS: Seat 1 reserved
  SUCCESS: Seat 2 reserved
  Seat 1 is RESERVED by Client-1
  SUCCESS: Seat 1 cancelled
  Seat 2 is RESERVED by Client-1

artifacts\demos\demo1\2026-10-01_14-39-21\clients\client-5\output.log
  SUCCESS: Seat 9 reserved
  SUCCESS: Seat 10 reserved
  SUCCESS: Seat 9 cancelled
  Seat 10 is RESERVED by Client-5

artifacts\demos\demo1\2026-10-01_14-39-21\seat-map.txt
  Seat 2 : RESERVED by Client-1
  Seat 3 : RESERVED by Client-2
  Seat 6 : RESERVED by Client-3
  Seat 7 : RESERVED by Client-4
  Seat 10 : RESERVED by Client-5

artifacts\demos\demo1\2026-10-01_14-39-21\report.txt
  Successful seat reservations: 10/10
  Failed seat reservations: 0/10
  Successful cancellations: 5/5
  Seats remaining reserved: 5/5
  Consistency check: PASSED
```

**Run 2** — `demo1-sync-w3-verbose-c5-r2`
```
artifacts\demos\demo1\2026-10-01_14-39-24\report.txt
  Successful seat reservations: 10/10
  Failed seat reservations: 0/10
  Successful cancellations: 5/5
  Seats remaining reserved: 5/5
  Consistency check: PASSED
  
seat-map.txt: Seat 2:C1, 3:C2, 6:C3, 7:C4, 10:C5 (ตรงทุก run)
```

**สรุป:** Demo 1 ผ่านครบ 3/3 รอบ ทุก operation สำเร็จ final state ตรงตาม command plan ทุก client และไม่มี seat conflict

---

## 6. Correctness comparison

| Experiment | Workers | Synchronization | Success pattern | Consistency | Conclusion |
| --- | ---: | --- | --- | --- | --- |
| Sequential (Exp 1) | 1 | Enabled | 1/5 ทุก run — Client-2 ชนะ | PASS 3/3 | Baseline ถูกต้อง; deterministic winner |
| Nosync (Exp 2) | 3 | **Disabled** | 3/5 ทุก run — RACE ทุก run | FAIL 3/3 | Race condition เกิดครบทุกรอบ |
| Sync (Exp 3) | 3 | Enabled | 1/5 ทุก run — winner เปลี่ยน | PASS 3/3 | Mutex ป้องกัน race ได้; non-deterministic |
| Demo 1 | 3 | Enabled | 10 reserves + 5 cancels | PASS 3/3 | คำสั่งหลักทำงานครบทุกรอบ |

### Key findings

1. **1 worker eliminates concurrency risk** — Experiment 1 แสดงว่า sequential processing รับประกัน correctness โดย trade-off throughput
2. **Nosync reproduces race consistently** — ทั้ง 3 รอบเกิด race condition โดยไม่ต้องรันซ้ำมาก แสดงว่า delay 50–500 ms ช่วยขยาย race window ได้ดี
3. **Sync restores correctness at scale** — 3 workers + mutex ให้ผลด้าน correctness เทียบเท่า sequential แต่ผู้ชนะไม่ deterministic
4. **Seat map ไม่เพียงพอสำหรับตรวจ race** — Experiment 2 seat map บันทึก 1 owner แต่ 3 clients ได้ SUCCESS ต้องอ่าน client output + seat-conflicts.txt ร่วมด้วย

---

*หลักฐานเพิ่มเติม: `docs/evidence/2026-10-01/experiment-transcripts.txt` | สภาพแวดล้อม: `docs/evidence/2026-10-01/environment.json`*
