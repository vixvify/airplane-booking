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
| Started (UTC) | 01 OCT 2026 14:39:06 |


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

| Run | Started (UTC) | Success | Rejected | Transport Fail | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 1 | 01 OCT 2026 14:39:07 | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 2 | 01 OCT 2026 14:39:08 | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 3 | 01 OCT 2026 14:39:10 | 1/5 | 4/5 | 0 | Client-2 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 2 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 3 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |

### หลักฐาน log (Experiment 1)

**Run 1** — `experiment1-sync-w1-verbose-c5-r1`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] waiting for Seat 10
[SEQ 3] [Worker-1] [Client-2] locked Seat 10
[SEQ 4] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 5] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 6] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 7] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 8] [Worker-1] [Client-3] received RESERVE 10
[SEQ 9] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-3] locked Seat 10
[SEQ 11] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 12] [Worker-1] [Client-3] leaving critical section: RESERVE transaction cancelled
[SEQ 13] [Worker-1] [Client-4] received RESERVE 10
[SEQ 14] [Worker-1] [Client-4] waiting for Seat 10
[SEQ 15] [Worker-1] [Client-4] locked Seat 10
[SEQ 16] [Worker-1] [Client-4] entering critical section for RESERVE
[SEQ 17] [Worker-1] [Client-4] leaving critical section: RESERVE transaction cancelled
[SEQ 18] [Worker-1] [Client-5] received RESERVE 10
[SEQ 19] [Worker-1] [Client-5] waiting for Seat 10
[SEQ 20] [Worker-1] [Client-5] locked Seat 10
[SEQ 21] [Worker-1] [Client-5] entering critical section for RESERVE
[SEQ 22] [Worker-1] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 23] [Worker-1] [Client-1] received RESERVE 10
[SEQ 24] [Worker-1] [Client-1] waiting for Seat 10
[SEQ 25] [Worker-1] [Client-1] locked Seat 10
[SEQ 26] [Worker-1] [Client-1] entering critical section for RESERVE
[SEQ 27] [Worker-1] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 28] [Worker-1] [Client-2] received QUIT
[SEQ 29] [Worker-1] [Client-3] received QUIT
[SEQ 30] [Worker-1] [Client-5] received QUIT
[SEQ 31] [Worker-1] [Client-4] received QUIT
[SEQ 32] [Worker-1] [Client-1] received QUIT
```

**Run 2** — `experiment1-sync-w1-verbose-c5-r2`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] waiting for Seat 10
[SEQ 3] [Worker-1] [Client-2] locked Seat 10
[SEQ 4] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 5] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 6] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 7] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 8] [Worker-1] [Client-1] received RESERVE 10
[SEQ 9] [Worker-1] [Client-1] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-1] locked Seat 10
[SEQ 11] [Worker-1] [Client-1] entering critical section for RESERVE
[SEQ 12] [Worker-1] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 13] [Worker-1] [Client-3] received RESERVE 10
[SEQ 14] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 15] [Worker-1] [Client-3] locked Seat 10
[SEQ 16] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 17] [Worker-1] [Client-3] leaving critical section: RESERVE transaction cancelled
[SEQ 18] [Worker-1] [Client-4] received RESERVE 10
[SEQ 19] [Worker-1] [Client-4] waiting for Seat 10
[SEQ 20] [Worker-1] [Client-4] locked Seat 10
[SEQ 21] [Worker-1] [Client-4] entering critical section for RESERVE
[SEQ 22] [Worker-1] [Client-4] leaving critical section: RESERVE transaction cancelled
[SEQ 23] [Worker-1] [Client-5] received RESERVE 10
[SEQ 24] [Worker-1] [Client-5] waiting for Seat 10
[SEQ 25] [Worker-1] [Client-5] locked Seat 10
[SEQ 26] [Worker-1] [Client-5] entering critical section for RESERVE
[SEQ 27] [Worker-1] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 28] [Worker-1] [Client-2] received QUIT
[SEQ 29] [Worker-1] [Client-3] received QUIT
[SEQ 30] [Worker-1] [Client-1] received QUIT
[SEQ 31] [Worker-1] [Client-4] received QUIT
[SEQ 32] [Worker-1] [Client-5] received QUIT
```

**Run 3** — `experiment1-sync-w1-verbose-c5-r3`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] waiting for Seat 10
[SEQ 3] [Worker-1] [Client-2] locked Seat 10
[SEQ 4] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 5] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 6] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 7] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 8] [Worker-1] [Client-1] received RESERVE 10
[SEQ 9] [Worker-1] [Client-1] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-1] locked Seat 10
[SEQ 11] [Worker-1] [Client-1] entering critical section for RESERVE
[SEQ 12] [Worker-1] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 13] [Worker-1] [Client-3] received RESERVE 10
[SEQ 14] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 15] [Worker-1] [Client-3] locked Seat 10
[SEQ 16] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 17] [Worker-1] [Client-3] leaving critical section: RESERVE transaction cancelled
[SEQ 18] [Worker-1] [Client-4] received RESERVE 10
[SEQ 19] [Worker-1] [Client-4] waiting for Seat 10
[SEQ 20] [Worker-1] [Client-4] locked Seat 10
[SEQ 21] [Worker-1] [Client-4] entering critical section for RESERVE
[SEQ 22] [Worker-1] [Client-4] leaving critical section: RESERVE transaction cancelled
[SEQ 23] [Worker-1] [Client-5] received RESERVE 10
[SEQ 24] [Worker-1] [Client-5] waiting for Seat 10
[SEQ 25] [Worker-1] [Client-5] locked Seat 10
[SEQ 26] [Worker-1] [Client-5] entering critical section for RESERVE
[SEQ 27] [Worker-1] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 28] [Worker-1] [Client-2] received QUIT
[SEQ 29] [Worker-1] [Client-1] received QUIT
[SEQ 30] [Worker-1] [Client-3] received QUIT
[SEQ 31] [Worker-1] [Client-4] received QUIT
[SEQ 32] [Worker-1] [Client-5] received QUIT
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

| Run | Started (UTC) | Success (RACE) | Rejected | Transport Fail | Clients ที่ได้ SUCCESS | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 01 OCT 2026 14:39:11 | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-1 | FAILED — 1 conflict |
| 2 | 01 OCT 2026 14:39:13 | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-2 | FAILED — 1 conflict |
| 3 | 01 OCT 2026 14:39:14 | 3/5 | 2/5 | 0 | Client-1, Client-2, Client-3 | Client-1 | FAILED — 1 conflict |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |
| 2 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |
| 3 | **SUCCESS — RACE** | **SUCCESS — RACE** | **SUCCESS — RACE** | REJECTED | REJECTED |

### หลักฐาน log (Experiment 2)

**Run 1** — `experiment2-nosync-w3-verbose-c5-r1`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] checking Seat 10
[SEQ 3] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 4] [Worker-2] [Client-1] received RESERVE 10
[SEQ 5] [Worker-2] [Client-1] checking Seat 10
[SEQ 6] [Worker-2] [Client-1] Seat 10 is AVAILABLE
[SEQ 7] [Worker-3] [Client-3] received RESERVE 10
[SEQ 8] [Worker-3] [Client-3] checking Seat 10
[SEQ 9] [Worker-3] [Client-3] Seat 10 is AVAILABLE
[SEQ 10] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 11] [Worker-1] [Client-4] received RESERVE 10
[SEQ 12] [Worker-1] [Client-4] checking Seat 10
[SEQ 13] [Worker-1] [Client-4] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 14] [Worker-1] [Client-5] received RESERVE 10
[SEQ 15] [Worker-1] [Client-5] checking Seat 10
[SEQ 16] [Worker-1] [Client-5] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 17] [Worker-1] [Client-2] received QUIT
[SEQ 18] [Worker-1] [Client-4] received QUIT
[SEQ 19] [Worker-1] [Client-5] received QUIT
[SEQ 20] [Worker-3] [Client-3] Seat 10 reserved
[SEQ 21] [Worker-1] [Client-3] received QUIT
[SEQ 22] [Worker-2] [Client-1] Seat 10 reserved
[SEQ 23] [Worker-3] [Client-1] received QUIT
```

> **อ่าน seat-conflicts.txt:** `10|Client-1, Client-2, Client-3|Client-1`  
> หมายถึง Seat 10 มี 3 clients ได้รับ SUCCESS (Client-1, 2, 3) แต่ seat map บันทึก Client-1 เป็น final owner

**Run 2** — `experiment2-nosync-w3-verbose-c5-r2`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] checking Seat 10
[SEQ 3] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 4] [Worker-2] [Client-3] received RESERVE 10
[SEQ 5] [Worker-2] [Client-3] checking Seat 10
[SEQ 6] [Worker-2] [Client-3] Seat 10 is AVAILABLE
[SEQ 7] [Worker-3] [Client-1] received RESERVE 10
[SEQ 8] [Worker-3] [Client-1] checking Seat 10
[SEQ 9] [Worker-3] [Client-1] Seat 10 is AVAILABLE
[SEQ 10] [Worker-2] [Client-3] Seat 10 reserved
[SEQ 11] [Worker-2] [Client-4] received RESERVE 10
[SEQ 12] [Worker-2] [Client-4] checking Seat 10
[SEQ 13] [Worker-2] [Client-4] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 14] [Worker-2] [Client-5] received RESERVE 10
[SEQ 15] [Worker-2] [Client-5] checking Seat 10
[SEQ 16] [Worker-2] [Client-5] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 17] [Worker-2] [Client-3] received QUIT
[SEQ 18] [Worker-2] [Client-4] received QUIT
[SEQ 19] [Worker-2] [Client-5] received QUIT
[SEQ 20] [Worker-3] [Client-1] Seat 10 reserved
[SEQ 21] [Worker-2] [Client-1] received QUIT
[SEQ 22] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 23] [Worker-3] [Client-2] received QUIT
```

**Run 3** — `experiment2-nosync-w3-verbose-c5-r3`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-3] [Client-1] received RESERVE 10
[SEQ 3] [Worker-3] [Client-1] checking Seat 10
[SEQ 4] [Worker-3] [Client-1] Seat 10 is AVAILABLE
[SEQ 5] [Worker-1] [Client-2] checking Seat 10
[SEQ 6] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 7] [Worker-2] [Client-3] received RESERVE 10
[SEQ 8] [Worker-2] [Client-3] checking Seat 10
[SEQ 9] [Worker-2] [Client-3] Seat 10 is AVAILABLE
[SEQ 10] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 11] [Worker-1] [Client-4] received RESERVE 10
[SEQ 12] [Worker-1] [Client-4] checking Seat 10
[SEQ 13] [Worker-1] [Client-4] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 14] [Worker-1] [Client-5] received RESERVE 10
[SEQ 15] [Worker-1] [Client-5] checking Seat 10
[SEQ 16] [Worker-1] [Client-5] RESERVE transaction cancelled: Seat 10 is already reserved
[SEQ 17] [Worker-1] [Client-4] received QUIT
[SEQ 18] [Worker-1] [Client-2] received QUIT
[SEQ 19] [Worker-1] [Client-5] received QUIT
[SEQ 20] [Worker-2] [Client-3] Seat 10 reserved
[SEQ 21] [Worker-1] [Client-3] received QUIT
[SEQ 22] [Worker-3] [Client-1] Seat 10 reserved
[SEQ 23] [Worker-2] [Client-1] received QUIT
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

| Run | Started (UTC) | Success | Rejected | Transport Fail | Final owner | Consistency |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 1 | 01 OCT 2026 14:39:16 | 1/5 | 4/5 | 0 | Client-2 | PASSED |
| 2 | 01 OCT 2026 14:39:18 | 1/5 | 4/5 | 0 | Client-4 | PASSED |
| 3 | 01 OCT 2026 14:39:19 | 1/5 | 4/5 | 0 | Client-3 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | REJECTED | **SUCCESS** | REJECTED | REJECTED | REJECTED |
| 2 | REJECTED | REJECTED | REJECTED | **SUCCESS** | REJECTED |
| 3 | REJECTED | REJECTED | **SUCCESS** | REJECTED | REJECTED |

### หลักฐาน log (Experiment 3)

**Run 1** — `experiment3-sync-w3-verbose-c5-r1`

Server log:

```text
[SEQ 1] [Worker-1] [Client-2] received RESERVE 10
[SEQ 2] [Worker-1] [Client-2] waiting for Seat 10
[SEQ 3] [Worker-1] [Client-2] locked Seat 10
[SEQ 4] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 5] [Worker-1] [Client-2] Seat 10 is AVAILABLE
[SEQ 6] [Worker-2] [Client-4] received RESERVE 10
[SEQ 7] [Worker-3] [Client-1] received RESERVE 10
[SEQ 8] [Worker-2] [Client-4] waiting for Seat 10
[SEQ 9] [Worker-3] [Client-1] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-2] Seat 10 reserved
[SEQ 11] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 12] [Worker-2] [Client-4] locked Seat 10
[SEQ 13] [Worker-2] [Client-4] entering critical section for RESERVE
[SEQ 14] [Worker-2] [Client-4] leaving critical section: RESERVE transaction cancelled
[SEQ 15] [Worker-1] [Client-3] received RESERVE 10
[SEQ 16] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 17] [Worker-3] [Client-1] locked Seat 10
[SEQ 18] [Worker-3] [Client-1] entering critical section for RESERVE
[SEQ 19] [Worker-3] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 20] [Worker-2] [Client-5] received RESERVE 10
[SEQ 21] [Worker-2] [Client-5] waiting for Seat 10
[SEQ 22] [Worker-1] [Client-3] locked Seat 10
[SEQ 23] [Worker-3] [Client-2] received QUIT
[SEQ 24] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 25] [Worker-1] [Client-3] leaving critical section: RESERVE transaction cancelled
[SEQ 26] [Worker-1] [Client-1] received QUIT
[SEQ 27] [Worker-2] [Client-5] locked Seat 10
[SEQ 28] [Worker-2] [Client-5] entering critical section for RESERVE
[SEQ 29] [Worker-2] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 30] [Worker-1] [Client-3] received QUIT
[SEQ 31] [Worker-3] [Client-4] received QUIT
[SEQ 32] [Worker-2] [Client-5] received QUIT
```

**Run 2** — `experiment3-sync-w3-verbose-c5-r2`

Server log:

```text
[SEQ 1] [Worker-1] [Client-4] received RESERVE 10
[SEQ 2] [Worker-2] [Client-5] received RESERVE 10
[SEQ 3] [Worker-1] [Client-4] waiting for Seat 10
[SEQ 4] [Worker-1] [Client-4] locked Seat 10
[SEQ 5] [Worker-1] [Client-4] entering critical section for RESERVE
[SEQ 6] [Worker-1] [Client-4] Seat 10 is AVAILABLE
[SEQ 7] [Worker-2] [Client-5] waiting for Seat 10
[SEQ 8] [Worker-3] [Client-2] received RESERVE 10
[SEQ 9] [Worker-3] [Client-2] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-4] Seat 10 reserved
[SEQ 11] [Worker-1] [Client-4] leaving critical section for RESERVE
[SEQ 12] [Worker-2] [Client-5] locked Seat 10
[SEQ 13] [Worker-2] [Client-5] entering critical section for RESERVE
[SEQ 14] [Worker-2] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 15] [Worker-1] [Client-3] received RESERVE 10
[SEQ 16] [Worker-3] [Client-2] locked Seat 10
[SEQ 17] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 18] [Worker-2] [Client-1] received RESERVE 10
[SEQ 19] [Worker-2] [Client-1] waiting for Seat 10
[SEQ 20] [Worker-3] [Client-2] entering critical section for RESERVE
[SEQ 21] [Worker-3] [Client-2] leaving critical section: RESERVE transaction cancelled
[SEQ 22] [Worker-3] [Client-4] received QUIT
[SEQ 23] [Worker-3] [Client-5] received QUIT
[SEQ 24] [Worker-1] [Client-3] locked Seat 10
[SEQ 25] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 26] [Worker-1] [Client-3] leaving critical section: RESERVE transaction cancelled
[SEQ 27] [Worker-2] [Client-1] locked Seat 10
[SEQ 28] [Worker-2] [Client-1] entering critical section for RESERVE
[SEQ 29] [Worker-2] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 30] [Worker-3] [Client-3] received QUIT
[SEQ 31] [Worker-1] [Client-2] received QUIT
[SEQ 32] [Worker-2] [Client-1] received QUIT
```

**Run 3** — `experiment3-sync-w3-verbose-c5-r3`

Server log:

```text
[SEQ 1] [Worker-1] [Client-3] received RESERVE 10
[SEQ 2] [Worker-1] [Client-3] waiting for Seat 10
[SEQ 3] [Worker-1] [Client-3] locked Seat 10
[SEQ 4] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 5] [Worker-1] [Client-3] Seat 10 is AVAILABLE
[SEQ 6] [Worker-2] [Client-2] received RESERVE 10
[SEQ 7] [Worker-2] [Client-2] waiting for Seat 10
[SEQ 8] [Worker-3] [Client-1] received RESERVE 10
[SEQ 9] [Worker-3] [Client-1] waiting for Seat 10
[SEQ 10] [Worker-1] [Client-3] Seat 10 reserved
[SEQ 11] [Worker-1] [Client-3] leaving critical section for RESERVE
[SEQ 12] [Worker-2] [Client-2] locked Seat 10
[SEQ 13] [Worker-2] [Client-2] entering critical section for RESERVE
[SEQ 14] [Worker-2] [Client-2] leaving critical section: RESERVE transaction cancelled
[SEQ 15] [Worker-1] [Client-4] received RESERVE 10
[SEQ 16] [Worker-1] [Client-4] waiting for Seat 10
[SEQ 17] [Worker-3] [Client-1] locked Seat 10
[SEQ 18] [Worker-3] [Client-1] entering critical section for RESERVE
[SEQ 19] [Worker-3] [Client-1] leaving critical section: RESERVE transaction cancelled
[SEQ 20] [Worker-2] [Client-5] received RESERVE 10
[SEQ 21] [Worker-2] [Client-5] waiting for Seat 10
[SEQ 22] [Worker-1] [Client-4] locked Seat 10
[SEQ 23] [Worker-1] [Client-4] entering critical section for RESERVE
[SEQ 24] [Worker-1] [Client-4] leaving critical section: RESERVE transaction cancelled
[SEQ 25] [Worker-3] [Client-3] received QUIT
[SEQ 26] [Worker-2] [Client-5] locked Seat 10
[SEQ 27] [Worker-1] [Client-2] received QUIT
[SEQ 28] [Worker-3] [Client-1] received QUIT
[SEQ 29] [Worker-2] [Client-5] entering critical section for RESERVE
[SEQ 30] [Worker-2] [Client-5] leaving critical section: RESERVE transaction cancelled
[SEQ 31] [Worker-2] [Client-4] received QUIT
[SEQ 32] [Worker-3] [Client-5] received QUIT
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

| Run | Started (UTC) | Reservations | Failed | Cancellations | Remaining | Consistency |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | 01 OCT 2026 14:39:21 | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 2 | 01 OCT 2026 14:39:24 | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 3 | 01 OCT 2026 14:39:27 | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |

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

Server log:

```text
[SEQ 1] [Worker-1] [Client-1] received LIST
[SEQ 2] [Worker-2] [Client-1] received QUIT
[SEQ 3] [Worker-3] [Client-1] received STATUS 1
[SEQ 4] [Worker-1] [Client-1] received QUIT
[SEQ 5] [Worker-2] [Client-1] received STATUS 2
[SEQ 6] [Worker-3] [Client-1] received QUIT
[SEQ 7] [Worker-1] [Client-1] received STATUS 3
[SEQ 8] [Worker-2] [Client-1] received QUIT
[SEQ 9] [Worker-3] [Client-1] received STATUS 4
[SEQ 10] [Worker-1] [Client-1] received QUIT
[SEQ 11] [Worker-2] [Client-1] received STATUS 5
[SEQ 12] [Worker-3] [Client-1] received QUIT
[SEQ 13] [Worker-1] [Client-1] received STATUS 6
[SEQ 14] [Worker-2] [Client-1] received QUIT
[SEQ 15] [Worker-3] [Client-1] received STATUS 7
[SEQ 16] [Worker-1] [Client-1] received QUIT
[SEQ 17] [Worker-2] [Client-1] received STATUS 8
[SEQ 18] [Worker-3] [Client-1] received QUIT
[SEQ 19] [Worker-1] [Client-1] received STATUS 9
[SEQ 20] [Worker-2] [Client-1] received QUIT
[SEQ 21] [Worker-3] [Client-1] received STATUS 10
[SEQ 22] [Worker-1] [Client-1] received QUIT
[SEQ 23] [Worker-2] [Client-2] received STATUS 3
[SEQ 24] [Worker-1] [Client-3] received RESERVE 5 6
[SEQ 25] [Worker-3] [Client-2] received RESERVE 3 4
[SEQ 26] [Worker-2] [Client-1] received LIST
[SEQ 27] [Worker-3] [Client-2] waiting for Seat 3
[SEQ 28] [Worker-3] [Client-2] locked Seat 3
[SEQ 29] [Worker-3] [Client-2] waiting for Seat 4
[SEQ 30] [Worker-3] [Client-2] locked Seat 4
[SEQ 31] [Worker-3] [Client-2] entering critical section for RESERVE
[SEQ 32] [Worker-3] [Client-2] Seat 3 is AVAILABLE
[SEQ 33] [Worker-1] [Client-3] waiting for Seat 5
[SEQ 34] [Worker-1] [Client-3] locked Seat 5
[SEQ 35] [Worker-1] [Client-3] waiting for Seat 6
[SEQ 36] [Worker-1] [Client-3] locked Seat 6
[SEQ 37] [Worker-1] [Client-3] entering critical section for RESERVE
[SEQ 38] [Worker-1] [Client-3] Seat 5 is AVAILABLE
[SEQ 39] [Worker-2] [Client-4] received RESERVE 7 8
[SEQ 40] [Worker-2] [Client-4] waiting for Seat 7
[SEQ 41] [Worker-2] [Client-4] locked Seat 7
[SEQ 42] [Worker-2] [Client-4] waiting for Seat 8
[SEQ 43] [Worker-2] [Client-4] locked Seat 8
[SEQ 44] [Worker-2] [Client-4] entering critical section for RESERVE
[SEQ 45] [Worker-2] [Client-4] Seat 7 is AVAILABLE
[SEQ 46] [Worker-1] [Client-3] Seat 5 reserved
[SEQ 47] [Worker-1] [Client-3] Seat 6 is AVAILABLE
[SEQ 48] [Worker-2] [Client-4] Seat 7 reserved
[SEQ 49] [Worker-2] [Client-4] Seat 8 is AVAILABLE
[SEQ 50] [Worker-1] [Client-3] Seat 6 reserved
[SEQ 51] [Worker-1] [Client-3] leaving critical section for RESERVE
[SEQ 52] [Worker-1] [Client-1] received RESERVE 1 2
[SEQ 53] [Worker-1] [Client-1] waiting for Seat 1
[SEQ 54] [Worker-1] [Client-1] locked Seat 1
[SEQ 55] [Worker-1] [Client-1] waiting for Seat 2
[SEQ 56] [Worker-1] [Client-1] locked Seat 2
[SEQ 57] [Worker-1] [Client-1] entering critical section for RESERVE
[SEQ 58] [Worker-1] [Client-1] Seat 1 is AVAILABLE
[SEQ 59] [Worker-3] [Client-2] Seat 3 reserved
[SEQ 60] [Worker-3] [Client-2] Seat 4 is AVAILABLE
[SEQ 61] [Worker-1] [Client-1] Seat 1 reserved
[SEQ 62] [Worker-1] [Client-1] Seat 2 is AVAILABLE
[SEQ 63] [Worker-3] [Client-2] Seat 4 reserved
[SEQ 64] [Worker-3] [Client-2] leaving critical section for RESERVE
[SEQ 65] [Worker-3] [Client-5] received LIST
[SEQ 66] [Worker-2] [Client-4] Seat 8 reserved
[SEQ 67] [Worker-2] [Client-4] leaving critical section for RESERVE
[SEQ 68] [Worker-2] [Client-3] received LIST
[SEQ 69] [Worker-1] [Client-1] Seat 2 reserved
[SEQ 70] [Worker-1] [Client-1] leaving critical section for RESERVE
[SEQ 71] [Worker-1] [Client-2] received CANCEL 4
[SEQ 72] [Worker-1] [Client-2] waiting for Seat 4
[SEQ 73] [Worker-3] [Client-4] received STATUS 8
[SEQ 74] [Worker-1] [Client-2] locked Seat 4
[SEQ 75] [Worker-1] [Client-2] entering critical section for CANCEL
[SEQ 76] [Worker-1] [Client-2] Seat 4 cancelled
[SEQ 77] [Worker-1] [Client-2] leaving critical section for CANCEL
[SEQ 78] [Worker-3] [Client-1] received STATUS 1
[SEQ 79] [Worker-1] [Client-4] received CANCEL 8
[SEQ 80] [Worker-1] [Client-4] waiting for Seat 8
[SEQ 81] [Worker-1] [Client-4] locked Seat 8
[SEQ 82] [Worker-1] [Client-4] entering critical section for CANCEL
[SEQ 83] [Worker-1] [Client-4] Seat 8 cancelled
[SEQ 84] [Worker-1] [Client-4] leaving critical section for CANCEL
[SEQ 85] [Worker-1] [Client-3] received CANCEL 5
[SEQ 86] [Worker-1] [Client-3] waiting for Seat 5
[SEQ 87] [Worker-1] [Client-3] locked Seat 5
[SEQ 88] [Worker-1] [Client-3] entering critical section for CANCEL
[SEQ 89] [Worker-1] [Client-3] Seat 5 cancelled
[SEQ 90] [Worker-1] [Client-3] leaving critical section for CANCEL
[SEQ 91] [Worker-1] [Client-1] received CANCEL 1
[SEQ 92] [Worker-1] [Client-1] waiting for Seat 1
[SEQ 93] [Worker-1] [Client-1] locked Seat 1
[SEQ 94] [Worker-1] [Client-1] entering critical section for CANCEL
[SEQ 95] [Worker-1] [Client-1] Seat 1 cancelled
[SEQ 96] [Worker-1] [Client-1] leaving critical section for CANCEL
[SEQ 97] [Worker-1] [Client-4] received LIST
[SEQ 98] [Worker-3] [Client-2] received STATUS 3
[SEQ 99] [Worker-3] [Client-1] received STATUS 2
[SEQ 100] [Worker-1] [Client-3] received STATUS 6
[SEQ 101] [Worker-3] [Client-4] received STATUS 7
[SEQ 102] [Worker-2] [Client-5] received RESERVE 9 10
[SEQ 103] [Worker-2] [Client-5] waiting for Seat 9
[SEQ 104] [Worker-2] [Client-5] locked Seat 9
[SEQ 105] [Worker-2] [Client-5] waiting for Seat 10
[SEQ 106] [Worker-1] [Client-1] received QUIT
[SEQ 107] [Worker-2] [Client-5] locked Seat 10
[SEQ 108] [Worker-2] [Client-5] entering critical section for RESERVE
[SEQ 109] [Worker-2] [Client-5] Seat 9 is AVAILABLE
[SEQ 110] [Worker-3] [Client-2] received LIST
[SEQ 111] [Worker-1] [Client-3] received QUIT
[SEQ 112] [Worker-1] [Client-4] received QUIT
[SEQ 113] [Worker-2] [Client-5] Seat 9 reserved
[SEQ 114] [Worker-2] [Client-5] Seat 10 is AVAILABLE
[SEQ 115] [Worker-2] [Client-5] Seat 10 reserved
[SEQ 116] [Worker-2] [Client-5] leaving critical section for RESERVE
[SEQ 117] [Worker-1] [Client-5] received CANCEL 9
[SEQ 118] [Worker-1] [Client-5] waiting for Seat 9
[SEQ 119] [Worker-1] [Client-5] locked Seat 9
[SEQ 120] [Worker-1] [Client-5] entering critical section for CANCEL
[SEQ 121] [Worker-1] [Client-5] Seat 9 cancelled
[SEQ 122] [Worker-1] [Client-5] leaving critical section for CANCEL
[SEQ 123] [Worker-2] [Client-2] received QUIT
[SEQ 124] [Worker-3] [Client-5] received STATUS 10
[SEQ 125] [Worker-1] [Client-5] received QUIT
```

**Run 2** — `demo1-sync-w3-verbose-c5-r2`

Server log:

```text
[SEQ 1] [Worker-1] [Client-1] received LIST
[SEQ 2] [Worker-2] [Client-1] received QUIT
[SEQ 3] [Worker-3] [Client-1] received STATUS 1
[SEQ 4] [Worker-1] [Client-1] received QUIT
[SEQ 5] [Worker-2] [Client-1] received STATUS 2
[SEQ 6] [Worker-3] [Client-1] received QUIT
[SEQ 7] [Worker-1] [Client-1] received STATUS 3
[SEQ 8] [Worker-2] [Client-1] received QUIT
[SEQ 9] [Worker-3] [Client-1] received STATUS 4
[SEQ 10] [Worker-1] [Client-1] received QUIT
[SEQ 11] [Worker-2] [Client-1] received STATUS 5
[SEQ 12] [Worker-3] [Client-1] received QUIT
[SEQ 13] [Worker-1] [Client-1] received STATUS 6
[SEQ 14] [Worker-2] [Client-1] received QUIT
[SEQ 15] [Worker-3] [Client-1] received STATUS 7
[SEQ 16] [Worker-1] [Client-1] received QUIT
[SEQ 17] [Worker-2] [Client-1] received STATUS 8
[SEQ 18] [Worker-3] [Client-1] received QUIT
[SEQ 19] [Worker-1] [Client-1] received STATUS 9
[SEQ 20] [Worker-2] [Client-1] received QUIT
[SEQ 21] [Worker-3] [Client-1] received STATUS 10
[SEQ 22] [Worker-1] [Client-1] received QUIT
[SEQ 23] [Worker-2] [Client-4] received RESERVE 7 8
[SEQ 24] [Worker-2] [Client-4] waiting for Seat 7
[SEQ 25] [Worker-2] [Client-4] locked Seat 7
[SEQ 26] [Worker-2] [Client-4] waiting for Seat 8
[SEQ 27] [Worker-2] [Client-4] locked Seat 8
[SEQ 28] [Worker-2] [Client-4] entering critical section for RESERVE
[SEQ 29] [Worker-2] [Client-4] Seat 7 is AVAILABLE
[SEQ 30] [Worker-3] [Client-2] received STATUS 3
[SEQ 31] [Worker-1] [Client-2] received RESERVE 3 4
[SEQ 32] [Worker-1] [Client-2] waiting for Seat 3
[SEQ 33] [Worker-1] [Client-2] locked Seat 3
[SEQ 34] [Worker-1] [Client-2] waiting for Seat 4
[SEQ 35] [Worker-1] [Client-2] locked Seat 4
[SEQ 36] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 37] [Worker-1] [Client-2] Seat 3 is AVAILABLE
[SEQ 38] [Worker-3] [Client-1] received LIST
[SEQ 39] [Worker-1] [Client-2] Seat 3 reserved
[SEQ 40] [Worker-1] [Client-2] Seat 4 is AVAILABLE
[SEQ 41] [Worker-2] [Client-4] Seat 7 reserved
[SEQ 42] [Worker-2] [Client-4] Seat 8 is AVAILABLE
[SEQ 43] [Worker-1] [Client-2] Seat 4 reserved
[SEQ 44] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 45] [Worker-1] [Client-5] received LIST
[SEQ 46] [Worker-2] [Client-4] Seat 8 reserved
[SEQ 47] [Worker-2] [Client-4] leaving critical section for RESERVE
[SEQ 48] [Worker-2] [Client-3] received RESERVE 5 6
[SEQ 49] [Worker-2] [Client-3] waiting for Seat 5
[SEQ 50] [Worker-3] [Client-2] received CANCEL 4
[SEQ 51] [Worker-2] [Client-3] locked Seat 5
[SEQ 52] [Worker-2] [Client-3] waiting for Seat 6
[SEQ 53] [Worker-1] [Client-4] received STATUS 8
[SEQ 54] [Worker-3] [Client-2] waiting for Seat 4
[SEQ 55] [Worker-3] [Client-2] locked Seat 4
[SEQ 56] [Worker-3] [Client-2] entering critical section for CANCEL
[SEQ 57] [Worker-2] [Client-3] locked Seat 6
[SEQ 58] [Worker-2] [Client-3] entering critical section for RESERVE
[SEQ 59] [Worker-2] [Client-3] Seat 5 is AVAILABLE
[SEQ 60] [Worker-3] [Client-2] Seat 4 cancelled
[SEQ 61] [Worker-3] [Client-2] leaving critical section for CANCEL
[SEQ 62] [Worker-3] [Client-5] received RESERVE 9 10
[SEQ 63] [Worker-1] [Client-1] received RESERVE 1 2
[SEQ 64] [Worker-1] [Client-1] waiting for Seat 1
[SEQ 65] [Worker-1] [Client-1] locked Seat 1
[SEQ 66] [Worker-1] [Client-1] waiting for Seat 2
[SEQ 67] [Worker-1] [Client-1] locked Seat 2
[SEQ 68] [Worker-1] [Client-1] entering critical section for RESERVE
[SEQ 69] [Worker-1] [Client-1] Seat 1 is AVAILABLE
[SEQ 70] [Worker-3] [Client-5] waiting for Seat 9
[SEQ 71] [Worker-3] [Client-5] locked Seat 9
[SEQ 72] [Worker-3] [Client-5] waiting for Seat 10
[SEQ 73] [Worker-3] [Client-5] locked Seat 10
[SEQ 74] [Worker-3] [Client-5] entering critical section for RESERVE
[SEQ 75] [Worker-3] [Client-5] Seat 9 is AVAILABLE
[SEQ 76] [Worker-2] [Client-3] Seat 5 reserved
[SEQ 77] [Worker-2] [Client-3] Seat 6 is AVAILABLE
[SEQ 78] [Worker-1] [Client-1] Seat 1 reserved
[SEQ 79] [Worker-1] [Client-1] Seat 2 is AVAILABLE
[SEQ 80] [Worker-3] [Client-5] Seat 9 reserved
[SEQ 81] [Worker-3] [Client-5] Seat 10 is AVAILABLE
[SEQ 82] [Worker-1] [Client-1] Seat 2 reserved
[SEQ 83] [Worker-1] [Client-1] leaving critical section for RESERVE
[SEQ 84] [Worker-1] [Client-4] received CANCEL 8
[SEQ 85] [Worker-1] [Client-4] waiting for Seat 8
[SEQ 86] [Worker-1] [Client-4] locked Seat 8
[SEQ 87] [Worker-1] [Client-4] entering critical section for CANCEL
[SEQ 88] [Worker-1] [Client-4] Seat 8 cancelled
[SEQ 89] [Worker-1] [Client-4] leaving critical section for CANCEL
[SEQ 90] [Worker-1] [Client-2] received STATUS 3
[SEQ 91] [Worker-1] [Client-1] received STATUS 1
[SEQ 92] [Worker-1] [Client-2] received LIST
[SEQ 93] [Worker-2] [Client-3] Seat 6 reserved
[SEQ 94] [Worker-2] [Client-3] leaving critical section for RESERVE
[SEQ 95] [Worker-2] [Client-4] received LIST
[SEQ 96] [Worker-3] [Client-5] Seat 10 reserved
[SEQ 97] [Worker-3] [Client-5] leaving critical section for RESERVE
[SEQ 98] [Worker-3] [Client-1] received CANCEL 1
[SEQ 99] [Worker-3] [Client-1] waiting for Seat 1
[SEQ 100] [Worker-3] [Client-1] locked Seat 1
[SEQ 101] [Worker-3] [Client-1] entering critical section for CANCEL
[SEQ 102] [Worker-3] [Client-1] Seat 1 cancelled
[SEQ 103] [Worker-3] [Client-1] leaving critical section for CANCEL
[SEQ 104] [Worker-2] [Client-2] received QUIT
[SEQ 105] [Worker-3] [Client-5] received CANCEL 9
[SEQ 106] [Worker-3] [Client-5] waiting for Seat 9
[SEQ 107] [Worker-3] [Client-5] locked Seat 9
[SEQ 108] [Worker-3] [Client-5] entering critical section for CANCEL
[SEQ 109] [Worker-3] [Client-5] Seat 9 cancelled
[SEQ 110] [Worker-3] [Client-5] leaving critical section for CANCEL
[SEQ 111] [Worker-1] [Client-3] received LIST
[SEQ 112] [Worker-2] [Client-4] received STATUS 7
[SEQ 113] [Worker-3] [Client-1] received STATUS 2
[SEQ 114] [Worker-1] [Client-3] received CANCEL 5
[SEQ 115] [Worker-1] [Client-3] waiting for Seat 5
[SEQ 116] [Worker-1] [Client-3] locked Seat 5
[SEQ 117] [Worker-1] [Client-3] entering critical section for CANCEL
[SEQ 118] [Worker-1] [Client-3] Seat 5 cancelled
[SEQ 119] [Worker-1] [Client-3] leaving critical section for CANCEL
[SEQ 120] [Worker-3] [Client-5] received STATUS 10
[SEQ 121] [Worker-3] [Client-4] received QUIT
[SEQ 122] [Worker-3] [Client-3] received STATUS 6
[SEQ 123] [Worker-3] [Client-5] received QUIT
[SEQ 124] [Worker-2] [Client-1] received QUIT
[SEQ 125] [Worker-3] [Client-3] received QUIT
```

**Run 3** — `demo1-sync-w3-verbose-c5-r3`

Server log:

```text
[SEQ 1] [Worker-1] [Client-1] received LIST
[SEQ 2] [Worker-2] [Client-1] received QUIT
[SEQ 3] [Worker-3] [Client-1] received STATUS 1
[SEQ 4] [Worker-1] [Client-1] received QUIT
[SEQ 5] [Worker-2] [Client-1] received STATUS 2
[SEQ 6] [Worker-3] [Client-1] received QUIT
[SEQ 7] [Worker-1] [Client-1] received STATUS 3
[SEQ 8] [Worker-2] [Client-1] received QUIT
[SEQ 9] [Worker-3] [Client-1] received STATUS 4
[SEQ 10] [Worker-1] [Client-1] received QUIT
[SEQ 11] [Worker-2] [Client-1] received STATUS 5
[SEQ 12] [Worker-3] [Client-1] received QUIT
[SEQ 13] [Worker-1] [Client-1] received STATUS 6
[SEQ 14] [Worker-2] [Client-1] received QUIT
[SEQ 15] [Worker-3] [Client-1] received STATUS 7
[SEQ 16] [Worker-1] [Client-1] received QUIT
[SEQ 17] [Worker-2] [Client-1] received STATUS 8
[SEQ 18] [Worker-3] [Client-1] received QUIT
[SEQ 19] [Worker-1] [Client-1] received STATUS 9
[SEQ 20] [Worker-2] [Client-1] received QUIT
[SEQ 21] [Worker-3] [Client-1] received STATUS 10
[SEQ 22] [Worker-1] [Client-1] received QUIT
[SEQ 23] [Worker-2] [Client-3] received RESERVE 5 6
[SEQ 24] [Worker-2] [Client-3] waiting for Seat 5
[SEQ 25] [Worker-2] [Client-3] locked Seat 5
[SEQ 26] [Worker-2] [Client-3] waiting for Seat 6
[SEQ 27] [Worker-2] [Client-3] locked Seat 6
[SEQ 28] [Worker-2] [Client-3] entering critical section for RESERVE
[SEQ 29] [Worker-2] [Client-3] Seat 5 is AVAILABLE
[SEQ 30] [Worker-1] [Client-1] received LIST
[SEQ 31] [Worker-3] [Client-4] received RESERVE 7 8
[SEQ 32] [Worker-3] [Client-4] waiting for Seat 7
[SEQ 33] [Worker-3] [Client-4] locked Seat 7
[SEQ 34] [Worker-3] [Client-4] waiting for Seat 8
[SEQ 35] [Worker-3] [Client-4] locked Seat 8
[SEQ 36] [Worker-3] [Client-4] entering critical section for RESERVE
[SEQ 37] [Worker-3] [Client-4] Seat 7 is AVAILABLE
[SEQ 38] [Worker-2] [Client-3] Seat 5 reserved
[SEQ 39] [Worker-2] [Client-3] Seat 6 is AVAILABLE
[SEQ 40] [Worker-3] [Client-4] Seat 7 reserved
[SEQ 41] [Worker-3] [Client-4] Seat 8 is AVAILABLE
[SEQ 42] [Worker-3] [Client-4] Seat 8 reserved
[SEQ 43] [Worker-3] [Client-4] leaving critical section for RESERVE
[SEQ 44] [Worker-3] [Client-5] received LIST
[SEQ 45] [Worker-2] [Client-3] Seat 6 reserved
[SEQ 46] [Worker-2] [Client-3] leaving critical section for RESERVE
[SEQ 47] [Worker-2] [Client-2] received STATUS 3
[SEQ 48] [Worker-1] [Client-4] received STATUS 8
[SEQ 49] [Worker-2] [Client-3] received LIST
[SEQ 50] [Worker-1] [Client-2] received RESERVE 3 4
[SEQ 51] [Worker-1] [Client-2] waiting for Seat 3
[SEQ 52] [Worker-1] [Client-2] locked Seat 3
[SEQ 53] [Worker-1] [Client-2] waiting for Seat 4
[SEQ 54] [Worker-1] [Client-2] locked Seat 4
[SEQ 55] [Worker-1] [Client-2] entering critical section for RESERVE
[SEQ 56] [Worker-1] [Client-2] Seat 3 is AVAILABLE
[SEQ 57] [Worker-3] [Client-5] received RESERVE 9 10
[SEQ 58] [Worker-3] [Client-5] waiting for Seat 9
[SEQ 59] [Worker-3] [Client-5] locked Seat 9
[SEQ 60] [Worker-3] [Client-5] waiting for Seat 10
[SEQ 61] [Worker-3] [Client-5] locked Seat 10
[SEQ 62] [Worker-3] [Client-5] entering critical section for RESERVE
[SEQ 63] [Worker-3] [Client-5] Seat 9 is AVAILABLE
[SEQ 64] [Worker-2] [Client-1] received RESERVE 1 2
[SEQ 65] [Worker-2] [Client-1] waiting for Seat 1
[SEQ 66] [Worker-2] [Client-1] locked Seat 1
[SEQ 67] [Worker-2] [Client-1] waiting for Seat 2
[SEQ 68] [Worker-2] [Client-1] locked Seat 2
[SEQ 69] [Worker-2] [Client-1] entering critical section for RESERVE
[SEQ 70] [Worker-2] [Client-1] Seat 1 is AVAILABLE
[SEQ 71] [Worker-3] [Client-5] Seat 9 reserved
[SEQ 72] [Worker-3] [Client-5] Seat 10 is AVAILABLE
[SEQ 73] [Worker-1] [Client-2] Seat 3 reserved
[SEQ 74] [Worker-1] [Client-2] Seat 4 is AVAILABLE
[SEQ 75] [Worker-3] [Client-5] Seat 10 reserved
[SEQ 76] [Worker-3] [Client-5] leaving critical section for RESERVE
[SEQ 77] [Worker-3] [Client-4] received CANCEL 8
[SEQ 78] [Worker-3] [Client-4] waiting for Seat 8
[SEQ 79] [Worker-3] [Client-4] locked Seat 8
[SEQ 80] [Worker-3] [Client-4] entering critical section for CANCEL
[SEQ 81] [Worker-3] [Client-4] Seat 8 cancelled
[SEQ 82] [Worker-3] [Client-4] leaving critical section for CANCEL
[SEQ 83] [Worker-3] [Client-3] received CANCEL 5
[SEQ 84] [Worker-3] [Client-3] waiting for Seat 5
[SEQ 85] [Worker-3] [Client-3] locked Seat 5
[SEQ 86] [Worker-3] [Client-3] entering critical section for CANCEL
[SEQ 87] [Worker-3] [Client-3] Seat 5 cancelled
[SEQ 88] [Worker-3] [Client-3] leaving critical section for CANCEL
[SEQ 89] [Worker-3] [Client-5] received CANCEL 9
[SEQ 90] [Worker-3] [Client-5] waiting for Seat 9
[SEQ 91] [Worker-3] [Client-5] locked Seat 9
[SEQ 92] [Worker-3] [Client-5] entering critical section for CANCEL
[SEQ 93] [Worker-3] [Client-5] Seat 9 cancelled
[SEQ 94] [Worker-3] [Client-5] leaving critical section for CANCEL
[SEQ 95] [Worker-3] [Client-4] received LIST
[SEQ 96] [Worker-2] [Client-1] Seat 1 reserved
[SEQ 97] [Worker-2] [Client-1] Seat 2 is AVAILABLE
[SEQ 98] [Worker-2] [Client-1] Seat 2 reserved
[SEQ 99] [Worker-2] [Client-1] leaving critical section for RESERVE
[SEQ 100] [Worker-2] [Client-3] received STATUS 6
[SEQ 101] [Worker-2] [Client-5] received STATUS 10
[SEQ 102] [Worker-2] [Client-3] received QUIT
[SEQ 103] [Worker-2] [Client-1] received STATUS 1
[SEQ 104] [Worker-1] [Client-2] Seat 4 reserved
[SEQ 105] [Worker-1] [Client-2] leaving critical section for RESERVE
[SEQ 106] [Worker-1] [Client-5] received QUIT
[SEQ 107] [Worker-1] [Client-2] received CANCEL 4
[SEQ 108] [Worker-1] [Client-2] waiting for Seat 4
[SEQ 109] [Worker-1] [Client-2] locked Seat 4
[SEQ 110] [Worker-1] [Client-2] entering critical section for CANCEL
[SEQ 111] [Worker-1] [Client-2] Seat 4 cancelled
[SEQ 112] [Worker-1] [Client-2] leaving critical section for CANCEL
[SEQ 113] [Worker-3] [Client-4] received STATUS 7
[SEQ 114] [Worker-1] [Client-2] received STATUS 3
[SEQ 115] [Worker-1] [Client-4] received QUIT
[SEQ 116] [Worker-2] [Client-1] received CANCEL 1
[SEQ 117] [Worker-2] [Client-1] waiting for Seat 1
[SEQ 118] [Worker-2] [Client-1] locked Seat 1
[SEQ 119] [Worker-2] [Client-1] entering critical section for CANCEL
[SEQ 120] [Worker-2] [Client-1] Seat 1 cancelled
[SEQ 121] [Worker-2] [Client-1] leaving critical section for CANCEL
[SEQ 122] [Worker-2] [Client-2] received LIST
[SEQ 123] [Worker-2] [Client-1] received STATUS 2
[SEQ 124] [Worker-3] [Client-2] received QUIT
[SEQ 125] [Worker-1] [Client-1] received QUIT
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
