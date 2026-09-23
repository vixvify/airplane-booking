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

ระหว่างที่ script ทำงาน จะเปิด server logs แบบ live ใน terminal เดียวกันทันที โดย script จะเติม prefix `[SERVER]` ให้ log ฝั่ง server และ script จะเติม `[CLIENT-N]` ให้ผลลัพธ์ของแต่ละ client ส่วนคำสั่ง `kubectl logs ... --tail=100` ที่อยู่ท้ายแต่ละตัวอย่างใช้ดู log ย้อนหลังหลังจบการทดสอบ

`kubectl wait` แค่รอให้ server และ client containers พร้อม ไม่ได้สร้าง Pod เอง

หลังจบการทดลอง:

```bash
kubectl delete pod airplane-reservation
```

Containers ใน Pod เดียวกันแชร์ IPC namespace กันโดยปริยาย จึงไม่จำเป็นต้องใช้ `hostIPC: true` และทุก container mount โฟลเดอร์ร่วม `/ipc` ผ่าน `emptyDir` เพื่อให้ `ftok` สร้าง queue key เดียวกัน โดย queue จะไม่ปะปนกับ Pod อื่นบน node เดียวกัน

### Demo 1: หลาย client ส่งหลายคำสั่ง

Demo 1 นี้เป็นการสาธิตคำสั่งปกติตาม requirement ไม่ใช่ชื่อใหม่ของ Experiment 1 (sequential baseline)

เริ่ม Pod แบบ sync 3 ใหม่ก่อน เพื่อให้ที่นั่ง 1–5 ว่าง แล้วรัน:

```bash
kubectl delete pod airplane-reservation --ignore-not-found
kubectl apply -f k8s/pod-sync.yaml
kubectl wait --for=condition=Ready pod/airplane-reservation --timeout=60s
bash scripts/demo1.sh
```

script เริ่ม client 1–5 พร้อมกัน แต่ละ client ส่งชุดคำสั่งต่างกันที่ครอบคลุม `LIST`, `STATUS`, `RESERVE`, `CANCEL`, `QUIT` โดยจองที่นั่งของตัวเองแล้วให้ client เดิมยกเลิก ทุก client ต้องจองและยกเลิกสำเร็จ หากที่นั่งไม่ว่างตั้งแต่แรก script จะหยุดก่อนเริ่ม demo ไม่ลบ reservation ของผู้อื่น

ส่วน Demo 2 (race) ใช้ Experiment 2 และ Demo 3 (แก้ race) ใช้ Experiment 3 ด้านบน

### ไฟล์หลักฐานของแต่ละรอบ

ทั้ง `demo1.sh` และ `concurrent-test.sh` แสดง live logs และสร้างโฟลเดอร์ใหม่ใน `results/` ทุกครั้ง:

- `summary.txt`: ประเภท demo, เวลาเริ่ม/จบ, runtime และ exit code
- `client-N-commands.txt`: คำสั่งที่ส่ง
- `client-N.txt`: คำตอบของ client แยกคนละไฟล์
- `server-live.txt`: log ที่ได้รับระหว่างรัน
- `server.txt`: log ตั้งแต่เริ่ม script ที่ดึงซ้ำเมื่อจบ เพื่อเก็บบรรทัดท้ายให้ครบ

ไฟล์เก่าไม่ถูกเขียนทับ และ `results/` ไม่ถูก commit อัตโนมัติ สำเนาโฟลเดอร์ที่ต้องการแนบรายงานได้เลย การพิมพ์ข้อความ “finished” หมายถึงส่ง/รับและเก็บผลสำเร็จ; ใน concurrent test การจองแพ้เป็นผลที่คาดไว้ ต้องนับผู้ชนะเปรียบเทียบแต่ละโหมดด้วย

หากใช้ Windows ให้เปิด **Git Bash** แล้วรัน script ใน root ของโปรเจกต์ การมี WSL อย่างเดียวไม่ได้ยืนยันว่ามี Linux distribution ที่มี `/bin/bash`; error `CreateProcessCommon ... /bin/bash` เกิดก่อน script เริ่มทำงาน

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

แต่ละ client ส่งคำสั่งผ่าน shared request queue และรอคำตอบผ่าน shared response queue โดยแต่ละ request มี `requestId` ที่ไม่ซ้ำกัน และ response ใช้ค่านี้เป็น `mtype` จึงไม่แย่งพื้นที่กับ request และไม่รับคำตอบสลับกันแม้ client ID ซ้ำ

### Concurrent test บน Docker

ให้เปิด server ค้างไว้ใน terminal หนึ่งก่อน แล้วใช้ terminal อีกอันยิง client ทั้ง 5 ตัวพร้อมกัน

ถ้าใช้ Git Bash หรือ WSL:

```bash
for i in 1 2 3 4 5; do
  docker exec airplane-reservation \
    sh -c "printf 'RESERVE 10\\n' | ./client $i" &
done
wait
```

ถ้าใช้ PowerShell:

```powershell
$jobs = 1..5 | ForEach-Object {
    $id = $_
    Start-Job -ScriptBlock {
        param($id)
        docker exec airplane-reservation sh -c "printf 'RESERVE 10\n' | ./client $id"
    } -ArgumentList $id
}

$jobs | Wait-Job | Out-Null
$jobs | Receive-Job
$jobs | Remove-Job
```

คำสั่งชุดนี้เทียบเท่ากับ `scripts/concurrent-test.sh` แต่ใช้ `docker exec` แทน `kubectl exec` และจึงใช้ได้กับ Docker standalone เท่านั้น

### ใช้ demo script กับ Docker โดยตรง

หากต้องการให้ script เก็บ server logs ด้วย ให้ server เป็น process หลักของ container (ต่างจากตัวอย่าง `sleep infinity` + `docker exec` ด้านบน):

```bash
docker run -d --name reservation-demo airplane-reservation:latest ./server sync 3
RUNTIME=docker CONTAINER_NAME=reservation-demo bash scripts/demo1.sh
RUNTIME=docker CONTAINER_NAME=reservation-demo bash scripts/concurrent-test.sh
```

เมื่อเปลี่ยน experiment ให้หยุดและลบ container ทดลองนี้ แล้วสร้างใหม่ด้วย `sync 1`, `nosync 3` หรือ `sync 3` เพื่อ reset ที่นั่ง:

```bash
docker stop reservation-demo
docker rm reservation-demo
```

บน Linux ที่รัน binary โดยตรง ให้ terminal แรกใช้ `./server sync 3 > server.txt 2>&1` แล้ว terminal อีกอันใช้ `RUNTIME=local SERVER_LOG=server.txt bash scripts/demo1.sh` (ต้องมี `/ipc` และสิทธิ์เขียน)

## 6. Commands ใน client

```text
LIST
STATUS <seat_id>
RESERVE <seat_id> [seat_id...]
CANCEL <seat_id> [seat_id...]
QUIT
```

`RESERVE` และ `CANCEL` ที่ระบุหลาย seat เป็น transaction แบบ all-or-nothing: ถ้ามี seat ใดไม่ผ่านเงื่อนไข ระบบจะไม่เปลี่ยนสถานะ seat ใดในคำสั่งนั้น ทั้ง `sync` และ `nosync` ใช้กฎนี้เหมือนกัน แต่ `nosync` ยังจงใจไม่ป้องกัน race ระหว่าง concurrent requests

ตัวอย่าง:

```text
RESERVE 10
STATUS 10
CANCEL 10
QUIT
```

คำสั่งยาวได้ไม่เกิน 127 bytes (ไม่รวม newline); ยาวเกินหรือมี NUL จะถูกปฏิเสธทั้งคำสั่ง ไม่ตัดข้อความแล้วนำไปรัน เลข overflow ถูกปฏิเสธก่อนเปลี่ยนข้อมูล และ `QUIT extra` จะแสดง usage โดยยังรับคำสั่งถัดไป

## 7. Server options

```text
./server [sync|nosync] [worker_count]
```

- `sync` เปิด per-seat mutex (ค่าเริ่มต้น)
- `nosync` ปิด mutex เพื่อสาธิต race condition
- `worker_count` อยู่ระหว่าง 1–64 และค่าเริ่มต้นคือ 3

Server สร้าง shared request queue จาก `ftok("/ipc", 'A')` และ shared response queue จาก `ftok("/ipc", 'B')` โดย request ใช้ message type `1` และ response ใช้ `requestId` เป็น message type Server จะล็อก `/ipc/server.lock` ก่อนจัดการทั้งสอง queue: เปิดซ้ำจะถูกปฏิเสธโดยไม่กระทบตัวเดิม แต่หลัง crash ยังลบ stale queues และเริ่มใหม่ได้

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

### PowerShell: รันและเก็บผลเป็น TXT อัตโนมัติ

บน Windows แนะนำให้ใช้ wrapper นี้แทนการเรียก `kubectl exec` โดยตรง:

```powershell
.\scripts\load-test.ps1 50000 100 RESERVE 10
```

argument ตามลำดับคือ `total_requests`, `concurrency`, `operation` และ `seat_id` โดย `seat_id` ไม่จำเป็นสำหรับ `STATUS` และถ้าไม่ใส่ ระบบจะวนใช้ที่นั่ง 1-20

ทุกครั้งที่รัน สคริปต์จะแสดงผล load test แบบสดใน terminal และสร้างโฟลเดอร์ใหม่เพื่อไม่ให้ทับผลเก่า:

```text
results/load-<timestamp>-<id>/
├── load-test.txt
├── server-log.txt
└── summary.txt
```

- `load-test.txt`: output และผลสรุปจากโปรแกรม `load_test`
- `server-log.txt`: log ของ server ตั้งแต่เวลาเริ่มทดสอบครั้งนั้น
- `summary.txt`: argument, เวลาเริ่ม/จบ และ exit code สำหรับตรวจว่าการทดสอบสำเร็จหรือไม่

ตัวอย่าง:

```powershell
.\scripts\load-test.ps1 1000 20 STATUS
.\scripts\load-test.ps1 1000 20 RESERVE
.\scripts\load-test.ps1 1000 20 CANCEL 10
```

แม้ load test หรือการเก็บ server log ล้มเหลว สคริปต์จะยังเก็บหลักฐานที่ได้ไว้ในโฟลเดอร์รอบนั้น และคืน exit code ที่ไม่ใช่ศูนย์

### รัน executable โดยตรง

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

client/load test มี timeout 10 วินาทีต่อ request (รวมเวลารอส่งและรอคำตอบ) หาก timeout หลังส่งแล้ว ผลของ operation อาจเกิดขึ้นแล้วหรือยังอยู่ใน queue ให้ตรวจ `STATUS` ก่อนลองจอง/ยกเลิกซ้ำ ไม่ถือว่า timeout แปลว่า transaction ถูก rollback

`load_test` ใช้ thread pool ตาม concurrency และคืน exit code ไม่เป็นศูนย์เมื่อ transport ล้มเหลว ส่วน `Operation Fail` เช่นจองที่นั่งที่มีเจ้าของแล้ว เป็นผลลัพธ์ทางธุรกิจ ไม่ใช่ transport failure

หากต้องการบันทึกผล load test บน Git Bash/Linux:

```bash
mkdir -p results
set -o pipefail
kubectl exec airplane-reservation -c client-1 -- ./load_test 200 200 RESERVE 10 | tee "results/load-$(date +%Y%m%d-%H%M%S).txt"
```

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

## 12. Tests

Test suite อยู่ในโฟลเดอร์ `tests/`:

| คำสั่ง | ขอบเขต |
| --- | --- |
| `make test-unit` | parser, seat validation, ownership, duplicate seats, multi-seat rollback, sync/nosync concurrency |
| `make test-integration` | server/client ผ่าน System V queue จริง, ทุก client command, CLI errors, 3 experiment modes, load test, queue cleanup/recovery |
| `make test-regression` | บั๊กทั้ง 8 จุด, timeout/queue routing, Demo 1, script exit codes, path ที่มีช่องว่าง และ incremental build |
| `make test-k8s` | smoke test manifests ทั้ง 3 แบบ, command lifecycle และ load test บน Kubernetes |

รัน unit, IPC, integration, regression, script และ build tests บน Linux (ต้องมี `/ipc` ที่เขียนได้ และไม่มี server ของงานอื่นใช้ namespace นี้):

```bash
bash scripts/test.sh
```

วิธีที่แนะนำบน Windows คือรันผ่าน Docker เพื่อให้ได้ Linux environment และ `/ipc` พร้อมใช้งาน:

```bash
docker build -t airplane-reservation:latest .
docker run --name reservation-tests airplane-reservation:latest timeout 300s bash scripts/test.sh
docker cp reservation-tests:/app/results ./results-from-container
docker rm reservation-tests
```

คำสั่ง `docker cp` เก็บหลักฐานออกมาก่อนลบ container; ถ้า tests fail ก็ยัง copy ผลมาตรวจได้ ส่วน `make test` รันชุดเดียวกัน แต่ `scripts/test.sh` เพิ่ม transcript รวม `test-output.txt`

CI ใน `.github/workflows/ci.yml` build image และรันชุดเดียวกันเมื่อ push ไป main/development หรือเปิด PR เข้า branch เหล่านั้น พร้อม upload `reservation-test-results` แม้ tests fail (เก็บ 14 วัน) การทดสอบ quoting ของ Kubernetes ใน CI ใช้ mock; ไม่ใช่การ deploy Kubernetes จริง

สำหรับ Kubernetes ให้ build image ก่อน เปิด Docker Desktop Kubernetes แล้วรันจาก Git Bash หรือ WSL:

```bash
make test-k8s
```

Kubernetes smoke test จะลบและสร้าง Pod `airplane-reservation` ใหม่หลายครั้งเพื่อแยก state ของแต่ละกรณี และลบ Pod เมื่อจบ หากต้องการเก็บ Pod สุดท้ายไว้ให้ใช้ `KEEP_TEST_POD=1 make test-k8s`

กรณีที่ตรวจครอบคลุมประกอบด้วย LIST, STATUS, RESERVE, CANCEL, QUIT, malformed input, seat bounds, client ownership, duplicate seats, transaction rollback, sequential baseline, synchronized concurrency, unsynchronized race, fixed-seat/round-robin load และ stale queue recovery

## 13. Current limitations

- Reservation data อยู่ใน memory ของ server process เท่านั้น และจะ reset เมื่อ server restart
- Queue lifecycle ถูกจัดการโดย System V kernel queue; ให้ใช้ container/Pod ใหม่เมื่อเปลี่ยน experiment เพื่อแยกผลการทดลอง
- หาก client timeout หรือถูกปิดหลัง server ประมวลผลแล้ว response ที่ไม่มีผู้รับอาจค้างใน shared response queue จน server restart; worker ส่งแบบ `IPC_NOWAIT` จึงไม่ deadlock แต่ client อื่นอาจ timeout หาก queue เต็ม
- หลังแก้ source หรือ message format ต้อง build image ใหม่และสร้าง Pod ใหม่ทั้งชุด ห้ามผสม binary เก่ากับใหม่
- `nosync` เป็นโหมดทดลองที่จงใจปล่อยให้เกิด race condition ไม่ควรใช้เป็น production mode
