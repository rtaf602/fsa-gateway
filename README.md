# fsa-gateway – SSL certificate สำหรับ Flysmart+ for iPad Gateway

สคริปต์ PowerShell สำหรับขอ ติดตั้ง ทดสอบ และต่ออายุใบรับรอง SSL แบบ DV ของ
**`efb-gateway.rtaf602.com`** บน Flysmart+ for iPad Gateway V5.6.1 (Wildfly)
ตามข้อกำหนดใน Installation Guide บทที่ 10.3 และ 11.4

> ⚠️ **Repo นี้เป็น public** ห้าม commit keystore (`.jks`/`.pfx`/`.p12`), private key,
> `config.ps1`, `standalone.xml` หรือรหัสผ่านใดๆ เด็ดขาด `.gitignore` กันไฟล์เหล่านี้ไว้แล้ว
> และสคริปต์เก็บไฟล์ทั้งหมดไว้ที่ `WorkRoot` (ค่าเริ่มต้น `C:\Airbus\ssl-work`) ซึ่งอยู่นอก repo

## ข้อกำหนดของ Gateway ที่สคริปต์รองรับให้แล้ว

| ข้อกำหนด (Installation Guide) | สคริปต์ทำให้ |
|---|---|
| ใบรับรองจาก CA ที่น่าเชื่อถือ ห้ามใช้ self-signed เมื่อเปิดออกอินเทอร์เน็ต (10.3) | ตรวจว่า issuer ≠ subject และ chain ครบ |
| ต้องใช้ชื่อโดเมน ห้ามใช้ IP (11.4) | ปฏิเสธถ้า `Domain` เป็น IP และตรวจ SAN |
| keystore ต้องมี alias `mach9` และ storetype `PKCS12` (11.4.1) | สร้างแบบนี้ตั้งแต่ต้น ไม่ต้องแปลงไฟล์ |
| แก้ `gatewayKeyStore` / `gatewayKeyManager` ใน `standalone.xml` แล้ว restart (11.4.3) | แก้เฉพาะ 3 ค่า สำรองไฟล์ก่อน แล้ว restart ให้ |
| รหัสผ่านห้ามมีอักขระพิเศษของ XML (Release Note: known issue) | ไม่รับ `< > " = / # : & ' \` และช่องว่าง |

## สิ่งที่ต้องมี

- Windows Server ที่ติดตั้ง Gateway แล้ว และตั้ง `JAVA_HOME` เป็น JDK ตัวเดียวกับที่ Wildfly ใช้ (คู่มือ 5.1.2)
  สคริปต์เรียก `keytool` จาก JDK ตัวนั้น เพื่อให้รูปแบบการเข้ารหัส PKCS12 เข้ากันได้
  (คู่มือ 11.4.1: ถ้าเป็น PBES2 ต้องใช้ JDK 1.8.0_311 ขึ้นไป)
- โดเมน `rtaf602.com` ที่หน่วยงานเป็นเจ้าของ และสิทธิ์แก้ DNS
- A record `efb-gateway.rtaf602.com` → IP ของ Gateway (ถ้าใช้เฉพาะภายใน ใส่ใน DNS ภายในได้)
- PowerShell 5.1 ขึ้นไป (มีมากับ Windows Server อยู่แล้ว)

## เริ่มใช้งาน (ครั้งแรก)

```powershell
git clone https://github.com/rtaf602/fsa-gateway.git C:\Airbus\fsa-gateway
cd C:\Airbus\fsa-gateway
copy config.example.ps1 config.ps1
notepad config.ps1          # ตรวจ WildflyPath, WildflyServiceName, HttpsPort
Set-ExecutionPolicy -Scope Process Bypass
```

## ขั้นตอน

### 1) สร้าง key และ CSR
```powershell
.\scripts\01-New-Csr.ps1
```
- สคริปต์ถามรหัสผ่าน keystore (อย่างน้อย 8 ตัว ห้ามมีอักขระต้องห้าม) ให้จดเก็บไว้ในที่ปลอดภัย
- จะได้ `C:\Airbus\ssl-work\<yyyyMMdd>\fsa-keystore-<yyyyMMdd>.jks` และ `gateway.csr`
  (คัดลอก CSR ลง clipboard ให้แล้ว)

### 2) ซื้อ DV SSL และยืนยันโดเมน
1. ซื้อ DV SSL แบบ single domain (เช่น Sectigo PositiveSSL) จาก reseller
2. ตอน activate ให้วาง CSR และถ้าระบบถามประเภทเซิร์ฟเวอร์ ให้เลือก **Tomcat** หรือ **Other**
3. ยืนยันโดเมนด้วย **DNS (CNAME/TXT)** ซึ่งเหมาะที่สุด เพราะ Gateway ไม่ต้องเปิดพอร์ต 80
4. ดาวน์โหลดไฟล์ที่ได้ เช่น `efb-gateway_rtaf602_com.crt` และ `efb-gateway_rtaf602_com.ca-bundle`

### 3) นำใบรับรองเข้า keystore
```powershell
.\scripts\02-Import-Certificate.ps1 -CertFile C:\Downloads\efb-gateway_rtaf602_com.crt `
                                     -ChainFile C:\Downloads\efb-gateway_rtaf602_com.ca-bundle
```
ถ้าได้ไฟล์ `.p7b` ที่มี chain ครบมาแล้ว ใช้ `-CertFile xxx.p7b` อย่างเดียวได้เลย
สคริปต์ตรวจให้ว่า alias `mach9` เป็น PrivateKeyEntry, chain ≥ 2 ใบ และ SAN ตรงกับโดเมน

### 4) ติดตั้งลง Wildfly (เปิด PowerShell แบบ Administrator)
```powershell
.\scripts\03-Install-Keystore.ps1
```
- สำรองไฟล์เป็น `standalone.xml.bak-<timestamp>`
- คัดลอก keystore ไปที่ `[Wildfly]\standalone\configuration\`
- แก้ `gatewayKeyStore` (path และรหัสผ่าน) และ `gatewayKeyManager` (รหัสผ่าน)
- restart service Wildfly แล้วรอจนพอร์ต HTTPS เปิด

ถ้าต้องการ restart เองในช่วงที่ไม่มีการ sync ใช้ `-NoRestart`

### 5) ทดสอบ
```powershell
.\scripts\04-Test-Gateway.ps1                     # จากเครื่องอื่นที่ resolve โดเมนได้
.\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1   # บนเครื่อง Gateway เอง
```
ต้องขึ้น `[OK] Certificate is valid and trusted.` จากนั้นทดสอบด้วย iPad จริง:
ตั้ง server address ใน FS+ Manager เป็น `efb-gateway.rtaf602.com` (ไม่ใช่ IP) แล้ว sync ด้วย Test user ก่อน

### ย้อนกลับ (ถ้า Wildfly ไม่ขึ้นหรือ iPad sync ไม่ได้)
```powershell
.\scripts\99-Rollback.ps1          # ใช้ backup ล่าสุด
```
keystore เดิมยังอยู่ที่เดิม เพราะไฟล์ใหม่ใช้ชื่อต่างกัน การย้อนกลับจึงแค่คืน `standalone.xml`

## การต่ออายุ

ใบรับรองหมดอายุ = **iPad ทุกเครื่อง sync ไม่ได้ทันที**

- ทำขั้นตอนที่ 1–5 ซ้ำทั้งหมดก่อนหมดอายุ สคริปต์สร้าง key ใหม่ในโฟลเดอร์ใหม่ทุกรอบ
- ปัจจุบันกฎ CA/Browser Forum ลดอายุสูงสุดของใบรับรองสาธารณะลงเรื่อยๆ
  แม้ซื้อแพ็กเกจหลายปี ก็ต้อง reissue และติดตั้งใหม่หลายครั้งต่อปี
- ตั้งการแจ้งเตือนอัตโนมัติด้วย Task Scheduler ให้รัน `04-Test-Gateway.ps1` ทุกวัน
  (exit code 1 = เหลือน้อยกว่า `WarnDays` วัน, 2 = ใบรับรองใช้ไม่ได้):
  ```powershell
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' `
       -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Airbus\fsa-gateway\scripts\04-Test-Gateway.ps1 -Server 127.0.0.1'
  Register-ScheduledTask -TaskName 'FSA Gateway SSL check' -Action $a `
       -Trigger (New-ScheduledTaskTrigger -Daily -At 8am) -User SYSTEM
  ```
  แล้วตั้งระบบ monitoring ที่มีอยู่ให้แจ้งเตือนเมื่อ task จบด้วย exit code ไม่ใช่ 0

## แก้ปัญหาที่พบบ่อย

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| `keystore password was incorrect` | รหัสผ่านไม่ตรงกับที่ตั้งในขั้นที่ 1 |
| `Public keys in reply and keystore don't match` | ใบรับรองออกจาก CSR ตัวอื่น ให้ใช้ `-Stamp <yyyyMMdd>` ชี้โฟลเดอร์ที่ถูก หรือ reissue ด้วย CSR ล่าสุด |
| `certificate chain length is 1` | ไม่ได้ใส่ `-ChainFile` (.ca-bundle) |
| `RemoteCertificateNameMismatch` | iPad/ผู้ทดสอบเข้าด้วย IP หรือชื่ออื่นที่ไม่ใช่ `efb-gateway.rtaf602.com` |
| `RemoteCertificateChainErrors` | ยังเป็น self-signed หรือ Wildfly ยังไม่ได้ restart |
| Wildfly ไม่ start | ดู `[Wildfly]\standalone\log\server.log` แล้วรัน `99-Rollback.ps1` |

## โครงสร้าง repo

```
config.example.ps1           ค่าตั้งต้น (คัดลอกเป็น config.ps1)
scripts/Common.ps1           ฟังก์ชันที่ใช้ร่วมกัน
scripts/01-New-Csr.ps1       สร้าง key (alias mach9, PKCS12) + CSR
scripts/02-Import-Certificate.ps1  นำใบรับรองจาก CA เข้า keystore และตรวจสอบ
scripts/03-Install-Keystore.ps1    ติดตั้งลง Wildfly + แก้ standalone.xml + restart
scripts/04-Test-Gateway.ps1  ทดสอบ TLS แบบเดียวกับฝั่ง client + เช็กวันหมดอายุ
scripts/99-Rollback.ps1      คืน standalone.xml จาก backup
```

อ้างอิง: Flysmart+ for iPad Gateway V5.6.1 Installation Guide RevA (10.3, 11.4) และ Release Note RevA
