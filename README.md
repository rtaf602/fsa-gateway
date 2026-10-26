# fsa-gateway – SSL certificate สำหรับ Flysmart+ for iPad Gateway (ใช้ในวง LAN)

ทำใบรับรอง SSL ให้ Flysmart+ Gateway V5.6.1 ด้วย **คำสั่งเดียว** ไม่มีค่าใช้จ่าย
ใบรับรองมีอายุประมาณ 2 ปี

เงื่อนไขการใช้งาน: iPad sync ได้เมื่อ **เครื่อง Gateway เปิดอยู่** และ **iPad ต่อ Wi-Fi วงเดียวกับเครื่อง Gateway**

> ⚠️ repo นี้เป็น public ห้าม commit ไฟล์ `.jks` `.p12` `.cer` `config.ps1` หรือรหัสผ่าน
> สคริปต์เก็บไฟล์ทั้งหมดไว้ที่ `C:\Airbus\ssl-work` ซึ่งอยู่นอก repo

---

## ทำครั้งแรก (ประมาณ 30 นาที)

### 1. ตั้งให้เครื่อง Gateway ได้ IP เดิมทุกครั้ง
ใน router ของที่ทำงาน ให้จอง IP (DHCP reservation) ให้เครื่อง Gateway เช่น `192.168.1.10`

### 2. ตั้งชื่อให้ iPad เรียกหาเครื่อง Gateway
คู่มือ NAVBLUE บังคับให้ใช้ชื่อ ห้ามใช้ IP เลือกทางใดทางหนึ่ง:

- **ก. router หรือ DNS ของที่ทำงานเพิ่มชื่อได้:** เพิ่ม `efb-gateway.rtaf602.com` → `192.168.1.10`
  (เมนูมักชื่อ Local DNS, Static DNS หรือ Host name)
- **ข. เพิ่มชื่อไม่ได้:** ใช้บริการฟรี sslip.io ที่แปลงชื่อเป็น IP ให้อัตโนมัติ เช่น IP `192.168.1.10`
  ใช้ชื่อ `efb-gateway-192-168-1-10.sslip.io` ได้ทันที
  (ต้องให้ iPad เข้าอินเทอร์เน็ตได้ และถ้าเปลี่ยน IP ต้องทำใบรับรองใหม่)

### 3. รันสคริปต์บนเครื่อง Gateway
เปิด PowerShell แบบ **Run as administrator**:
```powershell
cd C:\Airbus
git clone https://github.com/rtaf602/fsa-gateway.git
cd fsa-gateway
copy config.example.ps1 config.ps1
notepad config.ps1
```
ใน `config.ps1` ตรวจ 4 บรรทัดนี้ให้ตรงกับเครื่อง:
`Domain` (ชื่อจากข้อ 2), `WildflyPath`, `WildflyServiceName`, `HttpsPort`

จากนั้นรัน:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-LanSsl.ps1
```
- สคริปต์จะให้ตั้งรหัสผ่าน **จดเก็บไว้ ต้องใช้ตอนต่ออายุ** และรหัสผ่านห้ามมี `< > " = / # : & ' \` หรือช่องว่าง
- เมื่อเสร็จ ต้องขึ้น `Done.` และ `[OK] Certificate is valid and trusted.`
- **สำรองโฟลเดอร์ `C:\Airbus\ssl-work\ca`** ไว้ใน USB เก็บในที่ปลอดภัย
  ถ้าโฟลเดอร์นี้หาย ต้องติดตั้งไฟล์ใหม่ลง iPad ทุกเครื่องอีกรอบ

### 4. ติดตั้งลง iPad (ทำทีละเครื่อง ครั้งเดียว)
1. ส่งไฟล์ `C:\Airbus\ssl-work\ipad\rtaf602-efb-root-ca.cer` ไปที่ iPad ด้วย AirDrop หรืออีเมล แล้วแตะเปิดไฟล์
2. ไปที่ **Settings → Profile Downloaded → Install**
3. ไปที่ **Settings → General → About → Certificate Trust Settings**
   แล้วเปิดสวิตช์ **RTAF602 EFB Root CA** ⚠️ ถ้าลืมขั้นนี้ จะ sync ไม่ได้
4. ในแอป **FS+ Manager** ตั้ง ADDRESS เป็นชื่อจากข้อ 2 แล้วลอง sync ด้วย Test user

ถ้าหน่วยมี MDM ใช้ push ไฟล์ `.cer` นี้แทนการทำทีละเครื่องได้

---

## ต่ออายุ (ประมาณทุก 2 ปี)

สคริปต์บอกวันหมดอายุตอนรันเสร็จ ให้ลงปฏิทินเตือนล่วงหน้า 1 เดือน เมื่อถึงเวลาให้รันคำสั่งเดิม:
```powershell
.\Setup-LanSsl.ps1
```
แล้วใส่รหัสผ่านเดิม **ไม่ต้องทำอะไรกับ iPad**
ควรรันในช่วงที่ไม่มีใคร sync เพราะ Wildfly จะ restart

---

## ถ้ามีปัญหา

| อาการ | วิธีแก้ |
|---|---|
| สคริปต์ขึ้น `[FAIL]` | รันใหม่ด้วย `.\Setup-LanSsl.ps1 -ShowDetails` เพื่อดูรายละเอียด |
| `keystore password was incorrect` | ใส่รหัสผ่านไม่ตรงกับครั้งแรก |
| `does not resolve` | ยังไม่ได้ทำข้อ 2 หรือพิมพ์ชื่อใน `config.ps1` ผิด |
| Wildfly ไม่ start หลังติดตั้ง | `.\scripts\99-Rollback.ps1` เพื่อคืนค่าเดิม แล้วดู `[Wildfly]\standalone\log\server.log` |
| iPad sync ไม่ได้ | ตรวจว่า iPad อยู่ Wi-Fi วงเดียวกัน, เปิดสวิตช์ Certificate Trust Settings แล้ว และ ADDRESS เป็นชื่อ ไม่ใช่ IP |
| ทดสอบจาก iPad | เปิด Safari ไปที่ `https://<ชื่อ>:<port>/fsa-gateway` ต้องไม่มีคำเตือน |

---

## รายละเอียดทางเทคนิค

สคริปต์ทำตามข้อกำหนดใน Installation Guide V5.6.1 RevA (10.3, 11.4) และ Release Note:
keystore ใช้ alias `mach9` และ storetype PKCS12, แก้ `gatewayKeyStore` / `gatewayKeyManager` ใน `standalone.xml`
(สำรองไฟล์ไว้ก่อนทุกครั้ง) และใบรับรองผ่านข้อกำหนดของ iOS (≤ 825 วัน, SAN, EKU serverAuth, RSA 2048, SHA-256)

```
Setup-LanSsl.ps1                  คำสั่งเดียว: ทำครั้งแรก / ต่ออายุ
config.example.ps1                ค่าตั้งต้น (คัดลอกเป็น config.ps1)
scripts/99-Rollback.ps1           คืน standalone.xml จาก backup
scripts/04-Test-Gateway.ps1       ทดสอบ HTTPS และวันหมดอายุ
scripts/01-03, scripts/ca/*.ps1   ขั้นตอนย่อยที่ Setup-LanSsl.ps1 เรียกใช้
```
