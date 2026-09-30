# Airplane Reservation System - Experiment Report

วันที่ทดลอง: 27 กันยายน 2026

รายงานนี้สรุปผลการทดลองจากไฟล์หลักฐานจริงใน `results/experiment-study-2026-09-27/` โดยแยก configuration และผลลัพธ์ของแต่ละการทดลองอย่างชัดเจน

> รายงานนี้เป็นผลย้อนหลังจาก source commit ที่ระบุด้านล่าง ซึ่งยังใช้ shared response queue ตัวเลขเหล่านี้ไม่ใช่ผล benchmark ของ architecture ปัจจุบันที่ใช้ private reply queues ดูผังปัจจุบันใน [architecture.md](architecture.md)

> **การอ่านผล:** `REJECTED` ในการทดสอบแย่งจองที่นั่งเดียวกันเป็น expected contention ไม่ใช่ความผิดพลาดของ test script ส่วน `Transport Fail` หมายถึง request หรือ response ไม่เสร็จภายใน timeout จริง

## 1. Environment และเกณฑ์การทดลอง

### Environment

| Configuration | Value |
| --- | --- |
| Source commit | `f39198b7728b4c144ed289a3a69a725158324c8f` |
| Branch ขณะทดลอง | `update-run-documentation` |
| Container image | `airplane-reservation:latest` (`sha256:326ed0e47e4...`) |
| Docker | Docker Desktop 29.7.2 |
| Runtime kernel | Linux 6.6.87.2-microsoft-standard-WSL2 |
| Host resources | 12 CPUs, RAM ประมาณ 7.57 GiB |
| IPC | System V request queue และ shared response queue |
| Application timeout | 10 วินาทีต่อ request/response |
| External load-test guard | 120 วินาทีต่อ calibration point |

### Common controls

| Control | Value | เหตุผล |
| --- | --- | --- |
| Fresh server | Restart container ก่อน formal run ทุกครั้ง | ป้องกัน seat state, queue และ log จากรอบก่อนหน้า |
| Concurrent experiments | 5 clients จอง Seat 10 | ทำให้ทุก client แข่งขันบน resource เดียวกัน |
| Load-test operation | `STATUS`, วน Seat 1-20 แบบ round-robin | วัดความสามารถของ IPC/workers โดยไม่มี random transaction delay |
| Formal repetitions | 3 รอบต่อการทดลอง | ตรวจความสม่ำเสมอของผล |
| Stable load | Completed 100%, Transport Fail 0 และผ่าน 3/3 รอบ | ใช้เป็นเกณฑ์ capacity ที่ยืนยันได้ |

### ความหมายของ metrics

| Metric | ความหมาย |
| --- | --- |
| Successful | Business operation สำเร็จ |
| Rejected | Business operation ถูกปฏิเสธ เช่น ที่นั่งถูกจองแล้ว |
| Consistency | ตรวจว่ามี client มากกว่าหนึ่งรายได้ SUCCESS บนที่นั่งเดียวกันหรือไม่ |
| Transport Fail | ส่ง request หรือรับ response ไม่สำเร็จภายใน timeout |
| Throughput | จำนวน completed requests หารด้วยเวลารวม |
| Average latency | เวลาเฉลี่ยตั้งแต่ก่อนส่ง request จนได้รับ response |

## 2. Experiment 1 - Sequential baseline

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `sequential` |
| Server mode | `sync` |
| Workers | 1 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Server logging | Verbose |
| Repetitions | 3 fresh-container runs |

Baseline ใช้ worker เพียงหนึ่งตัว จึงประมวลผล request ทีละรายการ แม้ client ทั้ง 5 จะเริ่มพร้อมกัน

### Result summary

| Run | Started UTC | Success | Rejected | Final owner | Consistency |
| ---: | --- | ---: | ---: | --- | --- |
| 1 | 2026-09-27T08:59:28.696856900Z | 1/5 | 4/5 | Client-1 | PASSED |
| 2 | 2026-09-27T08:59:35.455730600Z | 1/5 | 4/5 | Client-1 | PASSED |
| 3 | 2026-09-27T08:59:41.640567100Z | 1/5 | 4/5 | Client-1 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | SUCCESS | REJECTED | REJECTED | REJECTED | REJECTED |
| 2 | SUCCESS | REJECTED | REJECTED | REJECTED | REJECTED |
| 3 | SUCCESS | REJECTED | REJECTED | REJECTED | REJECTED |

**สรุป:** ผลตรงตาม baseline ทั้ง 3 รอบ มีผู้จองสำเร็จหนึ่งราย ที่เหลือถูก reject และไม่พบ seat conflict

## 3. Experiment 2 - Concurrent without synchronization

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `nosync` |
| Server mode | `nosync` |
| Workers | 3 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Synchronization | Disabled |
| Server logging | Verbose |
| Repetitions | 3 fresh-container runs |

การทดลองนี้เปิด 3 workers โดยไม่ล็อก critical section เพื่อสาธิต race condition ระหว่างการ check และ write Seat 10

### Result summary

| Run | Started UTC | Success | Rejected | Clients ที่ได้รับ SUCCESS | Final owner | Consistency |
| ---: | --- | ---: | ---: | --- | --- | --- |
| 1 | 2026-09-27T09:00:02.540612800Z | 3/5 | 2/5 | Client-1, Client-3, Client-4 | Client-3 | FAILED - 1 conflict |
| 2 | 2026-09-27T09:00:09.164411400Z | 3/5 | 2/5 | Client-1, Client-2, Client-3 | Client-2 | FAILED - 1 conflict |
| 3 | 2026-09-27T09:00:15.477397900Z | 3/5 | 2/5 | Client-1, Client-2, Client-5 | Client-2 | FAILED - 1 conflict |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | SUCCESS - RACE | REJECTED | SUCCESS - RACE | SUCCESS - RACE | REJECTED |
| 2 | SUCCESS - RACE | SUCCESS - RACE | SUCCESS - RACE | REJECTED | REJECTED |
| 3 | SUCCESS - RACE | SUCCESS - RACE | REJECTED | REJECTED | SUCCESS - RACE |

**สรุป:** เกิด race condition ครบ 3/3 รอบ แต่ละรอบมี 3 clients ได้ SUCCESS บน Seat 10 เดียวกัน ขณะที่ seat map เก็บ owner สุดท้ายได้เพียงหนึ่งรายจากพฤติกรรม last write wins

## 4. Experiment 3 - Concurrent with synchronization

### Configuration

| Configuration | Value |
| --- | --- |
| Experiment label | `sync` |
| Server mode | `sync` |
| Workers | 3 |
| Clients | 5 logical client processes |
| Command | `RESERVE 10` แล้ว `QUIT` |
| Target resource | Seat 10 |
| Synchronization | Enabled - per-seat lock |
| Server logging | Verbose |
| Repetitions | 3 fresh-container runs |

ใช้ configuration เดียวกับ Nosync แต่เพิ่ม per-seat locking ครอบ critical section

### Result summary

| Run | Started UTC | Success | Rejected | Final owner | Consistency |
| ---: | --- | ---: | ---: | --- | --- |
| 1 | 2026-09-27T09:00:37.560684200Z | 1/5 | 4/5 | Client-1 | PASSED |
| 2 | 2026-09-27T09:00:43.383760500Z | 1/5 | 4/5 | Client-2 | PASSED |
| 3 | 2026-09-27T09:00:49.342096300Z | 1/5 | 4/5 | Client-2 | PASSED |

### Client-by-client results

| Run | Client-1 | Client-2 | Client-3 | Client-4 | Client-5 |
| ---: | --- | --- | --- | --- | --- |
| 1 | SUCCESS | REJECTED | REJECTED | REJECTED | REJECTED |
| 2 | REJECTED | SUCCESS | REJECTED | REJECTED | REJECTED |
| 3 | REJECTED | SUCCESS | REJECTED | REJECTED | REJECTED |

**สรุป:** ผ่าน 3/3 รอบ แม้ผู้ชนะเปลี่ยนตาม scheduling แต่มีผู้จอง Seat 10 สำเร็จเพียงหนึ่งรายและ invariant ยังคงถูกต้องทุกครั้ง

## 5. Demo 1 - Mixed commands

### Configuration

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Clients | 5 |
| Commands covered | `LIST`, `STATUS`, `RESERVE`, `CANCEL`, `QUIT` |
| Workload per client | จอง 2 ที่นั่ง ยกเลิก 1 ที่นั่ง และเหลือที่นั่งจองไว้ 1 ที่ |
| Seat range | Seats 1-10 |
| Server logging | Verbose |
| Repetitions | 3 fresh-container runs |
| Expected final seats | 2:C1, 3:C2, 6:C3, 7:C4, 10:C5 |

### Fixed command plan per client

| Client | Command sequence | Expected final reservation |
| --- | --- | --- |
| Client-1 | `LIST -> RESERVE 1 2 -> STATUS 1 -> CANCEL 1 -> STATUS 2 -> QUIT` | Seat 2 |
| Client-2 | `STATUS 3 -> RESERVE 3 4 -> CANCEL 4 -> STATUS 3 -> LIST -> QUIT` | Seat 3 |
| Client-3 | `RESERVE 5 6 -> LIST -> CANCEL 5 -> STATUS 6 -> QUIT` | Seat 6 |
| Client-4 | `RESERVE 7 8 -> STATUS 8 -> CANCEL 8 -> LIST -> STATUS 7 -> QUIT` | Seat 7 |
| Client-5 | `LIST -> RESERVE 9 10 -> CANCEL 9 -> STATUS 10 -> QUIT` | Seat 10 |

### Result summary

| Run | Started UTC | Reservations | Failed | Cancellations | Remaining | Consistency |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | 2026-09-27T09:01:11.781284700Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 2 | 2026-09-27T09:01:24.233868700Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |
| 3 | 2026-09-27T09:01:36.944920600Z | 10/10 | 0/10 | 5/5 | 5/5 | PASSED |

### Client results in every run

ผลด้านล่างเหมือนกันทั้ง Run 1, Run 2 และ Run 3

| Client | Reserved | Cancelled | Remains reserved |
| --- | --- | --- | --- |
| Client-1 | SUCCESS - Seats 1, 2 | SUCCESS - Seat 1 | SUCCESS - Seat 2 |
| Client-2 | SUCCESS - Seats 3, 4 | SUCCESS - Seat 4 | SUCCESS - Seat 3 |
| Client-3 | SUCCESS - Seats 5, 6 | SUCCESS - Seat 5 | SUCCESS - Seat 6 |
| Client-4 | SUCCESS - Seats 7, 8 | SUCCESS - Seat 8 | SUCCESS - Seat 7 |
| Client-5 | SUCCESS - Seats 9, 10 | SUCCESS - Seat 9 | SUCCESS - Seat 10 |

**สรุป:** Demo 1 ผ่านครบ 3/3 รอบ ไม่มี operation failure, final state ตรงตามที่คาด และ consistency PASSED ทุกครั้ง

## 6. Load-capacity calibration

### Configuration

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Total requests | 100,000 ต่อจุด |
| Operation | `STATUS` |
| Seat selection | Round-robin Seats 1-20 |
| Variable under test | Concurrency / logical clients |
| Log modes | Verbose และ Quiet |
| Application timeout | 10 วินาที |
| External cap | 120 วินาทีต่อจุด |

### Calibration results

| Concurrency | Quiet completed | Quiet req/s | Quiet latency | Verbose completed | Verbose fail | Verbose req/s | Verbose latency |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 100,000 | 423,203 | 0.222 ms | 100,000 | 0 | 111,569 | 0.871 ms |
| 250 | 100,000 | 398,712 | 0.564 ms | 100,000 | 0 | 85,143 | 2.855 ms |
| 500 | 100,000 | 258,047 | 1.652 ms | 100,000 | 0 | 21,162 | 23.121 ms |
| 750 | 100,000 | 58,455 | 11.914 ms | 100,000 | 0 | 6,430 | 113.870 ms |
| 1,000 | 100,000 | 14,701 | 64.890 ms | 100,000 | 0 | 2,358 | 414.144 ms |
| 1,250 | 100,000 | 10,250 | 112.097 ms | 100,000 | 0 | 1,811 | 672.972 ms |
| 1,500 | 100,000 | 10,754 | 106.315 ms | 99,943 | 57 | 1,428 | 986.347 ms |
| 2,000 | 100,000 | 7,333 | 180.933 ms | - | - | - | - |
| 3,000 | 100,000 | 15,735 | 66.624 ms | - | - | - | - |
| 5,000 | 100,000 | 297,240 | 0.219 ms | - | - | - | - |

**จุด failure ที่พบ:** Verbose concurrency 1,500 ทำเสร็จ 99,943/100,000 requests, มี Transport Fail 57, ใช้เวลา 69.965 วินาที, throughput 1,428.47 req/s และ latency เฉลี่ย 986.347 ms

## 7. Load Test - Verbose logging

### Configuration

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Server logging | Verbose - log ทุก request |
| Requests | 100,000 `STATUS` requests |
| Seat selection | Round-robin 1-20 |
| Stable candidate | Concurrency 1,000 |
| Boundary candidate | Concurrency 1,250 |
| Observed failure | Concurrency 1,500 |
| Pass criteria | Completed 100%, Transport Fail 0, ผ่าน 3/3 รอบ |

### Stable confirmation - concurrency 1,000

| Run | Started UTC | Completed | Transport Fail | Operation OK | Time | Throughput | Avg latency | Result |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 2026-09-27T09:12:52.318781700Z | 100,000 | 0 | 100,000 | 31.231 s | 3,201.92 req/s | 306.448 ms | PASS |
| 2 | 2026-09-27T09:13:29.322748100Z | 100,000 | 0 | 100,000 | 32.949 s | 3,034.99 req/s | 320.954 ms | PASS |
| 3 | 2026-09-27T09:14:08.340068500Z | 100,000 | 0 | 100,000 | 42.754 s | 2,338.98 req/s | 419.653 ms | PASS |
| **Mean** | - | **100,000** | **0** | **100,000** | **35.645 s** | **2,858.63 req/s** | **349.018 ms** | **PASS 3/3** |

### Boundary confirmation - concurrency 1,250

| Run | Started UTC | Completed | Transport Fail | Operation OK | Time | Throughput | Avg latency | Result |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 2026-09-27T09:09:16.386921400Z | 100,000 | 0 | 100,000 | 50.470 s | 1,981.38 req/s | 607.397 ms | PASS |
| 2 | 2026-09-27T09:10:13.048804600Z | 100,000 | 0 | 100,000 | 59.227 s | 1,688.43 req/s | 723.137 ms | PASS |
| 3 | 2026-09-27T09:11:18.236052600Z | 99,998 | 2 | 99,998 | 61.602 s | 1,623.29 req/s | 739.580 ms | FAIL |

**สรุป:** Concurrency 1,000 ผ่าน 3/3 และเป็นค่าสูงสุดที่ยืนยันว่า stable ภายใต้ verbose logging ส่วน 1,250 ผ่านเพียง 2/3 จึงไม่ถือว่า stable และ calibration ที่ 1,500 พบ timeout 57 requests

## 8. Load Test - Quiet logging

### Configuration

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Server logging | Quiet - ไม่เขียน per-request log |
| Requests | 100,000 `STATUS` requests |
| Concurrency | 5,000 logical clients |
| Seat selection | Round-robin 1-20 |
| Repetitions | 3 fresh-container runs |
| Pass criteria | Completed 100%, Transport Fail 0, process exit 0 |
| Interpretation | Lower bound ไม่ใช่ absolute maximum |

### Detailed results - concurrency 5,000

| Run | Started UTC | Completed | Transport Fail | Operation OK | Time | Throughput | Avg latency | Result |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 2026-09-27T09:15:20.192851700Z | 100,000 | 0 | 100,000 | 0.356 s | 280,762 req/s | 0.231 ms | PASS |
| 2 | 2026-09-27T09:15:25.921293500Z | 100,000 | 0 | 100,000 | 0.308 s | 324,358 req/s | 0.209 ms | PASS |
| 3 | 2026-09-27T09:15:31.279062400Z | 100,000 | 0 | 100,000 | 0.339 s | 295,044 req/s | 0.229 ms | PASS |
| **Mean** | - | **100,000** | **0** | **100,000** | **0.334 s** | **300,055 req/s** | **0.223 ms** | **PASS 3/3** |

**สรุป:** ระบบรองรับอย่างน้อย 5,000 logical clients สำหรับ workload นี้และผ่าน 3/3 รอบ แต่ยังไม่พบ timeout ภายในขอบเขตที่ทดลอง จึงสรุปได้เพียงว่า capacity เท่ากับหรือมากกว่า 5,000 ไม่ใช่ว่า 5,000 คือเพดานสูงสุด

Load generator ใช้หนึ่ง `std::thread` ต่อ logical client การเพิ่มสูงกว่า 5,000 จึงเริ่มเสี่ยงวัดข้อจำกัดของ OS thread creation/scheduling มากกว่าความสามารถของ server

## 9. Comparison และข้อสรุป

### Correctness comparison

| Experiment | Workers | Synchronization | Success pattern | Consistency | Conclusion |
| --- | ---: | --- | --- | --- | --- |
| Sequential | 1 | Enabled | 1/5 ทุก run | PASS 3/3 | Baseline ถูกต้อง |
| Nosync | 3 | Disabled | 3/5 ทุก run | FAIL 3/3 | Reproduce race condition ได้ |
| Sync | 3 | Enabled | 1/5 ทุก run | PASS 3/3 | Lock ป้องกัน race ได้ |
| Demo 1 | 3 | Enabled | 10 reserves + 5 cancels | PASS 3/3 | คำสั่งหลักทำงานครบ |

### Performance comparison

| Load mode | Validated point | Pass rate | Mean throughput | Mean latency | Interpretation |
| --- | ---: | ---: | ---: | ---: | --- |
| Verbose | 1,000 clients | 3/3 | 2,858.63 req/s | 349.018 ms | Stable maximum ที่ยืนยันได้ |
| Verbose boundary | 1,250 clients | 2/3 | 1,764.37 req/s | 690.038 ms | ไม่ stable |
| Quiet | 5,000 clients | 3/3 | 300,055 req/s | 0.223 ms | Validated lower bound |

### Key findings

1. ระบบหลาย workers ต้องใช้ synchronization ครอบ check/write ของ resource เดียวกัน
2. Nosync แสดง race condition ได้ครบทุก run ส่วน Sync ป้องกันการจองซ้ำได้ครบทุก run
3. Verbose logging เป็น bottleneck สำคัญ เนื่องจาก stdout/Docker logging มี overhead สูง
4. การเพิ่ม concurrency ไม่ได้ทำให้ throughput สูงขึ้นเสมอ เมื่อระบบอิ่มตัว latency และ scheduling overhead จะเพิ่มขึ้น
5. Quiet mode ผ่านที่ 5,000 clients แต่ยังสรุป absolute maximum ไม่ได้จากชุดข้อมูลนี้

## 10. Evidence directories

| Dataset | Path | Reports |
| --- | --- | ---: |
| Experiment 1-3 | `results/experiment-study-2026-09-27/demos/concurrent/` | 9 |
| Demo 1 | `results/experiment-study-2026-09-27/demos/demo1/` | 3 |
| Verbose boundary 1,250 | `results/experiment-study-2026-09-27/load-formal/verbose/` | 3 |
| Verbose stable 1,000 | `results/experiment-study-2026-09-27/load-stability/verbose-1000/` | 3 |
| Quiet 5,000 | `results/experiment-study-2026-09-27/load-formal/quiet/` | 3 |
| Calibration | `results/experiment-study-2026-09-27/load-calibration/` | 17 |

ตัวเลขในรายงานอ่านจาก `report.txt`, `output.log`, `seat-map.txt` และ `seat-conflicts.txt` ที่สร้างหลังการทดลองจริง
