# วิธีดูผลการรัน

รอบใหม่จะแยกเก็บตามประเภทงาน และใช้เวลา UTC เป็นชื่อโฟลเดอร์:

```text
results/
├── demos/
│   ├── concurrent/<วันเวลา>/
│   └── demo1/<วันเวลา>/
├── load-tests/<วันเวลา>/
├── tests/
│   ├── suite/<วันเวลา>/
│   ├── integration/<วันเวลา>/
│   ├── regression/<วันเวลา>/
│   ├── scripts/<วันเวลา>/
│   ├── build/<วันเวลา>/
│   └── container-smoke/<วันเวลา>/
└── archive/
    └── legacy/                 ผลจากรูปแบบโฟลเดอร์เดิม
```

## ตำแหน่งไฟล์ที่ใช้บ่อย

- ผลของ demo client: `demos/<ชนิด demo>/<รอบ>/clients/client-<id>/output.log`
- คำสั่งที่ส่งให้ client: `demos/<ชนิด demo>/<รอบ>/clients/client-<id>/commands.txt`
- สรุปว่า client ใดจอง/ยกเลิกสำเร็จ: `demos/<ชนิด demo>/<รอบ>/report.txt`
- Server log หลังจบ: `demos/<ชนิด demo>/<รอบ>/server.log`
- Server log ที่เก็บระหว่างรัน: `demos/<ชนิด demo>/<รอบ>/server-live.log`
- ผล Load Test และ throughput: `load-tests/<รอบ>/output.log`
- Server log ของ Load Test: `load-tests/<รอบ>/server.log`
- โหมดที่ใช้ จำนวน workers และ exit code: `summary.txt` ในโฟลเดอร์ของรอบนั้น
- ผล test suite ทั้งหมด: `tests/suite/<รอบ>/test-output.log`

เปิด `summary.txt` ก่อนเพื่อดูว่าใช้โหมดอะไรและสำเร็จหรือไม่ ชื่อโฟลเดอร์เรียงตามเวลาได้ และแต่ละสคริปต์จะแสดง path ของผลรอบนั้นใน terminal

ผลเก่าทั้ง 23 โฟลเดอร์ถูกย้ายไปไว้ใน `archive/legacy/` โดยคงไฟล์ข้างในไว้ครบ ไม่มีการลบข้อมูล
