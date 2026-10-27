# บันทึกเหตุการณ์ Flysmart+ Gateway

บันทึกปัญหาที่เคยเกิด แยกตามเครื่อง เพื่อใช้อ้างอิงเมื่อเกิดซ้ำ
(ห้ามใส่รหัสผ่านในไฟล์นี้ เพราะ repo เป็น public)

## เครื่องที่ดูแล

| ชื่อเรียก | รายละเอียด |
|---|---|
| **main** | Wildfly `C:\Airbus\Wildfly`, PostgreSQL 12 (`postgresql-x64-12`), JDK `C:\Program Files\Java\jdk1.8.0_202` |
| **ohomee** | Wildfly `C:\Airbus\Wildfly`, PostgreSQL 16 (`postgresql-x64-16`), JDK 1.8.0_202, SSL `rtaf602fsagateway.com`, Tailscale subnet router |

---

## [main] 2026-10-27 — Wildfly เปิดไม่ได้ และ fsa-gateway ไม่ถูก deploy

**อาการ**
- `Get-Service Wildfly` เป็น **Stopped** และ `Start-Service Wildfly` ขึ้น `Failed to start service 'Wildfly (Wildfly)'`
- `service.<date>.log` ขึ้น `Service started in 20 ms` แล้ว `Run service finished` ทันที
- `wildfly-stderr.<date>.log` ไม่มี error
- ใน `standalone\deployments` ไม่มี `fsa-gateway.war.deployed`

**สาเหตุ**
1. JAVA_HOME = `C:\Program Files\Java\jdk1.8.0_202` แต่**ไม่มี `bin\java.exe`** เพราะ Java ถูกถอนการติดตั้ง หรือหายไประหว่างอัปเดต
   service ของ Wildfly จึงเริ่มแล้วจบทันที (Installation Guide 12.2: หลังอัปเดต Java ต้องแก้ JAVA_HOME)
2. หลังแก้ Java แล้ว `fsa-gateway-user.war` deploy ได้ แต่ `fsa-gateway.war` **ไม่มีไฟล์ `.deployed`**
   และเพราะ deployment scanner ตั้งไว้ `auto-deploy-zipped="false"` Wildfly จึงไม่ deploy เอง

**วิธีแก้**
1. ติดตั้ง JDK 1.8.0_202 (64-bit) และ JRE กลับไปที่ `C:\Program Files\Java\jdk1.8.0_202`
   แล้วตรวจด้วย `Test-Path "$env:JAVA_HOME\bin\java.exe"` ต้องได้ `True`
2. รีสตาร์ทเครื่อง ตอนนี้ Wildfly และ PostgreSQL ขึ้นสถานะ Running แล้ว
3. สร้าง `C:\Airbus\Wildfly\standalone\deployments\fsa-gateway.war.dodeploy` แล้วรอจนได้ `fsa-gateway.war.deployed`
4. ผล: ใช้งานได้

**การป้องกัน**
- ติดตั้ง `scripts\Install-GatewayAutoRepair.ps1` ซึ่งจะ:
  - ตั้งให้ Wildfly รอ PostgreSQL ก่อนเปิด
  - ตั้งให้ restart เองถ้าล่ม
  - ปิด Java auto-update
  - สร้าง Scheduled Task ซ่อมไฟล์ `.deployed` อัตโนมัติ
- ห้ามถอนการติดตั้ง Java บนเครื่องนี้ และอย่าใช้โปรแกรมลบโปรแกรมเก่าหรือทำความสะอาดเครื่อง
- ข้อสังเกต: เครื่องนี้ใช้ PostgreSQL 12 ถ้าจะอัปเกรดเป็น Gateway V5.6.1 ที่ใช้ PostgreSQL 14+
  ต้องติดตั้งใหม่ทั้งหมด เพราะนำฐานข้อมูลของ PG12 เข้า PG14+ ไม่ได้ (Installation Guide บทที่ 7)

---

## [ohomee] 2026-09-18 ถึง 2026-10-26 — iPad sync ไม่ได้ ("Could not connect to server")

**อาการ**
- แอป FS+ Manager ขึ้น `Could not connect to server. Check server URL.` แต่ Safari เปิดหน้า `/fsa-gateway` ได้
- `/fsa-gateway-user` ขึ้น 404 และไม่มี `fsa-gateway-user.war.deployed`

**สาเหตุ**
- เวลา 2026-09-18 23:04 Wildfly ถูกปิดระหว่างที่กำลัง deploy `fsa-gateway-user`
  - PostgreSQL ตัดการเชื่อมต่อ (`The connection attempt failed` / `Connection reset`)
  - Wildfly ขึ้น `Container is down` แล้ว deploy ถูก rollback และไฟล์ `.deployed` ถูกลบ
- จากนั้นทุกครั้งที่เปิดเครื่อง log ขึ้น `WFLYDS0004 ... To trigger deployment create a file called fsa-gateway-user.war.dodeploy`
  แต่ Wildfly ไม่ deploy เอง เพราะตั้ง `auto-deploy-zipped="false"`

**วิธีแก้**
- สร้าง `fsa-gateway-user.war.dodeploy` แล้วรอจนได้ `.deployed` ผล: iPad sync ได้

**การป้องกัน**
- `sc.exe config Wildfly depend= Tcpip/Afd/postgresql-x64-16` (ทำแล้ว 2026-10-26)
- ควรติดตั้ง `Install-GatewayAutoRepair.ps1` เพิ่ม

**เรื่องอื่นที่ทำในวันเดียวกัน (ไม่ใช่สาเหตุของอาการข้างบน)**
- ติดตั้ง SSL `rtaf602fsagateway.com` ใช้ได้ถึง 2027-05-12
- เปิด Firewall rule "FSA Gateway HTTPS 8443"
- ติดตั้ง Tailscale subnet router `192.168.100.0/24`
