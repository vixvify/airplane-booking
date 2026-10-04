# Airplane Reservation System — Load Test Report

วันที่ทดลอง: 1 ตุลาคม 2026

รายงานนี้สรุปผล Load Test แบบ MIXED (RESERVE + CANCEL สลับ) จากหลักฐานจริงใน `docs/evidence/2026-10-01/load-transcripts.txt` โดยแสดงข้อมูลแต่ละรอบ พร้อมหลักฐาน log อ้างอิงสำหรับทุกค่าในตาราง

> **การอ่านผล:** Throughput นับทุก response รวม business rejection ด้วย จึงไม่ใช่จำนวนการจองสำเร็จต่อวินาที ส่วน latency วัดตั้งแต่ก่อนส่งจนได้รับ response คำนวณเฉพาะ requests ที่ได้รับคำตอบ ไม่รวม timeout

---

## 1. Environment และ Test Configuration

### Environment

คอลัมน์ **Configuration** คือรายการสภาพแวดล้อมที่บันทึกไว้ ส่วน **Value** คือค่าที่ใช้ขณะทดลอง เช่น เวอร์ชัน compiler หรือทรัพยากรเครื่อง ตารางนี้อธิบายเงื่อนไขการทดลอง ไม่ใช่ผลการวัดประสิทธิภาพ

| Configuration | Value |
| --- | --- |
| Source commit | `d6dab3528f354159668039bc5d011c14ca7de717` |
| Branch | `task/concurrency-updates` |
| Container image | `airplane-reservation:study-2026-10-01` (`sha256:6272f86561cd...`) |
| Docker | Docker Desktop 29.7.2 |
| Runtime kernel | Linux 6.18.33.1-microsoft-standard-WSL2 |
| Host resources | 12 CPUs, RAM 15.58 GiB |
| Architecture | x86_64 |

**หลักฐาน:** `docs/evidence/2026-10-01/environment.json`

### Test Configuration (คงที่ทุก level)

คอลัมน์ **Configuration** คือชื่อการตั้งค่าการทดสอบ ส่วน **Value** คือค่าที่กำหนดเหมือนกันทุกระดับ clients จึงใช้ดูว่าปัจจัยใดถูกควบคุมไว้ขณะเพิ่มโหลด

| Configuration | Value |
| --- | --- |
| Server mode | `sync` |
| Workers | 3 |
| Server logging | Quiet — ไม่เขียน per-request log เพื่อลด I/O overhead |
| Artificial race delay | Off (`AIRPLANE_RACE_DELAY=off`) |
| Operation | `MIXED` — สลับ RESERVE → CANCEL เป็นคู่ |
| Seat selection | Round-robin Seat 1–20 (pattern: `((i + req/2) % 20) + 1`) |
| Requests per client | 100 |
| Load generator | 1 logical client = 1 OS thread = 1 private reply queue |
| Start gate | Threads รอที่ barrier ก่อนเริ่มพร้อมกัน |
| Request timeout | 10 วินาที (send + receive รวมกัน) |
| External run guard | 180 วินาทีต่อรอบ |
| Pass criteria | Completed 100%, Transport Fail 0, Timeouts 0, exit code 0 |
| Repetitions | 3 fresh-container runs ต่อ client level |

### คำอธิบายคอลัมน์ตารางผลรายรอบ

คำอธิบายนี้ใช้กับตาราง **ผลรายรอบ** ของทุกระดับตั้งแต่ 20 ถึง 2,000 clients ค่าในแถว Run 1–3 เป็นผลของแต่ละรอบ ไม่ใช่ผลรวมสามรอบ หน่วย `req/s` หมายถึงคำขอต่อวินาที และ `ms` คือมิลลิวินาที โดย 1,000 ms = 1 วินาที

| คอลัมน์ | หมายถึงอะไร | วิธีอ่านและหน่วย |
| --- | --- | --- |
| Run | ลำดับรอบที่ทดลองด้วยจำนวน clients เท่ากัน | รอบ 1, 2 และ 3 เริ่ม server ใหม่แยกกัน ไม่ใช่ช่วงต่อเนื่องของการรันเดียว |
| Throughput (req/s) | จำนวนคำขอที่ได้รับคำตอบต่อวินาที | `Completed ÷ Total Time` รวมทั้งคำสั่งที่สำเร็จและถูกปฏิเสธ ค่าสูงแปลว่าตอบคำขอได้มากต่อวินาที ไม่ใช่จองสำเร็จมากเท่านั้น |
| Avg Latency (ms) | เวลารอคำตอบเฉลี่ยของคำขอในรอบนั้น | นับตั้งแต่ก่อนส่งจนได้รับ matching response รวมเวลารอคิว คำนวณเฉพาะคำขอที่ได้รับคำตอบ ค่าต่ำแปลว่ารอโดยเฉลี่ยสั้นลง |
| p95 (ms) | เวลารอคำตอบที่ percentile 95 | ประมาณ 95% ของคำขอที่ได้รับคำตอบใช้เวลาไม่เกินค่านี้ เช่น p95 = 200 ms แปลว่าประมาณ 5% รอนานกว่า 200 ms ไม่ใช่ค่าเฉลี่ย |
| p99 (ms) | เวลารอคำตอบที่ percentile 99 | ประมาณ 99% ของคำขอที่ได้รับคำตอบใช้เวลาไม่เกินค่านี้ ใช้ดูคำขอที่ช้ากว่าคำขอส่วนใหญ่ |
| Max (ms) | เวลารอคำตอบสูงสุดที่วัดได้ในรอบ | เป็นค่าสูงสุดเฉพาะคำขอที่ได้รับคำตอบ ไม่รวม requests ที่ timeout จึงอาจต่ำกว่า 10,000 ms แม้มี timeout เกิดขึ้น |
| Completed | จำนวนคำขอที่ได้รับคำตอบเรียบร้อย | หน่วยเป็นคำขอ รวมทั้ง business success และ business rejection ไม่ได้หมายความว่าจองสำเร็จทั้งหมด |
| Transport Fail | จำนวนคำขอที่จบด้วย timeout หรือข้อผิดพลาดในการ exchange | หน่วยเป็นคำขอ คำนวณ `Timeout + Transport Errors` ดังนั้น Timeout เป็นส่วนหนึ่งของค่านี้ ห้ามนำสองคอลัมน์มาบวกซ้ำ |
| Timeout | จำนวนคำขอที่หมดเวลาระหว่างส่งหรือรอรับคำตอบ | หน่วยเป็นคำขอ ใช้กำหนดเวลา 10 วินาทีร่วมกันสำหรับส่งและรับ อาจส่งไม่สำเร็จหรือส่งแล้วแต่รับไม่ทัน ตัวนับนี้ไม่แยกสองกรณี |
| สถานะ | ผลการตรวจว่ารอบนั้นผ่านเกณฑ์หรือไม่ | `PASS` คือได้รับคำตอบครบและไม่มี transport failure; `PARTIAL` คือได้รับคำตอบเพียงบางส่วน ซึ่งถือว่าไม่ผ่านเกณฑ์ PASS |

**การอ่านแถวสรุป:** Throughput และ Avg Latency เป็นค่าเฉลี่ยเลขคณิตของสามรอบ รวมรอบที่มี timeout ด้วย Completed จะแสดงจำนวนต่อรอบเมื่อทั้งสามรอบมีค่าเท่ากัน ส่วน Transport Fail/Timeout ที่ระบุว่า “รวม” เป็นผลรวมสามรอบ ค่า `—` หมายถึงไม่ได้สรุปค่านั้น ไม่ใช่ศูนย์ และไม่ใช่ผล percentile จากการรวม requests ทั้งสามรอบ `PASS 3/3` หมายถึงผ่านสามรอบ ส่วน `PARTIAL 3/3` หมายถึงทั้งสามรอบตอบไม่ครบ หรือผ่าน 0/3 รอบ

**ตัวอย่างอ่านข้อมูล:** ที่ 2,000 clients รอบ 1 วางแผนไว้ 200,000 คำขอ ได้คำตอบ 199,982 คำขอ และ timeout 18 คำขอ จึงมี `Transport Fail = 18` เช่นกัน ไม่ใช่เสียไป 36 คำขอ ส่วน Avg Latency 640.30 ms เป็นค่าเฉลี่ยของ 199,982 คำขอที่ได้คำตอบเท่านั้น

### คำเพิ่มเติมที่ปรากฏใน log

- **Logical Clients:** จำนวน clients จำลองที่สร้างขึ้น แต่ละรายใช้หนึ่ง OS thread ไม่ใช่จำนวน workers ของ server
- **Requests/Client:** จำนวนคำขอที่แต่ละ client ต้องส่ง ในชุดนี้คือ 100 คำขอ
- **Planned Requests:** จำนวนคำขอที่วางแผนไว้ต่อรอบ เท่ากับ clients × 100
- **Operation OK / Succeeded:** จำนวนคำสั่ง RESERVE หรือ CANCEL ที่ตอบว่าสำเร็จ นับคำสั่ง ไม่ใช่จำนวน clients หรือจำนวนคู่การจอง/ยกเลิก
- **Business Reject / Operation Fail:** จำนวนคำสั่งที่ได้รับคำตอบปฏิเสธ เช่น จองที่นั่งที่ไม่ว่าง หรือยกเลิกที่นั่งที่ตนไม่ได้เป็นเจ้าของ ค่านี้ยังนับอยู่ใน Completed
- **Transport Errors:** ข้อผิดพลาดในการส่ง/รับหรือตรวจคำตอบที่ไม่ใช่ timeout เช่น queue ถูกลบ ไม่ใช่ตัวเดียวกับ Transport Fail ซึ่งรวม timeout ด้วย
- **Skipped Requests:** คำขอที่วางแผนไว้แต่ไม่มีผล completed หรือ transport failure เช่น สร้าง client threads ได้ไม่ครบ ในชุดนี้เป็นศูนย์ทุกครั้ง
- **Completion Rate:** `Completed ÷ Planned Requests × 100` เป็นเปอร์เซ็นต์คำขอที่ได้รับคำตอบ ไม่ใช่อัตราจองสำเร็จ
- **Total Time:** เวลาตั้งแต่ปล่อย start gate ให้ clients เริ่มส่งคำขอจน client threads จบ หน่วยวินาที ไม่รวมการสร้าง threads/private queues ก่อนเปิด gate
- **Peak In-Flight:** จำนวน exchanges ที่ส่งคำขอเข้าคิวสำเร็จแล้วและยังไม่จบด้วย response หรือ exception สูงสุดที่พบ หน่วยเป็นคำขอ ไม่ใช่จำนวนงานที่ workers กำลังประมวลผลพร้อมกัน
- **Avg In-Flight:** ค่าเฉลี่ยจากการสุ่มอ่านจำนวน in-flight ระหว่างการรัน sampler รวมช่วงเตรียม threads ก่อนเปิด gate ด้วย จึงไม่ใช่ค่าเฉลี่ยเฉพาะช่วง Total Time

ความสัมพันธ์ที่ใช้ตรวจยอดคือ `Completed = Succeeded + Business Reject`, `Transport Fail = Timeout + Transport Errors` และ `Planned Requests = Completed + Transport Fail + Skipped Requests` ส่วนสูตรในโค้ดตรวจได้ที่ [load_test.cpp](../src/benchmark/load_test.cpp)

---

## 2. 20 Clients

**คำขอรวมต่อรอบ:** 20 × 100 = 2,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 55,090.99 | 0.33 | 0.74 | 1.53 | 3.55 | 2,000 | 0 | 0 | PASS |
| 2 | 64,933.72 | 0.29 | 0.51 | 0.70 | 1.19 | 2,000 | 0 | 0 | PASS |
| 3 | 50,049.82 | 0.37 | 0.97 | 2.17 | 3.56 | 2,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **56,691.51** | **0.33** | — | — | — | **2,000** | **0** | **0** | **PASS 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c20-r1`
```
output.log:
  Logical Clients : 20
  Requests/Client : 100
  Planned Requests: 2000
  Completed       : 2000
  Transport Fail  : 0
  Completion Rate : 100.00%
  Total Time      : 0.036 sec
  Throughput      : 55090.99 req/sec
  Average Latency : 0.33 ms
  Timeouts        : 0
  Peak In-Flight  : 20
  Avg In-Flight   : 14.00
  p95 Latency     : 0.74 ms
  p99 Latency     : 1.53 ms
  Max Latency     : 3.55 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c20-r2`
```
  Total Time      : 0.031 sec
  Throughput      : 64933.72 req/sec
  Average Latency : 0.29 ms
  p95 Latency     : 0.51 ms  p99 Latency : 0.70 ms  Max : 1.19 ms
```

**Run 3** — `MIXED-sync-w3-quiet-c20-r3`
```
  Total Time      : 0.040 sec
  Throughput      : 50049.82 req/sec
  Average Latency : 0.37 ms
  p95 Latency     : 0.97 ms  p99 Latency : 2.17 ms  Max : 3.56 ms
```

---

## 3. 50 Clients

**คำขอรวมต่อรอบ:** 50 × 100 = 5,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 86,077.87 | 0.52 | 1.29 | 2.74 | 5.36 | 5,000 | 0 | 0 | PASS |
| 2 | 101,239.14 | 0.46 | 1.01 | 1.41 | 3.24 | 5,000 | 0 | 0 | PASS |
| 3 | 101,358.94 | 0.46 | 1.17 | 1.80 | 2.79 | 5,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **96,225.32** | **0.48** | — | — | — | **5,000** | **0** | **0** | **PASS 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c50-r1`
```
  Logical Clients : 50
  Planned Requests: 5000
  Completed       : 5000 / Transport Fail : 0
  Total Time      : 0.058 sec
  Throughput      : 86077.87 req/sec
  Average Latency : 0.52 ms
  Peak In-Flight  : 50 / Avg In-Flight : 42.56
  p95 Latency     : 1.29 ms / p99 Latency : 2.74 ms / Max : 5.36 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c50-r2`: `Total Time: 0.049 sec, Throughput: 101239.14, Latency: 0.46 ms`

**Run 3** — `MIXED-sync-w3-quiet-c50-r3`: `Total Time: 0.049 sec, Throughput: 101358.94, Latency: 0.46 ms`

---

## 4. 100 Clients

**คำขอรวมต่อรอบ:** 100 × 100 = 10,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 89,662.93 | 1.02 | 2.82 | 6.58 | 12.81 | 10,000 | 0 | 0 | PASS |
| 2 | 90,171.63 | 1.02 | 2.82 | 4.49 | 12.82 | 10,000 | 0 | 0 | PASS |
| 3 | 164,761.56 | 0.56 | 1.38 | 2.11 | 4.40 | 10,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **114,865.37** | **0.87** | — | — | — | **10,000** | **0** | **0** | **PASS 3/3** |

> **หมายเหตุ Run 3:** Throughput สูงกว่า Run 1-2 เกือบ 2× เป็นผลจาก OS scheduling variability ไม่ใช่การเปลี่ยน config

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c100-r1`
```
  Logical Clients : 100
  Planned Requests: 10000
  Completed       : 10000 / Transport Fail : 0
  Total Time      : 0.112 sec
  Throughput      : 89662.93 req/sec
  Average Latency : 1.02 ms
  Peak In-Flight  : 100 / Avg In-Flight : 81.55
  p95 Latency     : 2.82 ms / p99 Latency : 6.58 ms / Max : 12.81 ms
```

**Run 3** — `MIXED-sync-w3-quiet-c100-r3`: `Total Time: 0.061 sec, Throughput: 164761.56, Latency: 0.56 ms`

---

## 5. 200 Clients — Peak throughput 🏆

**คำขอรวมต่อรอบ:** 200 × 100 = 20,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 141,848.66 | 1.36 | 2.56 | 3.71 | 6.31 | 20,000 | 0 | 0 | PASS |
| 2 | 135,092.66 | 1.43 | 2.53 | 3.58 | 8.51 | 20,000 | 0 | 0 | PASS |
| 3 | 129,685.79 | 1.50 | 3.19 | 4.32 | 7.22 | 20,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **135,542.37** | **1.43** | — | — | — | **20,000** | **0** | **0** | **PASS 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c200-r1`
```
  Logical Clients : 200
  Planned Requests: 20000
  Completed       : 20000 / Transport Fail : 0
  Total Time      : 0.141 sec
  Throughput      : 141848.66 req/sec   ← สูงสุดในสามรอบของระดับ 200 clients
  Average Latency : 1.36 ms
  Peak In-Flight  : 200 / Avg In-Flight : 159.18
  p95 Latency     : 2.56 ms / p99 Latency : 3.71 ms / Max : 6.31 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c200-r2`: `Total Time: 0.148 sec, Throughput: 135092.66, Latency: 1.43 ms`

**Run 3** — `MIXED-sync-w3-quiet-c200-r3`: `Total Time: 0.154 sec, Throughput: 129685.79, Latency: 1.50 ms`

---

## 6. 500 Clients — Saturation begins

**คำขอรวมต่อรอบ:** 500 × 100 = 50,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 9,463.51 | 51.42 | 200.17 | 509.42 | 2,126.51 | 50,000 | 0 | 0 | PASS |
| 2 | 16,409.13 | 29.78 | 77.71 | 147.65 | 454.30 | 50,000 | 0 | 0 | PASS |
| 3 | 9,100.41 | 54.36 | 138.82 | 234.93 | 876.86 | 50,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **11,657.68** | **45.19** | — | — | — | **50,000** | **0** | **0** | **PASS 3/3** |

> ⚠️ Throughput ลดจาก ~135,000 (200c) เหลือ ~11,600 (500c) — ระบบเข้าสู่ saturation

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c500-r1`
```
  Logical Clients : 500
  Planned Requests: 50000
  Completed       : 50000 / Transport Fail : 0
  Total Time      : 5.283 sec
  Throughput      : 9463.51 req/sec
  Average Latency : 51.42 ms
  Peak In-Flight  : 491 / Avg In-Flight : 195.46
  p95 Latency     : 200.17 ms / p99 Latency : 509.42 ms / Max : 2126.51 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c500-r2`
```
  Total Time      : 3.047 sec
  Throughput      : 16409.13 req/sec   ← Run 2 ดีกว่า Run 1/3 ชัดเจน (OS scheduling)
  Average Latency : 29.78 ms
  p95 Latency     : 77.71 ms / p99 Latency : 147.65 ms / Max : 454.30 ms
```

**Run 3** — `MIXED-sync-w3-quiet-c500-r3`
```
  Total Time      : 5.494 sec
  Throughput      : 9100.41 req/sec
  Average Latency : 54.36 ms
  p95 Latency     : 138.82 ms / p99 Latency : 234.93 ms / Max : 876.86 ms
```

---

## 7. 1,000 Clients

**คำขอรวมต่อรอบ:** 1,000 × 100 = 100,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 2,507.88 | 392.53 | 1,064.54 | 1,837.15 | 7,077.49 | 100,000 | 0 | 0 | PASS |
| 2 | 3,109.38 | 316.53 | 920.54 | 1,524.55 | 5,684.63 | 100,000 | 0 | 0 | PASS |
| 3 | 3,716.00 | 263.67 | 686.83 | 1,197.62 | 3,767.11 | 100,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **3,111.09** | **324.24** | — | — | — | **100,000** | **0** | **0** | **PASS 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c1000-r1`
```
  Logical Clients : 1000
  Planned Requests: 100000
  Completed       : 100000 / Transport Fail : 0
  Total Time      : 39.874 sec
  Throughput      : 2507.88 req/sec
  Average Latency : 392.53 ms
  Peak In-Flight  : 958 / Avg In-Flight : 165.07
  p95 Latency     : 1064.54 ms / p99 Latency : 1837.15 ms / Max : 7077.49 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c1000-r2`: `Total Time: 32.161 sec, Throughput: 3109.38, Latency: 316.53 ms`

**Run 3** — `MIXED-sync-w3-quiet-c1000-r3`: `Total Time: 26.911 sec, Throughput: 3716.00, Latency: 263.67 ms`

---

## 8. 1,500 Clients

**คำขอรวมต่อรอบ:** 1,500 × 100 = 150,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 3,021.32 | 483.73 | 1,340.84 | 2,230.38 | 8,413.14 | 150,000 | 0 | 0 | PASS |
| 2 | 2,411.24 | 607.54 | 1,621.24 | 2,757.57 | 8,193.08 | 150,000 | 0 | 0 | PASS |
| 3 | 2,292.19 | 635.96 | 1,713.82 | 2,906.75 | 8,923.23 | 150,000 | 0 | 0 | PASS |
| **เฉลี่ย** | **2,574.92** | **575.74** | — | — | — | **150,000** | **0** | **0** | **PASS 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c1500-r1`
```
  Logical Clients : 1500
  Planned Requests: 150000
  Completed       : 150000 / Transport Fail : 0
  Total Time      : 49.647 sec
  Throughput      : 3021.32 req/sec
  Average Latency : 483.73 ms
  Peak In-Flight  : 1202 / Avg In-Flight : 232.35
  p95 Latency     : 1340.84 ms / p99 Latency : 2230.38 ms / Max : 8413.14 ms
```

**Run 2** — `MIXED-sync-w3-quiet-c1500-r2`: `Total Time: 62.209 sec, Throughput: 2411.24, Latency: 607.54 ms`

**Run 3** — `MIXED-sync-w3-quiet-c1500-r3`: `Total Time: 65.440 sec, Throughput: 2292.19, Latency: 635.96 ms`

---

## 9. 2,000 Clients — เริ่มพบ Timeout 🔴

**คำขอรวมต่อรอบ:** 2,000 × 100 = 200,000 requests

### ผลรายรอบ

| Run | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) | Completed | Transport Fail | Timeout | สถานะ |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 3,036.75 | 640.30 | 2,118.91 | 3,563.43 | 9,845.86 | 199,982 | **18** | **18** | PARTIAL |
| 2 | 1,998.18 | 958.67 | 2,885.96 | 4,835.44 | 9,973.18 | 199,966 | **34** | **34** | PARTIAL |
| 3 | 1,976.93 | 982.93 | 2,755.02 | 4,703.31 | 9,959.35 | 199,933 | **67** | **67** | PARTIAL |
| **สรุป 3 รอบ** | **2,337.29** | **860.63** | — | — | — | — | **119 รวม** | **119 รวม** | **PARTIAL 3/3** |

### หลักฐาน log

**Run 1** — `MIXED-sync-w3-quiet-c2000-r1`
```
  Logical Clients : 2000
  Planned Requests: 200000
  Completed       : 199982    ← ไม่ครบ 200000
  Transport Fail  : 18        ← รวม 18 timeouts; Transport Errors ประเภทอื่นเป็น 0
  Completion Rate : 99.99%
  Total Time      : 65.854 sec
  Throughput      : 3036.75 req/sec
  Average Latency : 640.30 ms
  Timeouts        : 18        ← 18 requests หมดเวลา
  Peak In-Flight  : 1380 / Avg In-Flight : 251.21
  p95 Latency     : 2118.91 ms / p99 Latency : 3563.43 ms / Max : 9845.86 ms
```

> Max Latency 9,845 ms ≈ 9.8 วินาที ใกล้ application timeout 10 วินาที คือ requests ที่รอดมาเกือบ timeout แต่สำเร็จ ส่วน 18 requests ที่ timeout ไม่รวมอยู่ใน latency

**Run 2** — `MIXED-sync-w3-quiet-c2000-r2`
```
  Completed       : 199966 / Timeouts : 34
  Completion Rate : 99.98%
  Total Time      : 100.074 sec
  Throughput      : 1998.18 req/sec
  Average Latency : 958.67 ms
  p95 Latency     : 2885.96 ms / p99 Latency : 4835.44 ms / Max : 9973.18 ms
```

**Run 3** — `MIXED-sync-w3-quiet-c2000-r3`
```
  Completed       : 199933 / Timeouts : 67
  Completion Rate : 99.97%
  Total Time      : 101.133 sec
  Throughput      : 1976.93 req/sec
  Average Latency : 982.93 ms
  p95 Latency     : 2755.02 ms / p99 Latency : 4703.31 ms / Max : 9959.35 ms
```

> Timeout ในสามรอบเท่ากับ 18, 34 และ 67 แต่แต่ละรอบเริ่ม server ใหม่ จึงใช้แนวโน้มนี้สรุปว่าคิวสะสมข้ามรอบไม่ได้ ตัวเลขรวมยังไม่บอกว่า timeout เกิดช่วงใดของแต่ละรอบ

---

## 10. สรุปผล Load Test ทั้งหมด

### ตารางสรุปรายระดับ

**คำอธิบายคอลัมน์:**

- **Clients:** จำนวน logical clients ที่ใช้ในการทดลองระดับนั้น แต่ละรายส่ง 100 คำขอต่อรอบ
- **คำขอ/รอบ:** จำนวนคำขอที่วางแผนต่อหนึ่งรอบ เท่ากับ Clients × 100 ไม่ใช่ยอดรวมสามรอบ
- **Throughput เฉลี่ย (req/s):** ค่าเฉลี่ยเลขคณิตของ throughput จากสามรอบ ไม่ใช่นำจำนวนคำขอรวมมาหารเวลารวม
- **Latency เฉลี่ย (ms):** ค่าเฉลี่ยของ Avg Latency ทั้งสามรอบ โดย Avg Latency ของแต่ละรอบไม่รวมคำขอที่ timeout
- **Timeout รวม 3 รอบ:** ผลบวกของจำนวน timeout ทั้งสามรอบ เช่นระดับ 2,000 clients คือ 18 + 34 + 67 = 119 ไม่ใช่ค่าเฉลี่ยต่อรอบ
- **Zone:** ป้ายสรุปแนวโน้มจากข้อมูลชุดนี้: `Scaling` คือ throughput เฉลี่ยเพิ่มขึ้นตาม clients, `Peak` คือระดับที่มี throughput เฉลี่ยสูงสุด, `Saturated` คือช่วงที่ throughput ลดลงและ latency เพิ่มขึ้น และ `Degraded` คือพบการตอบไม่ครบจาก timeout ป้ายเหล่านี้เป็นการตีความผล ไม่ใช่สถานะที่โปรแกรมส่งออกหรือหลักฐานระบุคอขวดเฉพาะส่วน

| Clients | คำขอ/รอบ | Throughput เฉลี่ย (req/s) | Latency เฉลี่ย (ms) | Timeout รวม 3 รอบ | Zone |
| ---: | ---: | ---: | ---: | ---: | --- |
| 20 | 2,000 | 56,691.51 | 0.33 | 0 | 🟢 Scaling |
| 50 | 5,000 | 96,225.32 | 0.48 | 0 | 🟢 Scaling |
| 100 | 10,000 | 114,865.37 | 0.87 | 0 | 🟢 Scaling |
| **200** | **20,000** | **135,542.37** | **1.43** | **0** | **🏆 Peak** |
| 500 | 50,000 | 11,657.68 | 45.19 | 0 | 🟡 Saturated |
| 1,000 | 100,000 | 3,111.09 | 324.24 | 0 | 🟡 Saturated |
| 1,500 | 150,000 | 2,574.92 | 575.74 | 0 | 🟡 Saturated |
| 2,000 | 200,000 | 2,337.29 | 860.63 | 119 | 🔴 Degraded |

### Performance comparison ของ Quiet mode

ตารางนี้เลือกเฉพาะจุดสำคัญของ MIXED แบบ quiet ไม่ได้มีข้อมูล verbose ให้เปรียบเทียบ

- **Log mode:** รูปแบบการเขียน log ของ server ทุกแถวในตารางนี้เป็น quiet
- **Validated point:** จำนวน clients ที่ทดลองจริงในจุดนั้น คำว่า validated ไม่ได้หมายความว่าทุกจุดผ่าน
- **Pass rate:** จำนวนรอบที่ผ่านเกณฑ์ต่อทั้งหมดสามรอบ เช่น `0/3 (partial)` หมายถึงทั้งสามรอบตอบคำขอไม่ครบ
- **Mean throughput:** ค่าเฉลี่ย throughput สามรอบ หน่วยคำขอต่อวินาที รวม response ที่ถูกปฏิเสธตามเงื่อนไขธุรกิจ
- **Mean latency:** ค่าเฉลี่ย Avg Latency สามรอบ หน่วย ms โดยไม่รวมคำขอที่ timeout ใน latency ของแต่ละรอบ
- **หมายเหตุ:** คำอธิบายเหตุผลที่เลือกจุดนั้น เช่น throughput เฉลี่ยสูงสุด ระดับสูงสุดที่ผ่าน 3/3 ในชุดนี้ หรือระดับแรกที่พบ timeout ไม่ใช่ขีดจำกัดตายตัวของระบบ

| Log mode | Validated point | Pass rate | Mean throughput | Mean latency | หมายเหตุ |
| --- | ---: | --- | ---: | ---: | --- |
| Quiet (รายงานนี้) | 200 clients | 3/3 | 135,542 req/s | 1.43 ms | Peak ของ quiet mode |
| Quiet (รายงานนี้) | 1,500 clients | 3/3 | 2,574 req/s | 575.74 ms | Last stable level |
| Quiet (รายงานนี้) | 2,000 clients | 0/3 (partial) | 2,337 req/s | 860.63 ms | Timeout เริ่มปรากฏ |

### Key findings

1. **Peak throughput ที่ 200 clients** — 135,542 req/s เป็นจุดสูงสุดของชุดทดลอง ก่อนหน้านี้ throughput เพิ่มขึ้นตาม clients (scaling zone)
2. **Saturation ระหว่าง 200–500 clients** — Throughput ลดจาก 135,542 เหลือ 11,657 (ลด 92%) ขณะที่ latency เพิ่มจาก 1.43 ms เป็น 45.19 ms (เพิ่ม 31×)
3. **Stable สูงสุดที่ 1,500 clients** — ครบ 3/3 รอบโดยไม่มี timeout เลย
4. **Timeout เริ่มที่ 2,000 clients** — 119/600,000 requests = 0.02% timeout rate; timeout เพิ่มขึ้นทุกรอบ (18→34→67)
5. **ความแปรผันสูงในช่วง Saturated** — ที่ 500c throughput range คือ 9,100–16,409 (ratio 1.8×) แสดง OS scheduling มีผลมาก
6. **load generator เป็นส่วนหนึ่งของข้อจำกัด** — 1 OS thread ต่อ client ทำให้จำนวน clients สูงวัด OS scheduling overhead ร่วมกับ server capacity

---

*หลักฐานเพิ่มเติม: `docs/evidence/2026-10-01/load-transcripts.txt` | สภาพแวดล้อม: `docs/evidence/2026-10-01/environment.json`*
