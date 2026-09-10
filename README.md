# Airplane Reservation System

Concurrent reservation system สำหรับที่นั่งบนเครื่องบิน 20 ที่นั่ง เขียนด้วย C++17 โดยใช้ System V Message Queue สำหรับ IPC และใช้ per-seat mutex ควบคุม critical section ในโหมดที่เปิด synchronization

เอกสาร architecture อยู่ที่ [docs/architecture.md](docs/architecture.md)

## Requirements

- Linux หรือ Docker ที่รัน Linux userland ได้
- Docker Engine สำหรับ build/run ตามขั้นตอนด้านล่าง
- C++17 compiler และ GNU Make หาก build นอก Docker

## Build Docker image

```bash
docker build -t airplane-reservation:latest .
```

## Run one container with multiple terminals

สร้าง container ให้ทำงานค้างไว้ก่อน:

```bash
docker run -d \
  --name airplane-reservation \
  --ipc=host \
  airplane-reservation:latest \
  sleep infinity
```

เปิด server ใน terminal แรก:

```bash
docker exec -it airplane-reservation ./server sync 3
```

เปิด client ใน terminal อื่น ๆ:

```bash
docker exec -it airplane-reservation ./client 1
docker exec -it airplane-reservation ./client 2
docker exec -it airplane-reservation ./client 3
docker exec -it airplane-reservation ./client 4
docker exec -it airplane-reservation ./client 5
```

แต่ละ client รับคำสั่งจาก stdin และรอ response ของตัวเองผ่าน response message type ที่คำนวณจาก `1000 + client_id`

## Commands

```text
LIST
STATUS <seat_id>
RESERVE <seat_id> [seat_id...]
CANCEL <seat_id> [seat_id...]
QUIT
```

ตัวอย่าง:

```text
RESERVE 10
STATUS 10
CANCEL 10
QUIT
```

## Server options

```text
./server [sync|nosync] [worker_count]
```

- `sync` เปิด per-seat mutex (ค่าเริ่มต้น)
- `nosync` ปิด mutex เพื่อสาธิต race condition
- `worker_count` ต้องมากกว่า 0 และค่าเริ่มต้นคือ 3

Server ใช้ queue ที่สร้างจาก `ftok("/tmp", 'A')` และใช้ request message type `1` ส่วน response ใช้ `1000 + client_id`

## Required experiments

ให้เริ่ม server ใหม่สำหรับแต่ละกรณี เพื่อให้ seat state เริ่มต้นเป็น AVAILABLE และให้ใช้ client อย่างน้อย 5 ตัวจอง seat เดียวกัน เช่น seat 10

### Experiment 1: Sequential baseline

ใช้ worker เพียงตัวเดียวและเปิด synchronization:

```bash
./server sync 1
```

ผลควรทำงานถูกต้องโดยไม่มี concurrent worker race

### Experiment 2: Concurrent without synchronization

ใช้ worker อย่างน้อย 3 ตัวและปิด synchronization:

```bash
./server nosync 3
```

จากนั้นให้ client 1–5 ส่ง `RESERVE 10` ใกล้เคียงกัน ระบบมี random delay 50–500 ms ระหว่าง check และ update เพื่อขยาย race window สำหรับการทดลองเท่านั้น อาจเห็นมากกว่าหนึ่ง client รายงานว่าสำเร็จหรือ log แสดงว่าหลาย worker เห็น seat ว่างพร้อมกัน

### Experiment 3: Concurrent with synchronization

ใช้ worker จำนวนเดิมและเปิด synchronization:

```bash
./server sync 3
```

จากนั้นทดลอง `RESERVE 10` แบบเดิม ระบบต้องให้สำเร็จเพียงหนึ่ง client เท่านั้น ส่วน client อื่นต้องได้ผลลัพธ์ failed เนื่องจาก transaction ตรวจสอบและ update ภายใต้ mutex ที่เกี่ยวข้อง

## Run on Kubernetes

```bash
docker build -t airplane-reservation:latest .
kubectl apply -f k8s/pod.yaml
kubectl get pod airplane-reservation
```

`k8s/pod.yaml` สร้าง Pod เดียวที่มี server 1 container และ client 5 containers โดย server เริ่มด้วย `./server nosync 3` เพื่อใช้สาธิต Experiment 2

เปิด client จาก terminal แยกกัน:

```bash
kubectl exec -it airplane-reservation -c client-1 -- ./client 1
kubectl exec -it airplane-reservation -c client-2 -- ./client 2
kubectl exec -it airplane-reservation -c client-3 -- ./client 3
kubectl exec -it airplane-reservation -c client-4 -- ./client 4
kubectl exec -it airplane-reservation -c client-5 -- ./client 5
```

รัน race test แบบไม่ synchronize:

```bash
bash scripts/race-test.sh
```

สำหรับ Experiment 3 ให้สลับไปใช้ manifest ที่เปิด synchronization:

```bash
kubectl delete -f k8s/pod.yaml
kubectl apply -f k8s/pod-sync.yaml
```

`k8s/pod-sync.yaml` ใช้ server command `./server sync 3` โดยมี client containers เหมือนเดิม การใช้ Pod คนละ manifest ช่วยให้สลับ configuration ได้โดยไม่ต้องแก้ไฟล์ระหว่าง demo

Containers ใน Pod เดียวกันแชร์ IPC namespace กันโดยปริยาย จึงไม่จำเป็นต้องใช้ `hostIPC: true` ซึ่งจะทำให้ System V queue ไปแชร์กับ Pod อื่นบน node เดียวกัน

## Load test

`load_test` ส่ง `STATUS`, `RESERVE` หรือ `CANCEL` requests แบบ concurrent และรายงาน completion rate, ผลลัพธ์ของ operation, throughput และ average latency:

```bash
./load_test <total_requests> <concurrency> <STATUS|RESERVE|CANCEL> [seat_id]
```

ตัวอย่าง:

```bash
./load_test 1000 20 STATUS
./load_test 1000 20 RESERVE
./load_test 1000 20 RESERVE 10
./load_test 1000 20 CANCEL
```

ถ้าไม่ระบุ `seat_id` ระบบจะวน target seat 1–20 ส่วนการระบุ `seat_id` จะทำให้ทุก request ยิง resource เดียวกัน เหมาะสำหรับวัด contention และ transaction behavior

สำหรับวัด `CANCEL` ให้เตรียม reservation ด้วย request mapping เดิมก่อน เช่น:

```bash
./load_test 20 20 RESERVE
./load_test 20 20 CANCEL
```

คำสั่งทั้งสองใช้ client id และ seat mapping เดียวกัน ทำให้ cancel ชุดที่สองสามารถยกเลิก reservation ที่สร้างโดยชุดแรกได้

## Logs

Server log มี sequence number, worker id, client id, command/resource ที่กำลังทำงาน และ log การเข้า/ออก critical section เช่น:

```text
[SEQ 4] [Worker-2] [Client-2] received RESERVE 10
[SEQ 5] [Worker-2] [Client-2] entering critical section for RESERVE
[SEQ 6] [Worker-2] [Client-2] Seat 10 reserved
[SEQ 7] [Worker-2] [Client-2] leaving critical section for RESERVE
```

## Build locally on Linux

```bash
make
```

จะได้ executable `server`, `client` และ `load_test` โดยใช้ source modules ใน `src/` โดย logic ตรวจเลข argument ที่ใช้ร่วมกันอยู่ใน `src/utils/cli_parser.cpp`

## Current limitations

- Reservation data อยู่ใน memory ของ server process เท่านั้น และจะ reset เมื่อ server restart
- Queue lifecycle ถูกจัดการโดย System V kernel queue; ให้ใช้ container/Pod ใหม่เมื่อเปลี่ยน experiment เพื่อแยกผลการทดลอง
- `nosync` เป็นโหมดทดลองที่จงใจปล่อยให้เกิด race condition ไม่ควรใช้เป็น production mode
