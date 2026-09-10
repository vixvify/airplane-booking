# Airplane Reservation System

Concurrent reservation system สำหรับที่นั่งบนเครื่องบิน 20 ที่นั่ง เขียนด้วย C++17 โดยใช้ System V Message Queue สำหรับ IPC และใช้ per-seat mutex ควบคุม critical section ในโหมดที่เปิด synchronization

เอกสาร architecture อยู่ที่ [docs/architecture.md](docs/architecture.md)

## Requirements

- Docker Desktop โดยเปิดใช้งาน Kubernetes และ `kubectl` ที่ชี้ไปยัง context `docker-desktop`
- Git Bash หรือ WSL สำหรับรัน `bash scripts/concurrent-test.sh`
- C++17 compiler และ GNU Make หากต้องการ build นอก Docker

## 1. สรุปการทดลองทั้ง 3 แบบ

ทั้ง 3 experiments ใช้ workload เดียวกัน: client 1–5 ยิง `RESERVE 10` พร้อมกันผ่าน `scripts/concurrent-test.sh` แล้วเปลี่ยนเฉพาะ server configuration

| Experiment | Manifest | Server | ผลที่คาดหวัง |
| --- | --- | --- | --- |
| 1. Sequential baseline | `k8s/pod-sequential.yaml` | `sync 1` | สำเร็จ 1 client เพราะมี worker เดียว |
| 2. Concurrent without synchronization | `k8s/pod.yaml` | `nosync 3` | อาจมีหลาย client สำเร็จ เพราะจงใจไม่มี mutex |
| 3. Concurrent with synchronization | `k8s/pod-sync.yaml` | `sync 3` | สำเร็จ 1 client เพราะมี per-seat mutex |

Exp1 ยังยิง client พร้อมกันเหมือน Exp2/3 แต่ server มี worker เดียว จึงประมวลผลทีละ request และไม่มี worker race

## 2. เตรียม image และ Kubernetes

สร้าง image และตรวจสอบ Kubernetes ก่อน:

```bash
docker build -t airplane-reservation:latest .
kubectl config use-context docker-desktop
kubectl get nodes
```

ควรเห็น node `docker-desktop` มีสถานะ `Ready` จากนั้นเริ่ม experiment ที่ต้องการตามขั้นตอนด้านล่าง

## 3. วิธีรันแต่ละ experiment

ทุก experiment ใช้ขั้นตอนเหมือนกัน: ลบ Pod เก่า → apply manifest → รอ Pod พร้อม → ยิง workload → ดู server log

### Experiment 1: Sequential baseline

```bash
kubectl delete pod airplane-reservation --ignore-not-found
kubectl apply -f k8s/pod-sequential.yaml
kubectl wait --for=condition=Ready pod/airplane-reservation --timeout=60s
kubectl get pod airplane-reservation
bash scripts/concurrent-test.sh
kubectl logs airplane-reservation -c server --tail=100
```

### Experiment 2: Concurrent without synchronization

```bash
kubectl delete pod airplane-reservation --ignore-not-found
kubectl apply -f k8s/pod.yaml
kubectl wait --for=condition=Ready pod/airplane-reservation --timeout=60s
kubectl get pod airplane-reservation
bash scripts/concurrent-test.sh
kubectl logs airplane-reservation -c server --tail=100
```

### Experiment 3: Concurrent with synchronization

```bash
kubectl delete pod airplane-reservation --ignore-not-found
kubectl apply -f k8s/pod-sync.yaml
kubectl wait --for=condition=Ready pod/airplane-reservation --timeout=60s
kubectl get pod airplane-reservation
bash scripts/concurrent-test.sh
kubectl logs airplane-reservation -c server --tail=100
```

`concurrent-test.sh` ยิง `RESERVE 10` จาก client ทั้ง 5 ตัวพร้อมกัน จึงไม่ต้องเปิด terminal client แยกเอง

ระหว่างที่ script ทำงาน จะเปิด server logs แบบ live ใน terminal เดียวกันทันที โดย Kubernetes จะเติม prefix `[pod/airplane-reservation/server]` ให้ log ฝั่ง server และ script จะเติม `[CLIENT-N]` ให้ผลลัพธ์ของแต่ละ client ส่วนคำสั่ง `kubectl logs ... --tail=100` ที่อยู่ท้ายแต่ละตัวอย่างใช้ดู log ย้อนหลังหลังจบการทดสอบ

`kubectl wait` แค่รอให้ server และ client containers พร้อม ไม่ได้สร้าง Pod เอง

หลังจบการทดลอง:

```bash
kubectl delete pod airplane-reservation
```

Containers ใน Pod เดียวกันแชร์ IPC namespace กันโดยปริยาย จึงไม่จำเป็นต้องใช้ `hostIPC: true` และทุก container mount โฟลเดอร์ร่วม `/ipc` ผ่าน `emptyDir` เพื่อให้ `ftok` สร้าง queue key เดียวกัน โดย queue จะไม่ปะปนกับ Pod อื่นบน node เดียวกัน

## 4. ทดสอบ client แบบ manual

ถ้าต้องการป้อนคำสั่งเอง ให้เปิด client แต่ละตัวใน terminal แยกกัน:

```bash
kubectl exec -it airplane-reservation -c client-1 -- ./client 1
kubectl exec -it airplane-reservation -c client-2 -- ./client 2
kubectl exec -it airplane-reservation -c client-3 -- ./client 3
kubectl exec -it airplane-reservation -c client-4 -- ./client 4
kubectl exec -it airplane-reservation -c client-5 -- ./client 5
```

ใช้วิธีนี้สำหรับทดสอบคำสั่งทีละรายการ ส่วนการยิงพร้อมกันทั้ง 5 clients ให้ใช้ `scripts/concurrent-test.sh`

## 5. Docker standalone (optional)

ใช้สำหรับ debug หรือทดสอบระบบบน container เดียวโดยไม่ใช้ Kubernetes:

```bash
docker build -t airplane-reservation:latest .
```

### Run one container with multiple terminals

สร้าง container ให้ทำงานค้างไว้ก่อน:

```bash
docker run -d \
  --name airplane-reservation \
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

## 6. Commands ใน client

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

## 7. Server options

```text
./server [sync|nosync] [worker_count]
```

- `sync` เปิด per-seat mutex (ค่าเริ่มต้น)
- `nosync` ปิด mutex เพื่อสาธิต race condition
- `worker_count` ต้องมากกว่า 0 และค่าเริ่มต้นคือ 3

Server ใช้ queue ที่สร้างจาก `ftok("/ipc", 'A')` และใช้ request message type `1` ส่วน response ใช้ `1000 + client_id`

## 8. Experiment details เมื่อรัน executable โดยตรง

ส่วนนี้เป็นรายละเอียดของโหมดเดียวกับการทดลองใน Kubernetes ด้านบน ถ้ารัน `server` ตรงบน Linux หรือ Docker ให้ใช้คำสั่งเหล่านี้แทน manifest

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

## 9. Load test

`load_test` เป็นคนละส่วนกับ `concurrent-test.sh` โดยส่ง `STATUS`, `RESERVE` หรือ `CANCEL` requests จำนวนมากแบบ concurrent และรายงาน completion rate, ผลลัพธ์ของ operation, throughput และ average latency ต้องมี Pod กำลังทำงานอยู่ก่อน และรันใน client container ใดก็ได้:

```bash
kubectl exec airplane-reservation -c client-1 -- ./load_test <total_requests> <concurrency> <STATUS|RESERVE|CANCEL> [seat_id]
```

ตัวอย่าง:

```bash
kubectl exec airplane-reservation -c client-1 -- ./load_test 1000 20 STATUS
kubectl exec airplane-reservation -c client-1 -- ./load_test 1000 20 RESERVE
kubectl exec airplane-reservation -c client-1 -- ./load_test 1000 20 RESERVE 10
kubectl exec airplane-reservation -c client-1 -- ./load_test 1000 20 CANCEL
```

ถ้าไม่ระบุ `seat_id` ระบบจะวน target seat 1–20 ส่วนการระบุ `seat_id` จะทำให้ทุก request ยิง resource เดียวกัน เหมาะสำหรับวัด contention และ transaction behavior

สำหรับวัด `CANCEL` ให้เตรียม reservation ด้วย request mapping เดิมก่อน เช่น:

```bash
kubectl exec airplane-reservation -c client-1 -- ./load_test 20 20 RESERVE
kubectl exec airplane-reservation -c client-1 -- ./load_test 20 20 CANCEL
```

คำสั่งทั้งสองใช้ client id และ seat mapping เดียวกัน ทำให้ cancel ชุดที่สองสามารถยกเลิก reservation ที่สร้างโดยชุดแรกได้

## 10. Logs

Server log มี sequence number, worker id, client id, command/resource ที่กำลังทำงาน และ log การเข้า/ออก critical section เช่น:

```text
[SEQ 4] [Worker-2] [Client-2] received RESERVE 10
[SEQ 5] [Worker-2] [Client-2] entering critical section for RESERVE
[SEQ 6] [Worker-2] [Client-2] Seat 10 reserved
[SEQ 7] [Worker-2] [Client-2] leaving critical section for RESERVE
```

## 11. Build locally on Linux

```bash
make
```

จะได้ executable `server`, `client` และ `load_test` โดยใช้ source modules ใน `src/` โดย logic ตรวจเลข argument ที่ใช้ร่วมกันอยู่ใน `src/utils/cli_parser.cpp`

## 12. Current limitations

- Reservation data อยู่ใน memory ของ server process เท่านั้น และจะ reset เมื่อ server restart
- Queue lifecycle ถูกจัดการโดย System V kernel queue; ให้ใช้ container/Pod ใหม่เมื่อเปลี่ยน experiment เพื่อแยกผลการทดลอง
- `nosync` เป็นโหมดทดลองที่จงใจปล่อยให้เกิด race condition ไม่ควรใช้เป็น production mode
