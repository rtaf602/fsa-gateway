# วิธี A – Gateway เปิดตลอด + VPN + Private CA

เป้าหมาย: อัพเดท iPad ได้จากทุกที่ ไม่ต้องไปเปิดคอม Gateway ที่ที่ทำงาน
และใช้ใบรับรอง SSL ที่ต่ออายุประมาณทุก 2 ปี โดยไม่มีค่าใช้จ่าย

```
 iPad (4G/Wi-Fi ที่ไหนก็ได้)
   │  VPN (เปิดอัตโนมัติเมื่อแอป Flysmart+ ใช้งาน)
   ▼
 VPN gateway ของหน่วย ── firewall: อนุญาตเฉพาะ VPN pool → Gateway:HTTPS
   ▼
 Gateway server (เปิด 24 ชม.)  efb-gateway.rtaf602.com : <HTTPS port>
   Wildfly + PostgreSQL + ใบรับรองจาก RTAF602 EFB Root CA (≤ 825 วัน)
```

Gateway ไม่ได้เปิดออกอินเทอร์เน็ต จึงเข้าได้เฉพาะ iPad ที่ต่อ VPN แล้วเท่านั้น

> ก่อนเริ่ม: ขออนุมัติจากฝ่ายสื่อสาร/ไซเบอร์ของหน่วย และถาม NAVBLUE support ว่า
> (1) รองรับใบรับรองจาก enterprise/private CA ที่ติดตั้งผ่าน MDM หรือไม่
> (2) การย้าย Gateway ไปเครื่องใหม่ต้องขอ license ใหม่หรือไม่

---

## ขั้นที่ 1 – ย้าย Gateway ไปเครื่องที่เปิดตลอด

**สเปกขั้นต่ำ** (Installation Guide 3.1–3.2): Windows Server 2016/2019/2022 (หรือ Windows 10/11 Pro/Enterprise),
CPU 64-bit 1.8 GHz, RAM 8 GB, พื้นที่ว่าง 4 GB + 50 GB สำหรับข้อมูล ใช้เป็น VM ได้
ควรใช้ IP คงที่ และมี UPS

**ตั้งค่าไม่ให้เครื่องหลับ** (PowerShell แบบ Administrator):
```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /hibernate off
```
ตั้ง Windows Update ให้รีบูตนอกเวลาปฏิบัติงาน (Active hours / maintenance window)
installer ตั้ง service Wildfly เป็น Automatic ให้อยู่แล้ว

**ย้ายข้อมูลจากเครื่องเดิม** (คู่มือบทที่ 9 และ FAQ "How to copy all the data from Gateway server 1 to server 2"
บน NAVBLUE Support Portal):
1. เครื่องเดิม: export **User Report แบบ XML** (Fleet / Profile / User management – คู่มือ 9.1)
2. เครื่องเดิม: backup ฐานข้อมูลเป็น **TAR format** (บังคับ – คู่มือ 9.2) เช่น
   ```powershell
   & "C:\Program Files\PostgreSQL\14\bin\pg_dump.exe" -U postgres -p <PG_PORT> -F t -f D:\backup\fsa-gateway.tar fsa-gateway
   ```
3. เครื่องเดิม: คัดลอกโฟลเดอร์ `fsa-license`, `notification-artifacts`, `PerformanceReport`, `Repository`
   จาก Gateway Installation Folder
4. เครื่องใหม่: ติดตั้ง JDK, PostgreSQL, Gateway **เวอร์ชันเดียวกัน** ตาม Installation Guide
   - เปลี่ยนพอร์ต HTTPS จาก 8443 (คู่มือ 10.2)
   - จด Wildfly admin / PostgreSQL password ไว้ – จำเป็นตอน upgrade (คู่มือ 7.2)
   - รหัสผ่านทุกตัวห้ามมี `< > " = / # :`
5. เครื่องใหม่: restore ฐานข้อมูลและโฟลเดอร์ตาม FAQ "How to restore a PostgreSQL Backup"
6. ตรวจ Preferences และ Ident Name ใหม่ เพราะ User Report ไม่ได้เก็บค่าเหล่านี้ (คู่มือ 9.1)

> ⚠️ ฐานข้อมูลจาก PostgreSQL 12 นำเข้า PostgreSQL 14+ ไม่ได้ (คู่มือบทที่ 7) ถ้าเครื่องเดิมยังใช้ PG12 ต้องติดตั้งใหม่ทั้งหมด
> แล้วนำเข้าเฉพาะ User Report XML

**ตั้ง backup อัตโนมัติ**: ใช้ Task Scheduler รัน `pg_dump -F t` ทุกคืน และคัดลอก 4 โฟลเดอร์ข้างบนไปไว้นอกเครื่อง

---

## ขั้นที่ 2 – DNS

- เพิ่ม A record `efb-gateway.rtaf602.com` → IP ของ Gateway ใน **DNS ภายใน**
- ตั้ง VPN ให้ส่ง DNS ภายในนี้ให้ iPad (split DNS) iPad จึง resolve ชื่อนี้ได้เฉพาะตอนต่อ VPN
- เนื่องจากใช้ Private CA จึงไม่จำเป็นต้องมี record นี้ใน DNS สาธารณะ แต่ **ควรจดโดเมน `rtaf602.com` ไว้**
  หรือใช้ชื่อใต้โดเมนทางการของหน่วยแทน เพื่อไม่ให้คนอื่นนำชื่อนี้ไปใช้
- ห้ามใช้ `.local` เพราะ iOS ใช้ชื่อนี้กับ Bonjour/mDNS

---

## ขั้นที่ 3 – Private CA และใบรับรอง Gateway

ทำบน **เครื่องแอดมิน** ที่มี JDK (ไม่ใช่เครื่อง Gateway) และเก็บโฟลเดอร์ CA ไว้ในไดรฟ์ USB ที่เข้ารหัส (BitLocker To Go)

| ทำที่ | คำสั่ง | ผลลัพธ์ |
|---|---|---|
| เครื่องแอดมิน (ครั้งเดียว) | `.\scripts\ca\10-New-RootCA.ps1` | `root-ca.p12` (เก็บลับ), `rtaf602-efb-root-ca.cer` (สำหรับ MDM), `.pem` |
| Gateway | `.\scripts\01-New-Csr.ps1` | `gateway.csr` → คัดลอกไปเครื่องแอดมิน |
| เครื่องแอดมิน | `.\scripts\ca\11-Sign-GatewayCsr.ps1 -CsrFile gateway.csr` | `gateway.crt` อายุ 800 วัน → คัดลอกกลับไป Gateway |
| Gateway | `.\scripts\02-Import-Certificate.ps1 -CertFile gateway.crt -ChainFile rtaf602-efb-root-ca.pem` | keytool จะถามว่า "not trusted. Install reply anyway?" ให้ตรวจ fingerprint แล้วตอบ `yes` |
| Gateway (Admin) | `.\scripts\03-Install-Keystore.ps1` | ติดตั้งลง Wildfly + restart |
| Gateway | `.\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1 -CaFile rtaf602-efb-root-ca.pem` | ต้องขึ้น `[OK]` |

ใบรับรองที่ `11-Sign-GatewayCsr.ps1` ออกให้ตรงตามข้อกำหนดของ iOS:
มี SAN (DNS) และ EKU serverAuth, RSA 2048 บิตขึ้นไป, SHA-256 และอายุไม่เกิน 825 วัน
`04-Test-Gateway.ps1` ตรวจข้อกำหนดเหล่านี้ให้ซ้ำด้วย

**ติดตั้ง root CA บน iPad**
- **ผ่าน MDM (แนะนำ)**: สร้าง Configuration Profile ที่มี Certificate payload ใส่ไฟล์ `rtaf602-efb-root-ca.cer`
  แล้ว push ให้ iPad กลุ่ม EFB ทุกเครื่อง root ที่ติดตั้งผ่าน MDM จะถูกเชื่อถือให้อัตโนมัติ
- **ด้วยมือ** (กรณีไม่มี MDM): AirDrop หรืออีเมลไฟล์ `.cer` แล้วเลือก Settings → General → VPN & Device Management → ติดตั้ง
  จากนั้นต้องไปที่ Settings → General → About → **Certificate Trust Settings** แล้วเปิดสวิตช์ของ RTAF602 EFB Root CA
  ถ้าข้ามขั้นนี้ แอปจะเชื่อมต่อ Gateway ไม่ได้

ตรวจว่า SHA-1 fingerprint ที่ iPad แสดงตรงกับค่าที่ `10-New-RootCA.ps1` พิมพ์ออกมา

---

## ขั้นที่ 4 – VPN

ใช้ VPN ที่หน่วยมีอยู่แล้ว (FortiGate, Palo Alto GlobalProtect, Cisco, หรือ IKEv2 ที่มีมาใน iOS) โดยตั้งค่าดังนี้:

- **Split tunnel**: route เฉพาะ subnet ของ Gateway ผ่าน VPN อินเทอร์เน็ตส่วนอื่นของ iPad ไม่ต้องผ่าน VPN
- **Firewall บน VPN gateway**: อนุญาตเฉพาะ VPN pool → `Gateway IP : HTTPS port` เท่านั้น
- **ให้ VPN เปิดอัตโนมัติ** ผ่าน MDM เลือกแบบใดแบบหนึ่ง:
  - **Per-App VPN** ผูกกับแอป Flysmart+ (Manager, TakeOff, InFlight, Landing, Loadsheet, Ops Library, eQRH)
  - **VPN On Demand** ด้วยกฎ "connect เมื่อเรียกโดเมน `efb-gateway.rtaf602.com`"
- ใช้ใบรับรองหรือบัญชีผู้ใช้แยกต่อเครื่อง iPad เพื่อให้เพิกถอนสิทธิ์ทีละเครื่องได้เมื่อเครื่องหาย

**Firewall บนเครื่อง Gateway**: แก้ `AllowedSubnets` ใน `config.ps1` เป็น VPN pool และ LAN ของที่ทำงาน แล้วรัน
```powershell
.\scripts\05-Set-Firewall.ps1 -WhatIf               # ดูก่อนว่าจะเปลี่ยนอะไร
.\scripts\05-Set-Firewall.ps1 -DisableConflicting   # ปิด rule เดิมที่เปิดพอร์ตให้ทุก IP
```
iPad ไม่ต้องใช้พอร์ต 8080 (HTTP), 9990 (Wildfly admin) และพอร์ต PostgreSQL อย่าเปิดพอร์ตเหล่านี้ให้เข้าจากภายนอก

---

## ขั้นที่ 5 – ทดสอบและใช้งานจริง

1. ใช้ iPad ทดสอบ 1 เครื่อง ปิด Wi-Fi ที่ทำงานแล้วต่อ 4G
2. เปิด Safari ไปที่ `https://efb-gateway.rtaf602.com:<port>/fsa-gateway` ต้องเห็นรูปแม่กุญแจโดยไม่มีคำเตือน
3. ใน FS+ Manager ตั้ง ADDRESS เป็น `efb-gateway.rtaf602.com` และพอร์ตใหม่ แล้ว sync ด้วย Test user
4. ปิด VPN แล้วลองอีกครั้ง ต้องเชื่อมต่อ**ไม่ได้** เพื่อยืนยันว่า Gateway ไม่ได้เปิดออกอินเทอร์เน็ต
5. เมื่อผ่านทุกข้อ ค่อยตั้งค่าให้ iPad ทุกเครื่องผ่าน MDM

---

## ปฏิทินการดูแล

| รายการ | ความถี่ | ทำอย่างไร |
|---|---|---|
| ใบรับรอง Gateway | ประมาณทุก 2 ปี (800 วัน) | ทำขั้นที่ 3 ซ้ำ ยกเว้น `10-New-RootCA.ps1` ไม่ต้องแตะ iPad |
| Root CA | 10 ปี | สร้างใหม่และ push ผ่าน MDM ล่วงหน้าก่อนหมดอายุ |
| ตรวจวันหมดอายุ | ทุกวัน | Task Scheduler รัน `04-Test-Gateway.ps1 -Server 127.0.0.1 -CaFile ...` (ดู README) |
| Backup ฐานข้อมูล | ทุกคืน | `pg_dump -F t` + 4 โฟลเดอร์ |
