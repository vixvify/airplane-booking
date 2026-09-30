# รายงานผลการทดสอบ Load Test

> ผลย้อนหลังจากวันที่ 2026-09-29: ชุดทดสอบนี้ยังใช้ shared response queue จึงไม่ควรนำตัวเลขไปอ้างว่าเป็น throughput ของ architecture ปัจจุบันที่ใช้ private reply queues ดูผังปัจจุบันใน [architecture.md](architecture.md)

## Airplane Reservation System

**วันที่ทดสอบ:** 2026-09-29  
**สภาพแวดล้อม:** Linux Container (`gcc:14-bookworm`, Docker Desktop บน Windows, AMD64)  
**Server:** `./server sync 3`  
**Load Generator:** 1 Logical Client = 1 OS Thread (`std::thread`)  
**Workload:** `MIXED` — RESERVE และ CANCEL สลับกัน โดยเลือกที่นั่ง 1–20 แบบ Round-robin  
**จำนวนรอบ:** 3 Fresh Runs ต่อระดับ Client

---

## 1. Test Environment

การทดสอบนี้ใช้สภาพแวดล้อมดังต่อไปนี้

- **Operating System:** Linux บน Docker Container ผ่าน WSL2 / Docker Desktop
- **CPU Architecture:** x86_64
- **IPC:** System V Message Queues
  - Request Key: `0x4153bb35`
  - Response Key: `0x4253bb35`
- **Server Mode:** `sync`
- **Server Workers:** 3 Threads
- **Race Delay:** `AIRPLANE_RACE_DELAY=off`
- **Log Mode:** `AIRPLANE_LOG_MODE=quiet`
- **Load Test Program:** `src/benchmark/load_test.cpp`
- **Load Generator Model:** 1 Logical Client = 1 `std::thread`
- **Requests per Client:** 100 Requests
- **Request Timeout:** 10 วินาที

การทดสอบปิด Artificial Race Delay และ Detailed Logging เพื่อไม่ให้เวลาหน่วงที่ใช้สำหรับสาธิต Race Condition หรือการเขียน Log มีผลต่อผลการวัด Performance

---

## 2. Test Methodology

Load Test ใช้รูปแบบที่เรียบง่าย โดยสร้าง OS Thread หนึ่งตัวต่อหนึ่ง Logical Client

```text
1 Logical Client
      │
      ▼
1 std::thread
      │
      ├── Send Request
      │
      ├── Wait for Response
      │
      └── Send Next Request
```

Client แต่ละตัวส่งทั้งหมด 100 Requests โดย Request ถัดไปจะถูกส่งหลังจาก Request ก่อนหน้าได้รับ Response หรือสิ้นสุดด้วย Error/Timeout แล้ว

ก่อนเริ่มทดสอบ Client Threads ทั้งหมดจะรอที่ Start Gate เพื่อให้เริ่มทำงานในช่วงเวลาใกล้เคียงกัน และลดความคลาดเคลื่อนจากการสร้าง Thread ทีละตัว

ลำดับการทำงานของ Request แต่ละรายการคือ

```text
Start Timer
    ↓
msgsnd()
    ↓
Request successfully sent
    ↓
Increment Actual In-Flight
    ↓
Wait for matching response
    ↓
msgrcv()
    ↓
Decrement Actual In-Flight
    ↓
Stop Timer
    ↓
Record Result and Latency
```

แต่ละระดับ Client ทดสอบทั้งหมด 3 Fresh Runs โดยเริ่ม Server ใหม่ก่อนแต่ละรอบ เพื่อให้สถานะของระบบและที่นั่งเริ่มต้นจากสภาวะเดียวกัน

### PASS Criteria

การทดสอบถือว่า **PASS** เมื่อ

- Requests ทำงานครบตามจำนวนที่กำหนด
- ไม่มี Timeout
- ไม่มี Transport Error
- ไม่มี Thread Creation หรือ Setup Error

Business Rejection เช่น การจองที่นั่งที่ถูกจองแล้ว หรือการยกเลิกที่ไม่สามารถทำได้ตามเงื่อนไขของระบบ ถือเป็น Response ที่ Server ประมวลผลและตอบกลับเรียบร้อย จึงไม่ถือเป็น Transport Failure

---

## 3. Metric Definitions

เพื่อป้องกันความสับสนระหว่างจำนวน Client จำนวน Request ที่กำลังรอ และจำนวนงานที่ Server ประมวลผลพร้อมกัน รายงานนี้แยก Metric ออกเป็นดังนี้

### 3.1 Logical Clients

จำนวน Client ที่ Load Generator จำลองขึ้นมา โดยแต่ละ Logical Client ใช้ OS Thread หนึ่งตัว

ตัวอย่าง:

```text
200 Logical Clients = 200 Client Threads
```

Logical Clients ไม่ได้หมายความว่า Server กำลังประมวลผล 200 Requests พร้อมกัน

### 3.2 Actual In-Flight Requests

Request จะถูกนับเป็น **Actual In-Flight** เมื่อ `msgsnd()` ส่ง Request เข้า System V IPC สำเร็จแล้ว แต่ยังไม่ได้รับ Matching Response กลับมา

```text
msgsnd() success
      │
      ├──── Actual In-Flight ────┐
      │                           │
      └──────────────────────> Response received
                                  │
                                  ▼
                           Remove from In-Flight
```

เก็บ Metric สองค่า ได้แก่

- **Peak In-Flight:** จำนวน In-Flight สูงสุดที่พบระหว่างการทดสอบ
- **Average In-Flight:** ค่าเฉลี่ยของจำนวน In-Flight ระหว่างการทดสอบ

Request ที่ยังส่งเข้า IPC ไม่สำเร็จจะไม่ถูกนับเป็น Actual In-Flight

### 3.3 Server Worker Parallelism

Server ใช้ Worker Threads จำนวน 3 ตัว ดังนั้น Server สามารถมี Worker ที่กำลังประมวลผล Request ได้พร้อมกันสูงสุด 3 ตัว

ค่านี้แตกต่างจาก Actual In-Flight เนื่องจาก Request ที่เป็น In-Flight อาจกำลังรออยู่ใน IPC หรือรอ Response และไม่ได้หมายความว่าทุก Request กำลัง Execute บน CPU พร้อมกัน

### 3.4 Throughput

Throughput คำนวณจาก

```text
Throughput = Completed Requests / Total Duration
```

หน่วยเป็น Requests per Second (`req/s`)

### 3.5 Latency

Latency วัดเวลาของ Request-Response Cycle ตั้งแต่ก่อนเริ่มส่ง Request จนกระทั่งได้รับ Response หรือ Request สิ้นสุดลง

รายงานประกอบด้วย

- Average Latency
- p95 Latency
- p99 Latency
- Maximum Latency

---

## 4. Client Scaling Results

ผลการทดสอบจริงจาก 3 Fresh Runs ในแต่ละระดับ Client มีดังนี้

|   Clients | Run | Completed | Business Rejection | Error / Timeout | Peak In-Flight | Avg In-Flight | Duration (s) | Throughput (req/s) | Avg Latency (ms) | p95 (ms) | p99 (ms) | Max (ms) |  Result  |
| --------: | --: | --------: | -----------------: | --------------: | -------------: | ------------: | -----------: | -----------------: | ---------------: | -------: | -------: | -------: | :------: |
|    **20** |   1 |     2,000 |                548 |               0 |             20 |         14.28 |        0.023 |           88,339.9 |             0.21 |     0.32 |     0.61 |     0.84 | **PASS** |
|           |   2 |     2,000 |                456 |               0 |             20 |         15.74 |        0.020 |           99,890.0 |             0.19 |     0.26 |     0.40 |     0.86 | **PASS** |
|           |   3 |     2,000 |                498 |               0 |             20 |         16.07 |        0.020 |           97,910.9 |             0.19 |     0.25 |     0.31 |     0.41 | **PASS** |
|    **50** |   1 |     5,000 |              2,690 |               0 |             50 |         16.43 |        0.028 |          177,660.2 |             0.26 |     0.64 |     1.20 |     2.23 | **PASS** |
|           |   2 |     5,000 |              2,656 |               0 |             50 |         33.18 |        0.021 |          234,715.0 |             0.20 |     0.29 |     0.56 |     0.84 | **PASS** |
|           |   3 |     5,000 |              2,768 |               0 |             50 |         15.15 |        0.021 |          243,344.8 |             0.19 |     0.27 |     0.33 |     0.56 | **PASS** |
|   **100** |   1 |    10,000 |              6,956 |               0 |            100 |         50.51 |        0.033 |          306,384.6 |             0.28 |     0.47 |     0.81 |     8.30 | **PASS** |
|           |   2 |    10,000 |              7,032 |               0 |            100 |         26.09 |        0.026 |          378,483.2 |             0.23 |     0.41 |     0.58 |     2.75 | **PASS** |
|           |   3 |    10,000 |              6,990 |               0 |            100 |         33.90 |        0.040 |          249,430.0 |             0.34 |     0.53 |     1.02 |     8.46 | **PASS** |
|   **200** |   1 |    20,000 |             16,444 |               0 |            200 |         49.85 |        0.053 |          378,864.8 |             0.48 |     0.94 |     1.50 |     6.96 | **PASS** |
|           |   2 |    20,000 |             16,452 |               0 |            196 |         77.40 |        0.049 |      **406,350.2** |             0.43 |     0.77 |     1.11 |     4.73 | **PASS** |
|           |   3 |    20,000 |             16,570 |               0 |            195 |         81.97 |        0.070 |          286,944.4 |             0.62 |     1.23 |     1.80 |    12.38 | **PASS** |
|   **500** |   1 |    50,000 |             45,186 |               0 |            291 |         39.10 |        0.442 |          113,240.3 |             4.19 |    13.33 |    22.63 |    93.12 | **PASS** |
|           |   2 |    50,000 |             45,318 |               0 |            300 |         55.11 |        0.770 |           64,963.1 |             7.42 |    29.13 |    51.89 |   127.75 | **PASS** |
|           |   3 |    50,000 |             45,078 |               0 |            197 |         60.03 |        0.446 |          112,204.5 |             4.16 |    11.80 |    19.36 |   365.35 | **PASS** |
| **1,000** |   1 |   100,000 |             95,286 |               0 |            318 |        119.37 |       10.728 |            9,321.7 |           105.12 |   415.52 |   702.82 | 1,879.68 | **PASS** |
|           |   2 |   100,000 |             95,422 |               0 |            320 |         98.11 |       13.868 |            7,210.9 |           135.44 |   481.08 |   793.84 | 2,907.69 | **PASS** |
|           |   3 |   100,000 |             95,378 |               0 |            320 |        109.87 |       14.768 |            6,771.4 |           145.31 |   522.93 |   855.81 | 2,211.28 | **PASS** |
| **1,500** |   1 |   150,000 |            145,328 |               0 |            327 |         96.36 |       38.062 |            3,941.0 |           369.12 | 1,287.13 | 2,123.42 | 6,563.38 | **PASS** |
|           |   2 |   150,000 |            145,176 |               0 |            325 |         98.91 |       38.363 |            3,910.0 |           371.41 | 1,324.72 | 2,137.28 | 6,624.39 | **PASS** |
|           |   3 |   150,000 |            145,220 |               0 |            325 |         98.96 |       40.610 |            3,693.6 |           394.67 | 1,374.55 | 2,286.15 | 7,506.11 | **PASS** |
| **2,000** |   1 |   199,988 |            195,240 |     12 Timeouts |            324 |        100.62 |       75.465 |            2,650.1 |           730.82 | 2,423.86 | 3,991.47 | 9,647.24 | **FAIL** |
|           |   2 |   199,974 |            194,986 |     26 Timeouts |            324 |        101.82 |       75.941 |            2,633.3 |           739.02 | 2,409.34 | 3,987.58 | 9,985.17 | **FAIL** |
|           |   3 |   199,985 |            195,293 |     15 Timeouts |            326 |         98.99 |       73.664 |            2,714.8 |           715.64 | 2,372.81 | 3,856.32 | 9,844.47 | **FAIL** |

---

## 5. Summary Results

| Logical Clients | Completed Requests | Avg Throughput (req/s) | Avg Latency |     Avg p95 |     Avg p99 | Highest Peak In-Flight | Avg In-Flight | Successful Runs |
| --------------: | -----------------: | ---------------------: | ----------: | ----------: | ----------: | ---------------------: | ------------: | :-------------: |
|          **20** |      2,000 / 2,000 |               95,380.2 |     0.20 ms |     0.28 ms |     0.44 ms |                     20 |         15.36 |    **3 / 3**    |
|          **50** |      5,000 / 5,000 |              218,573.3 |     0.22 ms |     0.40 ms |     0.70 ms |                     50 |         21.59 |    **3 / 3**    |
|         **100** |    10,000 / 10,000 |              311,432.6 |     0.28 ms |     0.47 ms |     0.80 ms |                    100 |         36.83 |    **3 / 3**    |
|         **200** |    20,000 / 20,000 |          **357,386.5** |     0.51 ms |     0.98 ms |     1.47 ms |                    200 |         69.74 |    **3 / 3**    |
|         **500** |    50,000 / 50,000 |               96,802.6 |     5.26 ms |    18.09 ms |    31.29 ms |                    300 |         51.41 |    **3 / 3**    |
|       **1,000** |  100,000 / 100,000 |                7,768.0 |   128.62 ms |   473.18 ms |   784.16 ms |                    320 |        109.12 |    **3 / 3**    |
|       **1,500** |  150,000 / 150,000 |                3,848.2 |   378.40 ms | 1,328.80 ms | 2,182.28 ms |                **327** |         98.08 |    **3 / 3**    |
|       **2,000** |  199,982 / 200,000 |                2,666.1 |   728.49 ms | 2,402.00 ms | 3,945.12 ms |                    326 |        100.48 |    **0 / 3**    |

---

## 6. Throughput Analysis

Throughput เพิ่มขึ้นตามจำนวน Client ในช่วงแรก โดยมีค่าเฉลี่ยดังนี้

```text
20 clients      95,380 req/s
50 clients     218,573 req/s
100 clients    311,433 req/s
200 clients    357,387 req/s
500 clients     96,803 req/s
1000 clients     7,768 req/s
1500 clients     3,848 req/s
2000 clients     2,666 req/s
```

ค่า Throughput เฉลี่ยสูงที่สุดอยู่ที่ **200 Logical Clients** เท่ากับ **357,386.5 req/s**

สำหรับผลราย Run ค่า Throughput สูงที่สุดที่วัดได้คือ **406,350.2 req/s** จาก Run 2 ของการทดสอบ 200 Clients

เมื่อเพิ่มจำนวน Client จาก 20 เป็น 200 ตัว Throughput เพิ่มขึ้นอย่างต่อเนื่อง แสดงให้เห็นว่า Server สามารถใช้ Load ที่เพิ่มขึ้นเพื่อประมวลผล Request ได้มากขึ้นในช่วงดังกล่าว

หลังจาก 200 Clients ค่า Throughput เริ่มลดลงอย่างชัดเจน โดยเฉพาะตั้งแต่ 500–2,000 Clients

อย่างไรก็ตาม ไม่ควรตีความการลดลงนี้ว่าเป็นขีดจำกัดของ Server เพียงอย่างเดียว เนื่องจาก Load Generator ใช้โมเดล 1 Client = 1 OS Thread และทำงานในสภาพแวดล้อมเดียวกับ Server ดังนั้น OS Thread Scheduling, Context Switching, IPC Contention และการแย่งใช้ทรัพยากรของเครื่องทดสอบอาจมีผลต่อค่าที่วัดได้ด้วย

---

## 7. Latency Analysis

Latency อยู่ในระดับต่ำในช่วง 20–200 Clients

| Clients | Average Latency |     p95 |     p99 |
| ------: | --------------: | ------: | ------: |
|      20 |         0.20 ms | 0.28 ms | 0.44 ms |
|      50 |         0.22 ms | 0.40 ms | 0.70 ms |
|     100 |         0.28 ms | 0.47 ms | 0.80 ms |
|     200 |         0.51 ms | 0.98 ms | 1.47 ms |

หลังจากเพิ่มจำนวน Client เป็น 500 ตัวขึ้นไป Latency เพิ่มขึ้นอย่างชัดเจน

ที่ 500 Clients ค่า Average Latency เพิ่มเป็น **5.26 ms** และ p99 เท่ากับ **31.29 ms**

ที่ 1,000 Clients ค่า Average Latency เพิ่มเป็น **128.62 ms** และ p99 เท่ากับ **784.16 ms**

ที่ 1,500 Clients ค่า Average Latency เท่ากับ **378.40 ms** และ p99 เท่ากับ **2,182.28 ms**

ที่ 2,000 Clients ค่า Average Latency เพิ่มเป็น **728.49 ms** และ p99 เท่ากับ **3,945.12 ms** โดย Maximum Latency ของบาง Request เข้าใกล้ Timeout Limit 10 วินาที

ผลดังกล่าวสอดคล้องกับการลดลงของ Throughput เมื่อจำนวน Client สูงขึ้น

---

## 8. Actual In-Flight Requests

Actual In-Flight ใช้แสดงจำนวน Request ที่ส่งเข้าสู่ IPC สำเร็จแล้ว แต่ยังไม่ได้รับ Response กลับมา

ผล Peak In-Flight สูงสุดของแต่ละระดับเป็นดังนี้

| Logical Clients | Highest Peak Actual In-Flight |
| --------------: | ----------------------------: |
|              20 |                            20 |
|              50 |                            50 |
|             100 |                           100 |
|             200 |                           200 |
|             500 |                           300 |
|           1,000 |                           320 |
|           1,500 |                       **327** |
|           2,000 |                           326 |

ในช่วง 20–200 Clients ค่า Peak In-Flight เพิ่มขึ้นตามจำนวน Logical Clients

เมื่อเพิ่มเป็น 500 Clients ขึ้นไป ค่า Peak In-Flight เริ่มอยู่ในช่วงประมาณ **300–327 Requests** และไม่เพิ่มขึ้นตามจำนวน Client ในอัตราเดียวกับช่วงแรก

ค่ามากที่สุดที่สังเกตได้จากการทดสอบทั้งหมดคือ

> **Maximum Observed Peak Actual In-Flight = 327 Requests**

ค่านี้หมายถึงจำนวน Actual In-Flight สูงที่สุดที่พบในชุดการทดสอบนี้เท่านั้น ไม่ได้หมายความว่า 327 Requests เป็นขีดจำกัดสูงสุดของ Server หรือ System V Message Queue

ระบบมีข้อจำกัดและปัจจัยหลายส่วนที่อาจส่งผลต่อจำนวน In-Flight ที่เกิดขึ้น เช่น ความจุของ System V Message Queue, อัตราการรับ Request ของ Server, อัตราการส่ง Response และการ Scheduling ของ Client Threads

ดังนั้นผลนี้ควรใช้เพื่ออธิบายพฤติกรรมที่สังเกตได้จากการทดสอบ มากกว่าการใช้เป็นค่าขีดจำกัดทางกายภาพของระบบ

---

## 9. First Observed Failure Point

การทดสอบตั้งแต่ **20 ถึง 1,500 Logical Clients** ผ่านครบทั้ง 3 Runs โดยไม่มี Timeout หรือ Transport Error

ที่ **2,000 Logical Clients** เริ่มพบ Timeout เป็นครั้งแรก

| Run | Planned Requests | Completed | Timeouts | Completion Rate |
| --: | ---------------: | --------: | -------: | --------------: |
|   1 |          200,000 |   199,988 |       12 |         99.994% |
|   2 |          200,000 |   199,974 |       26 |         99.987% |
|   3 |          200,000 |   199,985 |       15 |         99.993% |

ดังนั้นสามารถระบุได้ว่า

> **First Observed Failure Point = 2,000 Logical Clients**

Failure ที่พบเป็น Response Timeout เมื่อ Request-Response Cycle ใช้เวลานานเกิน Timeout Limit 10 วินาที

ผลนี้ไม่ได้หมายความว่า Server รองรับได้สูงสุด 1,999 Clients หรือมี Hard Limit ที่ 2,000 Clients แต่หมายความว่า ภายใต้สภาพแวดล้อม Workload และ Timeout Policy ที่ใช้ในการทดสอบนี้ เริ่มพบ Timeout ที่ระดับ 2,000 Logical Clients

---

## 10. Load Generator Limitations

Load Generator ใช้โมเดล

```text
1 Logical Client = 1 OS Thread
```

ข้อดีของรูปแบบนี้คือโครงสร้างเรียบง่าย และแต่ละ Client มีพฤติกรรมใกล้เคียงกับ Client ที่ส่ง Request แล้วรอ Response ก่อนส่ง Request ถัดไป

อย่างไรก็ตาม เมื่อจำนวน Client เพิ่มขึ้นมาก จำนวน OS Threads ก็เพิ่มขึ้นตามโดยตรง

ตัวอย่างเช่น

```text
200 clients   = 200 threads
500 clients   = 500 threads
1000 clients  = 1000 threads
1500 clients  = 1500 threads
2000 clients  = 2000 threads
```

เมื่อมี Threads จำนวนมาก ผลการทดสอบไม่ได้สะท้อนเฉพาะ Performance ของ Server แต่รวมถึง Overhead จาก Load Generator และระบบปฏิบัติการด้วย เช่น

- Thread Scheduling
- Context Switching
- CPU Contention
- System V IPC Contention
- Memory และ Thread Stack Overhead

ในการทดสอบนี้สามารถสร้าง Client Threads ได้ครบถึง 2,000 Threads โดยไม่พบ Thread Creation Failure

อย่างไรก็ตาม ตั้งแต่ประมาณ 500 Clients ขึ้นไป Throughput ลดลงและ Latency เพิ่มขึ้นอย่างมาก ขณะที่ Peak Actual In-Flight ไม่เพิ่มขึ้นตามจำนวน Client

ดังนั้นผลในช่วง Client จำนวนสูงควรตีความโดยคำนึงถึงข้อจำกัดของ Load Generator ร่วมด้วย และไม่ควรใช้ผลดังกล่าวเพื่อสรุป Hard Limit ของ Server โดยตรง

---

## 11. Conclusion

จากการทดสอบ Load Test ด้วยโมเดล 1 Logical Client = 1 OS Thread และทดสอบ 3 Fresh Runs ต่อระดับ สามารถสรุปผลที่วัดได้ดังนี้

| Metric                                     |              Result | Interpretation                                                 |
| ------------------------------------------ | ------------------: | -------------------------------------------------------------- |
| **Highest Single-Run Throughput**          | **406,350.2 req/s** | พบที่ 200 Logical Clients                                      |
| **Highest Average Throughput**             | **357,386.5 req/s** | ค่าเฉลี่ย 3 Runs ที่ 200 Logical Clients                       |
| **Maximum Tested Clients with 3/3 PASS**   |   **1,500 Clients** | Requests ครบทั้งหมดโดยไม่มี Timeout หรือ Transport Error       |
| **Maximum Observed Peak Actual In-Flight** |    **327 Requests** | ค่าสูงสุดที่สังเกตได้จากชุดการทดสอบ ไม่ใช่ Hard Limit          |
| **First Observed Failure Point**           |   **2,000 Clients** | เริ่มพบ Response Timeout ภายใต้ Timeout Limit 10 วินาที        |
| **Server Worker Parallelism**              |       **3 Workers** | Server มี Worker Threads สำหรับประมวลผล Request พร้อมกัน 3 ตัว |

ผลการทดสอบแสดงให้เห็นว่า Throughput เพิ่มขึ้นตามจำนวน Client จนถึงช่วงประมาณ 200 Clients ก่อนที่จะเริ่มลดลงเมื่อจำนวน Client สูงขึ้น ขณะเดียวกัน Latency เพิ่มขึ้นอย่างชัดเจนตั้งแต่ 500 Clients เป็นต้นไป

ระบบผ่านการทดสอบครบทั้ง 3 Runs จนถึง **1,500 Logical Clients** และเริ่มพบ Timeout ที่ **2,000 Logical Clients**

จำนวน Actual In-Flight สูงที่สุดที่สังเกตได้คือ **327 Requests** อย่างไรก็ตาม ค่านี้ไม่ควรถูกตีความว่าเป็น Maximum Concurrency หรือ Hard Limit ของ Server เนื่องจากผลการทดสอบยังได้รับอิทธิพลจาก System V IPC, Load Generator และ OS Thread Scheduling

ดังนั้นผลที่เหมาะสมสำหรับรายงานคือ ระบบถูก **ทดสอบและยืนยันว่า Load Test ผ่านถึง 1,500 Logical Clients ภายใต้ Configuration นี้** โดยมี Throughput สูงสุดราย Run **406,350.2 req/s**, Peak Actual In-Flight ที่สังเกตได้สูงสุด **327 Requests** และเริ่มพบ Timeout ที่ระดับ **2,000 Logical Clients** ภายใต้ Timeout Policy 10 วินาที
