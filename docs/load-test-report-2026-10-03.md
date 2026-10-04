# Load Test: เพิ่มโหลดจนพบความผิดพลาด — 3 ตุลาคม 2026

เริ่ม 03/10/2026 20:53:53 เวลาไทย (UTC+7) · สิ้นสุด 03/10/2026 21:02:02


ทดสอบ MIXED โดยวางแผน Reserve:Cancel = **1:1** สองชุด: (1) เพิ่ม clients และ requests ต่อ client พร้อมกัน เริ่ม 50×50 (2) คง clients = 100 แล้วเพิ่ม requests ต่อ client เริ่ม 100 ชุดที่ 1 เพิ่มเป็นสองเท่า; ชุดที่ 2 เพิ่มเป็นสองเท่าจน R = 6,553,600 แล้วเพิ่ม R ทีละ 1,000,000 ตามการปรับแผนของผู้ใช้ แต่ละระดับเริ่ม server/container ใหม่ รอบที่ขาดการเชื่อมต่อกับ Docker เก็บไว้แยกและรันซ้ำเฉพาะระดับที่ยังไม่ได้ผลสรุป ค่าด้านล่างเป็นผลวัดจริงรายรอบ ไม่ใช่ค่าเฉลี่ยจากหลายรอบ

## สรุปผล

| ชุด | ระดับผ่านล่าสุด C × R | ระดับแรกที่พบ boom C × R | เหตุที่หยุด / สถานะ | Server หลัง boom |
| --- | --- | --- | --- | --- |
| 1: เพิ่ม C และ R | [400 × 400](evidence/2026-10-03/scale-both-c400-r400/output.log) | [800 × 800](evidence/2026-10-03/scale-both-c800-r800/output.log) | Timeout 771 ครั้ง | ยังทำงานและตอบ LIST ได้ |
| 2: คง C = 100 | [100 × 204,800](evidence/2026-10-03/fixed-100-c100-r204800/output.log) | [100 × 409,600](evidence/2026-10-03/fixed-100-c100-r409600/output.log) | ตรวจสอบ exit 124 และ log | ยังทำงานและตอบ LIST ได้ |

**Boom** includes a request timeout, transport/setup failure, server failure, or reaching the 120-second whole-run limit. The 120-second limit counts as the stopping threshold for this load-test progression even when request-level timeouts and transport errors are zero. Business rejection (for example, a full seat) is not boom. ไม่รวม business rejection เช่น ที่นั่งถูกจองแล้วหรือผู้ยกเลิกไม่ใช่เจ้าของ และไม่ใช้ throughput ที่ลดลงอย่างเดียวเป็นเกณฑ์ ระดับแรกที่พบปัญหาเป็นผลของขั้นโหลดที่ทดลอง ยังไม่ใช่ขีดจำกัดขั้นต่ำที่พิสูจน์แน่นอน

**เทียบที่งานรวมตามแผนเท่ากัน 640,000 คำขอ:** [800 × 800](evidence/2026-10-03/scale-both-c800-r800/output.log) พบความผิดพลาด แต่ [100 × 6,400](evidence/2026-10-03/fixed-100-c100-r6400/output.log) ตอบครบ ผลนี้แสดงว่าจำนวนคำขอรวมอย่างเดียวอธิบายจุด boom ไม่ได้ ต้องพิจารณา concurrency และรูปแบบการส่งคำขอด้วย โดยยังมีความแปรปรวนจากการรันครั้งเดียวในแต่ละระดับ

## การตั้งค่าและวิธีทดลอง

- Docker 29.7.2 (Docker Desktop); Linux `6.18.33.1-microsoft-standard-WSL2`; 12 CPUs, RAM ของ Docker VM 15.58 GiB; `x86_64`
- Source commit `36b48dec133a65221d1cf916c34c500d0e6f6434`; branch `docs/update-report`; working tree มีงานค้างตามรายการใน environment.json
- Image ที่ตรึงตลอดการทดลอง: `sha256:d11a4bd5a007e3a10f170f9bc46895a176c3f467ddd2b56b3a5d424979686cbb`
- Server `sync`, 3 workers, 20 ที่นั่ง, logging `quiet`, `AIRPLANE_RACE_DELAY=off`; ไม่ได้กำหนด CPU/RAM quota เพิ่มให้ container
- 1 client = 1 OS thread และ 1 private reply queue; ทุก thread รอ start gate จากนั้นส่งทีละคำขอและรอ response ก่อนส่งครั้งถัดไป (closed loop)
- ส่ง RESERVE → CANCEL สลับเป็นคู่ไปที่ที่นั่งเดียวกัน จากนั้นเลื่อนไปที่นั่งถัดไปแบบ round-robin 1–20; requests ต่อ client ทุกระดับเป็นเลขคู่ จึงมีอัตราส่วน **ที่วางแผน** 1:1 พอดี
- Per-request timeout: 10 seconds. Whole-run deadline: 120 seconds from benchmark start, including client setup; reaching it ends the run with exit code `124` and counts as BOOM for this progression.
- รันสำเนา benchmark ที่เพิ่มการหยุดส่งงานใหม่เมื่อเกิด transport/setup error ครั้งแรก คำขอที่กำลังรอคำตอบยังรอจนเสร็จหรือ timeout ดังนั้นรอบ boom อาจมี timeout มากกว่า 1 ครั้ง requests ที่ยังไม่ได้เริ่มถูกนับเป็น Skipped และสัดส่วนที่รันจริงในรอบนั้นอาจไม่ครบ 1:1
- ไม่แก้ไฟล์ application ใน `src/` หรือ image เดิม; เก็บ [diff ของสำเนา benchmark](evidence/2026-10-03/failfast.patch), [source ต้นฉบับ](evidence/2026-10-03/load_test.original.cpp), [source ที่ใช้](evidence/2026-10-03/load_test.failfast.cpp) และ hash ของ binary ใน [environment.json](evidence/2026-10-03/environment.json)
- สุ่มเก็บ Docker CPU/RAM ทุกประมาณ 30 วินาทีในรอบที่ยาว; generator และ server ใช้ทรัพยากรเครื่องร่วมกัน การตรวจทรัพยากรและ workload อื่นบนเครื่องอาจกระทบผล จึงไม่ใช่ค่าประสิทธิภาพของ server เพียงอย่างเดียว

## วิธีอ่านตาราง

- **C × R** = จำนวน clients × requests ต่อ client; คลิกเพื่อเปิด raw output ของรอบนั้น
- **Planned** = C × R; **Completed** = ได้รับ response แล้ว รวมทั้งสำเร็จและ business rejection
- **Timeout** = เกินเวลารอส่ง/รับ; **Other error** = transport error ที่ไม่ใช่ timeout; **Skipped** = คำขอตามแผนที่ยังไม่ได้รันเมื่อหยุด ทั้งสามค่านี้แยกกัน ไม่ได้นับซ้ำ
- **OK / Reject** = การจองหรือยกเลิกสำเร็จ / ถูกปฏิเสธตามกติกา; OK + Reject = Completed และ Completed + Timeout + Other error + Skipped = Planned ในรอบที่มีผลสรุป
- **Time (s)** = เวลาตั้งแต่เปิด start gate จน client threads จบ ไม่รวมสร้าง threads หรือสรุป latency **Throughput (req/s)** = Completed ÷ เวลาจริงก่อนปัดเศษ รวม response ที่เป็น Reject ด้วย
- **Avg / p95 / p99 / Max (ms)** = ค่าเฉลี่ย, percentile 95, percentile 99 และค่าสูงสุดของ latency วัดก่อนส่งถึงรับ response สำเร็จ ไม่รวม timeout หรือ Skipped; percentile ใช้อันดับตาม benchmark เดิม
- **Peak / Avg in-flight** = จำนวนคำขอหลังส่งสำเร็จที่ยังรอคำตอบหรือยังไม่สิ้นสุดการรอ ค่าสูงสุด / ค่าเฉลี่ยจากการสุ่มประมาณทุก 100 µs; ไม่ใช่จำนวน workers และไม่รวมคำขอที่ยังรอส่ง
- **PASS** = ตอบครบ ไม่มี transport failure และ server ยังตอบ LIST ได้; **BOOM** = เข้าเกณฑ์ข้างต้น; **HARNESS_ERROR** = ตัวรัน/การเชื่อมต่อ Docker สะดุด ยังยืนยัน server boom ไม่ได้; **PLAN_CHANGED** = ยุติตามคำสั่งปรับขั้นโหลด ไม่ใช่ความผิดพลาดของ server; **—** = ไม่มีค่าที่วัดได้ ไม่ใช่ศูนย์

## ชุดที่ 1 — เพิ่ม clients และ requests ต่อ client พร้อมกัน

### การตอบครบและความผิดพลาด

| C × R | Planned | Completed | Timeout | Other error | Skipped | ผล |
| --- | --- | --- | --- | --- | --- | --- |
| [50 × 50](evidence/2026-10-03/scale-both-c50-r50/output.log) | 2,500 | 2,500 | 0 | 0 | 0 | PASS |
| [100 × 100](evidence/2026-10-03/scale-both-c100-r100/output.log) | 10,000 | 10,000 | 0 | 0 | 0 | PASS |
| [200 × 200](evidence/2026-10-03/scale-both-c200-r200/output.log) | 40,000 | 40,000 | 0 | 0 | 0 | PASS |
| [400 × 400](evidence/2026-10-03/scale-both-c400-r400/output.log) | 160,000 | 160,000 | 0 | 0 | 0 | PASS |
| [800 × 800](evidence/2026-10-03/scale-both-c800-r800/output.log) | 640,000 | 496,549 | 771 | 0 | 142,680 | BOOM |

### ผลการจอง/ยกเลิกและอัตราการตอบกลับ

| C × R | OK | Reject | Time (s) | Throughput (req/s) |
| --- | --- | --- | --- | --- |
| [50 × 50](evidence/2026-10-03/scale-both-c50-r50/output.log) | 1,276 | 1,224 | 0.051 | 48837.33 |
| [100 × 100](evidence/2026-10-03/scale-both-c100-r100/output.log) | 2,970 | 7,030 | 0.043 | 232959.11 |
| [200 × 200](evidence/2026-10-03/scale-both-c200-r200/output.log) | 6,862 | 33,138 | 0.333 | 120278.32 |
| [400 × 400](evidence/2026-10-03/scale-both-c400-r400/output.log) | 16,046 | 143,954 | 7.114 | 22490.84 |
| [800 × 800](evidence/2026-10-03/scale-both-c800-r800/output.log) | 23,861 | 472,688 | 119.948 | 4139.69 |

### เวลาตอบกลับและคำขอที่รอคำตอบ

| C × R | Avg (ms) | p95 (ms) | p99 (ms) | Max (ms) | Peak in-flight | Avg in-flight |
| --- | --- | --- | --- | --- | --- | --- |
| [50 × 50](evidence/2026-10-03/scale-both-c50-r50/output.log) | 0.81 | 6.01 | 10.90 | 20.84 | 50 | 28.79 |
| [100 × 100](evidence/2026-10-03/scale-both-c100-r100/output.log) | 0.39 | 0.78 | 1.21 | 2.11 | 100 | 67.92 |
| [200 × 200](evidence/2026-10-03/scale-both-c200-r200/output.log) | 1.62 | 3.49 | 10.94 | 38.67 | 200 | 157.79 |
| [400 × 400](evidence/2026-10-03/scale-both-c400-r400/output.log) | 17.59 | 39.96 | 71.66 | 339.89 | 400 | 170.67 |
| [800 × 800](evidence/2026-10-03/scale-both-c800-r800/output.log) | 192.97 | 487.44 | 876.16 | 3908.48 | 800 | 181.86 |

**จุดที่พบปัญหา:** Timeout 771 ครั้ง; benchmark exit code `124`.

หลักฐานเพิ่มเติม: [สถานะ server และคำสั่งที่รัน](evidence/2026-10-03/scale-both-c800-r800/run.json), [server log](evidence/2026-10-03/scale-both-c800-r800/server.log), [LIST หลังเกิดปัญหา](evidence/2026-10-03/scale-both-c800-r800/seat-map.txt), [memory events](evidence/2026-10-03/scale-both-c800-r800/memory-events.txt)

## ชุดที่ 2 — คง 100 clients แล้วเพิ่ม requests ต่อ client

### การตอบครบและความผิดพลาด

| C × R | Planned | Completed | Timeout | Other error | Skipped | ผล |
| --- | --- | --- | --- | --- | --- | --- |
| [100 × 100](evidence/2026-10-03/fixed-100-c100-r100/output.log) | 10,000 | 10,000 | 0 | 0 | 0 | PASS |
| [100 × 200](evidence/2026-10-03/fixed-100-c100-r200/output.log) | 20,000 | 20,000 | 0 | 0 | 0 | PASS |
| [100 × 400](evidence/2026-10-03/fixed-100-c100-r400/output.log) | 40,000 | 40,000 | 0 | 0 | 0 | PASS |
| [100 × 800](evidence/2026-10-03/fixed-100-c100-r800/output.log) | 80,000 | 80,000 | 0 | 0 | 0 | PASS |
| [100 × 1,600](evidence/2026-10-03/fixed-100-c100-r1600/output.log) | 160,000 | 160,000 | 0 | 0 | 0 | PASS |
| [100 × 3,200](evidence/2026-10-03/fixed-100-c100-r3200/output.log) | 320,000 | 320,000 | 0 | 0 | 0 | PASS |
| [100 × 6,400](evidence/2026-10-03/fixed-100-c100-r6400/output.log) | 640,000 | 640,000 | 0 | 0 | 0 | PASS |
| [100 × 12,800](evidence/2026-10-03/fixed-100-c100-r12800/output.log) | 1,280,000 | 1,280,000 | 0 | 0 | 0 | PASS |
| [100 × 25,600](evidence/2026-10-03/fixed-100-c100-r25600/output.log) | 2,560,000 | 2,560,000 | 0 | 0 | 0 | PASS |
| [100 × 51,200](evidence/2026-10-03/fixed-100-c100-r51200/output.log) | 5,120,000 | 5,120,000 | 0 | 0 | 0 | PASS |
| [100 × 102,400](evidence/2026-10-03/fixed-100-c100-r102400/output.log) | 10,240,000 | 10,240,000 | 0 | 0 | 0 | PASS |
| [100 × 204,800](evidence/2026-10-03/fixed-100-c100-r204800/output.log) | 20,480,000 | 20,480,000 | 0 | 0 | 0 | PASS |
| [100 × 409,600](evidence/2026-10-03/fixed-100-c100-r409600/output.log) | 40,960,000 | 28,013,693 | 0 | 0 | 12,946,307 | BOOM |

### ผลการจอง/ยกเลิกและอัตราการตอบกลับ

| C × R | OK | Reject | Time (s) | Throughput (req/s) |
| --- | --- | --- | --- | --- |
| [100 × 100](evidence/2026-10-03/fixed-100-c100-r100/output.log) | 3,096 | 6,904 | 0.072 | 139476.84 |
| [100 × 200](evidence/2026-10-03/fixed-100-c100-r200/output.log) | 5,782 | 14,218 | 0.114 | 174838.86 |
| [100 × 400](evidence/2026-10-03/fixed-100-c100-r400/output.log) | 11,742 | 28,258 | 0.298 | 134434.07 |
| [100 × 800](evidence/2026-10-03/fixed-100-c100-r800/output.log) | 23,110 | 56,890 | 0.391 | 204416.56 |
| [100 × 1,600](evidence/2026-10-03/fixed-100-c100-r1600/output.log) | 46,270 | 113,730 | 0.720 | 222100.31 |
| [100 × 3,200](evidence/2026-10-03/fixed-100-c100-r3200/output.log) | 91,988 | 228,012 | 1.454 | 220019.89 |
| [100 × 6,400](evidence/2026-10-03/fixed-100-c100-r6400/output.log) | 183,898 | 456,102 | 3.518 | 181930.16 |
| [100 × 12,800](evidence/2026-10-03/fixed-100-c100-r12800/output.log) | 366,264 | 913,736 | 6.141 | 208423.62 |
| [100 × 25,600](evidence/2026-10-03/fixed-100-c100-r25600/output.log) | 732,770 | 1,827,230 | 11.461 | 223357.93 |
| [100 × 51,200](evidence/2026-10-03/fixed-100-c100-r51200/output.log) | 1,464,972 | 3,655,028 | 22.374 | 228832.74 |
| [100 × 102,400](evidence/2026-10-03/fixed-100-c100-r102400/output.log) | 2,925,770 | 7,314,230 | 46.912 | 218283.27 |
| [100 × 204,800](evidence/2026-10-03/fixed-100-c100-r204800/output.log) | 5,852,908 | 14,627,092 | 89.050 | 229982.48 |
| [100 × 409,600](evidence/2026-10-03/fixed-100-c100-r409600/output.log) | 8,008,821 | 20,004,872 | 119.991 | 233464.18 |

### เวลาตอบกลับและคำขอที่รอคำตอบ

| C × R | Avg (ms) | p95 (ms) | p99 (ms) | Max (ms) | Peak in-flight | Avg in-flight |
| --- | --- | --- | --- | --- | --- | --- |
| [100 × 100](evidence/2026-10-03/fixed-100-c100-r100/output.log) | 0.63 | 1.35 | 1.96 | 3.75 | 100 | 71.74 |
| [100 × 200](evidence/2026-10-03/fixed-100-c100-r200/output.log) | 0.54 | 1.07 | 1.42 | 8.41 | 100 | 83.82 |
| [100 × 400](evidence/2026-10-03/fixed-100-c100-r400/output.log) | 0.72 | 1.91 | 3.53 | 8.64 | 100 | 89.20 |
| [100 × 800](evidence/2026-10-03/fixed-100-c100-r800/output.log) | 0.48 | 0.99 | 1.54 | 4.03 | 100 | 93.28 |
| [100 × 1,600](evidence/2026-10-03/fixed-100-c100-r1600/output.log) | 0.44 | 0.91 | 1.41 | 7.11 | 100 | 95.14 |
| [100 × 3,200](evidence/2026-10-03/fixed-100-c100-r3200/output.log) | 0.45 | 0.94 | 1.36 | 7.72 | 100 | 96.41 |
| [100 × 6,400](evidence/2026-10-03/fixed-100-c100-r6400/output.log) | 0.54 | 1.23 | 2.35 | 50.27 | 100 | 97.24 |
| [100 × 12,800](evidence/2026-10-03/fixed-100-c100-r12800/output.log) | 0.48 | 1.02 | 1.62 | 32.26 | 100 | 97.71 |
| [100 × 25,600](evidence/2026-10-03/fixed-100-c100-r25600/output.log) | 0.44 | 0.93 | 1.45 | 41.80 | 100 | 97.97 |
| [100 × 51,200](evidence/2026-10-03/fixed-100-c100-r51200/output.log) | 0.43 | 0.91 | 1.37 | 26.19 | 100 | 98.10 |
| [100 × 102,400](evidence/2026-10-03/fixed-100-c100-r102400/output.log) | 0.46 | 0.96 | 1.54 | 43.99 | 100 | 98.29 |
| [100 × 204,800](evidence/2026-10-03/fixed-100-c100-r204800/output.log) | 0.43 | 0.90 | 1.38 | 26.62 | 100 | 98.28 |
| [100 × 409,600](evidence/2026-10-03/fixed-100-c100-r409600/output.log) | 0.43 | 0.89 | 1.38 | 31.41 | 100 | 98.44 |

**จุดที่พบปัญหา:** ตรวจสอบ exit 124 และ log; benchmark exit code `124`.

หลักฐานเพิ่มเติม: [สถานะ server และคำสั่งที่รัน](evidence/2026-10-03/fixed-100-c100-r409600/run.json), [server log](evidence/2026-10-03/fixed-100-c100-r409600/server.log), [LIST หลังเกิดปัญหา](evidence/2026-10-03/fixed-100-c100-r409600/seat-map.txt), [memory events](evidence/2026-10-03/fixed-100-c100-r409600/memory-events.txt)

## การตีความและข้อจำกัด

ชุดที่ 1 เพิ่มทั้ง concurrency และปริมาณงานรวม: เมื่อ C และ R เพิ่มสองเท่า Planned เพิ่มสี่เท่า จึงใช้ดูการเสื่อมของ throughput/latency และความผิดพลาดภายใต้ contention ที่สูงขึ้น แต่แยกผลของจำนวน clients ออกจากระยะเวลาที่ทำงานไม่ได้จากชุดนี้เพียงชุดเดียว

ชุดที่ 2 คง concurrency ที่ 100 การเพิ่ม R เพิ่มจำนวนงานและระยะเวลาทดสอบ ไม่ได้บังคับเพิ่ม arrival rate หรือจำนวนคำขอพร้อมกันเกินรูปแบบ closed loop เดิม จึงอาจผ่านได้ต่อเนื่องแม้งานรวมมากกว่าในชุดที่ 1 มาก benchmark ยังเก็บ latency ทุก response ไว้ในหน่วยความจำ และรวม/เรียงข้อมูลหลังจบ หากเกิดปัญหาหน่วยความจำ ต้องตรวจว่าเป็นตัวสร้างโหลดหรือ server ก่อนสรุปว่า server รับไม่ไหว

ค่ารอบ BOOM เป็นผลของงานที่รันก่อนหยุดตามความผิดพลาดครั้งแรก ไม่ใช่ผลของ Planned ทั้งหมด latency ที่คำนวณเฉพาะ response อาจดูต่ำแม้มี timeout และสัดส่วน Operation OK ไม่ใช่ completion rate ไม่ได้ทำซ้ำเพื่อหาค่าเฉลี่ยหรือค้นหาค่ากึ่งกลาง; การ retry ใช้กับรอบที่ถูกขัดจังหวะเท่านั้น จึงไม่อ้างระดับดังกล่าวเป็นเพดานถาวรของระบบ

หากตัวรันถูกขัดจังหวะ ให้ใช้ `python scripts/run-breakpoint-study.py --output results/breakpoint-2026-10-02 --resume` เพื่อใช้ image/binary เดิม เก็บหลักฐานเก่า และรันต่อจากระดับที่ยังไม่ผ่าน ตัวรันอัปเดตรายงานอัตโนมัติหลังจบแต่ละรอบและเมื่อจบการทดลอง

## หลักฐานและการทำซ้ำ

เก็บผลสรุปทุกรอบใน [runs.json](evidence/2026-10-03/runs.json), สภาพแวดล้อมใน [environment.json](evidence/2026-10-03/environment.json), IPC/ระบบปฏิบัติการใน [runtime.txt](evidence/2026-10-03/runtime.txt) และ raw log แยกโฟลเดอร์รายรอบ ลิงก์ C × R ในตารางชี้ไปที่หลักฐานของแถวนั้นโดยตรง ไฟล์หลักฐานข้อความถูกคัดลอกมาไว้ข้างรายงานแล้ว ส่วน binary อยู่ในโฟลเดอร์ผลดิบภายในเครื่อง

รันจาก root ของโปรเจกต์ โดยเลือก output directory ใหม่ที่ยังไม่มี:

```powershell
docker build -t airplane-reservation:latest .
python scripts/run-breakpoint-study.py --output results/breakpoint-repeat --fixed-increment 1000000 --fixed-linear-after 6553600
python scripts/render-breakpoint-report.py --input results/breakpoint-repeat --report-dir docs
```

สคริปต์ใช้ชื่อ container เฉพาะแต่ละรอบและลบเฉพาะ container ที่สร้างเองหลังเก็บผล มีการป้องกันไม่ส่งค่าที่เกินช่วง input ของ benchmark (clients > 100,000 หรือ C × R > 2,147,483,647) หากถึงขอบนี้จะรายงานเป็นข้อจำกัดของตัวสร้างโหลด ไม่อ้างเป็น server boom
