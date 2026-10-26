# fsa-gateway – SSL certificate สำหรับ Flysmart+ for iPad Gateway

ติดตั้งใบรับรอง SSL ให้ Flysmart+ Gateway V5.6.1 ที่ **`rtaf602fsagateway.com`**
ใช้ใบรับรอง **Sectigo PositiveSSL** ซื้อจาก Namecheap ซึ่งเป็น CA ที่น่าเชื่อถือตามที่คู่มือ NAVBLUE กำหนด
(Installation Guide 10.3, 11.4) iPad เชื่อถือใบรับรองนี้ได้ทันที **ไม่ต้องติดตั้งอะไรลง iPad**

เงื่อนไขการใช้งาน: iPad sync ได้เมื่อ **เครื่อง Gateway เปิดอยู่** และ **iPad ต่อ Wi-Fi วงเดียวกับเครื่อง Gateway**

> ⚠️ repo นี้เป็น public ห้าม commit ไฟล์ `.jks` `.crt` `config.ps1` หรือรหัสผ่าน
> สคริปต์เก็บไฟล์ทั้งหมดไว้ที่ `C:\Airbus\ssl-work` ซึ่งอยู่นอก repo

ค่าใช้จ่ายประมาณ 16–20 USD ต่อปี (โดเมนประมาณ 10–15 USD + PositiveSSL ประมาณ 6 USD)

---

## ทำครั้งแรก

### 1. ตั้ง IP ตายตัวให้เครื่อง Gateway
ใน router ให้จอง IP (DHCP reservation) เช่น `192.168.1.200`
ถ้า router ไม่มีเมนูนี้ ให้ตั้งที่เครื่อง Gateway เอง: Settings → Network → IP assignment → **Manual**
แล้วเลือก IP ที่อยู่นอกช่วงที่ router แจกอัตโนมัติ ส่วน Subnet mask, Gateway และ DNS ให้ใช้ค่าเดียวกับที่ `ipconfig /all` แสดงอยู่ตอนนี้

### 2. ซื้อบน Namecheap
1. ค้นหา `rtaf602fsagateway.com` แล้วกด **Add to cart**
   เปิด Domain Privacy (ฟรี) และ Auto-Renew **ไม่ต้องซื้อของเสริม** เช่น PremiumDNS, Email หรือ Hosting
2. เมนู **Security → SSL Certificates → Domain Validation → PositiveSSL** (ใบธรรมดา ไม่ใช่ Wildcard หรือ Multi-Domain)
   แนะนำซื้อ 2–3 ปี จะได้ราคาต่อปีถูกกว่า และ reissue ได้ฟรีภายใน subscription
3. Checkout

### 3. ตั้ง DNS
Namecheap → Domain List → Manage `rtaf602fsagateway.com` → **Advanced DNS** → Add New Record

| Type | Host | Value |
|---|---|---|
| A Record | `@` | `192.168.1.200` (IP เครื่อง Gateway) |

ลบ record ตัวอย่างที่ Namecheap ใส่มาให้ทิ้ง (เช่น `www` CNAME หรือ URL Redirect)
ตรวจจากคอมในที่ทำงานด้วย `nslookup rtaf602fsagateway.com` ต้องได้ `192.168.1.200`

### 4. เตรียมเครื่อง Gateway
PowerShell แบบ **Run as administrator**:
```powershell
cd C:\Airbus
git clone https://github.com/rtaf602/fsa-gateway.git
cd fsa-gateway
copy config.example.ps1 config.ps1
notepad config.ps1        # ตรวจ WildflyPath, WildflyServiceName, HttpsPort
Set-ExecutionPolicy -Scope Process Bypass
```

### 5. สร้าง CSR
```powershell
.\scripts\01-New-Csr.ps1
```
- สคริปต์จะให้ตั้งรหัสผ่าน **จดเก็บไว้** ห้ามมี `< > " = / # : & ' \` หรือช่องว่าง
- CSR จะถูกคัดลอกลง clipboard ให้อัตโนมัติ ส่วน private key อยู่ในไฟล์ `.jks` บนเครื่องแล้ว ไม่ต้องใช้ไฟล์ `.key`

### 6. Activate บน Namecheap
Account → **SSL Certificates** → **Activate**
1. Domain: `rtaf602fsagateway.com`
2. เลือก **Manage SSL manually**
3. วาง CSR ช่อง Primary domain ต้องขึ้นเป็น `rtaf602fsagateway.com`
4. DCV method: **CNAME record** แล้วใส่อีเมล → **Submit**
5. หน้า Details จะแสดง CNAME Host และ Target ให้ไปที่ **Advanced DNS** แล้วเพิ่ม **CNAME Record**
   (ช่อง Host ให้ตัด `.rtaf602fsagateway.com` ท้ายชื่อออก)
6. รอ 15–60 นาที จนสถานะเป็น **Active** แล้วกด **Download** (ถ้าถามประเภทเซิร์ฟเวอร์ ให้เลือก Tomcat หรือ Other)

### 7. ติดตั้งและทดสอบ
แตก ZIP จะได้ `rtaf602fsagateway_com.crt` และ `rtaf602fsagateway_com.ca-bundle` จากนั้นรัน:
```powershell
.\scripts\02-Import-Certificate.ps1 -CertFile C:\Downloads\rtaf602fsagateway_com.crt `
                                     -ChainFile C:\Downloads\rtaf602fsagateway_com.ca-bundle
.\scripts\03-Install-Keystore.ps1
.\scripts\04-Test-Gateway.ps1
```
- `03` จะสำรอง `standalone.xml` แก้ค่าที่จำเป็น แล้ว restart Wildfly
- `04` ต้องขึ้น `[OK] Certificate is valid and trusted.`

### 8. ตั้ง iPad
ในแอป **FS+ Manager** ตั้ง ADDRESS เป็น `rtaf602fsagateway.com` และพอร์ต HTTPS ของ Gateway
แล้วลอง sync ด้วย Test user ก่อน

---

## ต่ออายุ (ทุก ≤ 200 วัน และทุก ≤ 100 วันตั้งแต่ มี.ค. 2027)

กฎนี้ใช้กับทุก CA ซื้อแพ็กเกจหลายปีก็ต้อง reissue ตามรอบ
`04-Test-Gateway.ps1` แสดงจำนวนวันที่เหลือ และเตือนเมื่อเหลือน้อยกว่า 30 วัน

1. `.\scripts\01-New-Csr.ps1`
2. Namecheap → SSL Certificates → ใบรับรองเดิม → **Reissue** → วาง CSR ใหม่ → ยืนยัน CNAME ตามที่ระบบแจ้ง
3. ดาวน์โหลดไฟล์ใหม่ แล้วรัน `02` → `03` → `04` เหมือนขั้นที่ 7

ไม่ต้องทำอะไรกับ iPad ควรทำในช่วงที่ไม่มีใคร sync เพราะ Wildfly จะ restart

---

## ถ้ามีปัญหา

| อาการ | วิธีแก้ |
|---|---|
| `keystore password was incorrect` | รหัสผ่านไม่ตรงกับที่ตั้งตอน `01` |
| `Public keys in reply and keystore don't match` | ใบรับรองออกจาก CSR ตัวอื่น ให้ reissue ด้วย CSR ล่าสุด |
| `certificate chain length is 1` | ลืมใส่ `-ChainFile` (.ca-bundle) |
| `RemoteCertificateNameMismatch` | iPad หรือผู้ทดสอบเข้าด้วย IP แทนชื่อ `rtaf602fsagateway.com` |
| `nslookup` ไม่ได้ IP | ตรวจ A record ใน Namecheap หรือ router บล็อก DNS ที่ชี้ไป IP ภายใน (DNS rebinding protection) |
| Wildfly ไม่ start | `.\scripts\99-Rollback.ps1` แล้วดู `[Wildfly]\standalone\log\server.log` |

---

## โครงสร้าง repo

```
config.example.ps1                ค่าตั้งต้น (คัดลอกเป็น config.ps1)
scripts/01-New-Csr.ps1            สร้าง key (alias mach9, PKCS12) + CSR
scripts/02-Import-Certificate.ps1 นำใบรับรองจาก CA เข้า keystore และตรวจ chain/ชื่อ
scripts/03-Install-Keystore.ps1   ติดตั้งลง Wildfly + แก้ standalone.xml + restart
scripts/04-Test-Gateway.ps1       ทดสอบ HTTPS แบบเดียวกับ iPad + วันหมดอายุ
scripts/99-Rollback.ps1           คืน standalone.xml จาก backup
Setup-LanSsl.ps1, scripts/ca/     ทางเลือกสำรอง: ใช้ CA ของหน่วยเอง (ฟรี อายุประมาณ 2 ปี
                                  แต่ต้องติดตั้งไฟล์ลง iPad ทุกเครื่อง และไม่ตรงตามคู่มือ NAVBLUE)
```
