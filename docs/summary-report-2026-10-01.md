# Airplane Reservation System — Summary Report

วันที่ทดลอง: 1 ตุลาคม 2026

รายงานนี้รวมผลจากทุกการทดลองไว้ในที่เดียว ใช้เปรียบเทียบภาพรวมระหว่าง Experiment 1–3, Demo 1 และ Load Test โดยชี้จุดสำคัญในแต่ละมิติและอ้างอิงรายงานย่อย

---

## 1. ดัชนีไฟล์หลักฐาน

| ไฟล์ | เนื้อหา |
| --- | --- |
| `docs/evidence/2026-10-01/environment.json` | Environment: commit, image, Docker version, RAM, kernel |
| `docs/evidence/2026-10-01/experiment-transcripts.txt` | Raw output จาก Exp 1-3 และ Demo 1 รายรอบ |
| `docs/evidence/2026-10-01/load-transcripts.txt` | Raw output จาก Load Test ทุก client level |
| `docs/experiment-report-2026-10-01.md` | รายงาน Exp 1-3 + Demo 1 (รายละเอียด) |
| `docs/load-test-report-2026-10-01.md` | รายงาน Load Test (รายละเอียด) |
| `experiment-tables.md` | ตาราง 25 ตารางในรูปแบบกะทัดรัด |

---

## 2. ภาพรวม Environment

| Configuration | Value |
| --- | --- |
| Source commit | `d6dab3528f354159668039bc5d011c14ca7de717` |
| Branch | `task/concurrency-updates` |
| Image | `airplane-reservation:study-2026-10-01` |
| Docker | Docker Desktop 29.7.2 |
| Kernel | Linux 6.18.33.1-microsoft-standard-WSL2 |
| Host | 12 CPUs, 15.58 GiB RAM, x86_64 |
| IPC | System V — shared request queue + private reply queue per client |
| Application timeout | 10 วินาที |
| External guard | 180 วินาทีต่อรอบ |

---

## 3. Correctness — Experiment 1-3 และ Demo 1

### 3.1 Result matrix ทุก experiment

| Experiment | Mode | Workers | Command | Success | Consistency | Winner |
| --- | --- | ---: | --- | --- | --- | --- |
| Exp 1 Run 1 | sync | 1 | RESERVE 10 | 1/5 | ✅ PASSED | Client-2 |
| Exp 1 Run 2 | sync | 1 | RESERVE 10 | 1/5 | ✅ PASSED | Client-2 |
| Exp 1 Run 3 | sync | 1 | RESERVE 10 | 1/5 | ✅ PASSED | Client-2 |
| Exp 2 Run 1 | nosync | 3 | RESERVE 10 | 3/5 | ❌ FAILED | C1/C2/C3 → C1 final |
| Exp 2 Run 2 | nosync | 3 | RESERVE 10 | 3/5 | ❌ FAILED | C1/C2/C3 → C2 final |
| Exp 2 Run 3 | nosync | 3 | RESERVE 10 | 3/5 | ❌ FAILED | C1/C2/C3 → C1 final |
| Exp 3 Run 1 | sync | 3 | RESERVE 10 | 1/5 | ✅ PASSED | Client-2 |
| Exp 3 Run 2 | sync | 3 | RESERVE 10 | 1/5 | ✅ PASSED | Client-4 |
| Exp 3 Run 3 | sync | 3 | RESERVE 10 | 1/5 | ✅ PASSED | Client-3 |
| Demo 1 Run 1 | sync | 3 | Mixed | 10/10 | ✅ PASSED | All clients |
| Demo 1 Run 2 | sync | 3 | Mixed | 10/10 | ✅ PASSED | All clients |
| Demo 1 Run 3 | sync | 3 | Mixed | 10/10 | ✅ PASSED | All clients |

### 3.2 สรุปตาม experiment

| Experiment | กลไก | Consistency rate | Winner pattern | ข้อสรุป |
| --- | --- | --- | --- | --- |
| Exp 1 (sequential) | 1 worker | 3/3 PASS | Client-2 ชนะทุกรอบ | Deterministic; ไม่มี race |
| Exp 2 (nosync) | 3 workers ไม่มี lock | 0/3 PASS | Client-1,2,3 ได้ SUCCESS ทุกรอบ | Race condition เกิดทุกรอบ |
| Exp 3 (sync) | 3 workers + mutex | 3/3 PASS | Winner ต่างกันทุกรอบ | Mutex แก้ race; non-deterministic priority |
| Demo 1 | 3 workers + mutex | 3/3 PASS | ทุก client ประสบสำเร็จตามแผน | คำสั่งผสมทำงานครบถ้วน |

### 3.3 ผลต่างระหว่าง nosync และ sync

| ด้าน | nosync (Exp 2) | sync (Exp 3) | ผลต่าง |
| --- | --- | --- | --- |
| Clients ได้ SUCCESS | 3/5 ทุกรอบ | 1/5 ทุกรอบ | Mutex ลด SUCCESS เหลือ 1 รายต่อ seat |
| Seat conflict | เกิดทุกรอบ | ไม่เกิดเลย | Mutex ป้องกัน race ได้ 100% |
| Final owner | ผิดแตกต่างกัน (last-write-wins) | ตรงตาม real winner | Mutex ทำให้ seat map ถูกต้อง |
| Winner determinism | Non-deterministic | Non-deterministic | ทั้งคู่ขึ้นกับ OS scheduling |

---

## 4. Performance — Load Test

### 4.1 Timeline ประสิทธิภาพตามจำนวน clients

| Clients | Throughput เฉลี่ย (req/s) | Latency เฉลี่ย (ms) | Timeout รวม | Zone |
| ---: | ---: | ---: | ---: | --- |
| 20 | 56,691 | 0.33 | 0 | 🟢 Scaling |
| 50 | 96,225 | 0.48 | 0 | 🟢 Scaling |
| 100 | 114,865 | 0.87 | 0 | 🟢 Scaling |
| **200** | **135,542** | **1.43** | **0** | **🏆 Peak** |
| 500 | 11,657 | 45.19 | 0 | 🟡 Saturated |
| 1,000 | 3,111 | 324 | 0 | 🟡 Saturated |
| 1,500 | 2,574 | 575 | 0 | 🟡 Saturated |
| 2,000 | 2,337 | 860 | 119 | 🔴 Degraded |

### 4.2 Saturation boundary

| ด้าน | ค่า |
| --- | --- |
| จุดสูงสุด (peak) | 200 clients — 135,542 req/s |
| Saturation onset | ระหว่าง 200 และ 500 clients |
| Throughput drop (200→500) | 135,542 → 11,657 (-92%) |
| Latency jump (200→500) | 1.43 ms → 45.19 ms (+31×) |
| Last stable level | 1,500 clients — 3/3 PASS, timeout 0 |
| First failure point | 2,000 clients — timeout 119 รวม (0.02% of 600,000) |

### 4.3 Variation ระหว่างรอบ

| Clients | Throughput min | Throughput max | Ratio | สาเหตุหลัก |
| ---: | ---: | ---: | ---: | --- |
| 20 | 50,050 | 64,934 | 1.3× | OS scheduling variability |
| 100 | 89,663 | 164,762 | 1.8× | OS scheduling variability |
| 500 | 9,100 | 16,409 | 1.8× | IPC queue backpressure variability |
| 1,000 | 2,508 | 3,716 | 1.5× | Kernel thread scheduling |

---

## 5. ข้อสังเกตข้ามมิติ

### 5.1 Correctness vs Performance trade-off

| กลไก | Correctness | Throughput | Trade-off |
| --- | --- | --- | --- |
| 1 worker (Exp 1) | ✅ PASS 3/3 | ต่ำ (sequential) | Safety มาก แต่ scale ไม่ได้ |
| 3 workers nosync (Exp 2) | ❌ FAIL 3/3 | สูงกว่า | Scale ได้แต่ data corrupt |
| 3 workers sync (Exp 3) | ✅ PASS 3/3 | ปานกลาง | Best of both worlds ในชุดนี้ |

### 5.2 IPC architecture observation

Architecture ปัจจุบัน (private reply queue per client) แก้ปัญหา response routing race ที่พบใน shared reply queue (architecture เก่า) ดูได้จาก:
- Experiment 2 ยังแสดง race condition — เกิดจาก **ส่วน check/write** บน seat state ไม่ใช่ IPC
- Experiment 3 + 3 workers แก้ได้ด้วย mutex บน seat state
- Response routing ถูกต้องทุกรอบ (ไม่มี wrong-client response)

### 5.3 Load test generator limitation

IPC queue limit บน Linux (~819,200 bytes โดย default) จำกัดจำนวน in-flight messages ได้ จึงเห็นว่า `Peak In-Flight` ที่ 2,000 clients ถึงแค่ 1,380–1,295 (ไม่ใช่ 2,000) แสดงว่า kernel queue ทำหน้าที่ backpressure อยู่

---

## 6. รายงานอ้างอิง

| รายงาน | เส้นทาง | เนื้อหา |
| --- | --- | --- |
| Experiment Report (2026-10-01) | `docs/experiment-report-2026-10-01.md` | Exp 1-3, Demo 1 — log references ทุกค่า |
| Load Test Report (2026-10-01) | `docs/load-test-report-2026-10-01.md` | Load test ทุก client level — log references ทุกค่า |
| Experiment Tables | `experiment-tables.md` | 25 ตารางกะทัดรัด |
| Experiment Report เก่า (2026-09-27) | `docs/experiment-report.md` | ผลก่อน architecture เปลี่ยน (shared reply queue) |
| Methodology | `Sirawit-Report/methodology.md` | วิธีทดลองและ environment |

---

*หลักฐานทั้งหมด: `docs/evidence/2026-10-01/` | Source: `d6dab3528f354159668039bc5d011c14ca7de717`*
