# การจำกัดให้เฉพาะทีมเข้าถึง Jenkins ด้วย VPN

เป้าหมาย: เปิด Jenkins ให้ **เฉพาะทีมของเรา** เข้าได้ คนนอกมองไม่เห็นด้วยซ้ำ —
ทำได้ด้วย VPN โดยที่ Jenkins ยังคง bind กับ `127.0.0.1` (ไม่เปิดพอร์ตสู่สาธารณะ)

> หลักการ: VPN คุมที่ **"ตัวคน/อุปกรณ์"** ไม่ใช่ IP ตำแหน่ง — ทีมเข้าได้จากที่ไหนก็ได้
> (บ้าน/มือถือ/คาเฟ่) ส่วนคนนอกต่อโดเมน/IP ก็ไม่ติด เพราะพอร์ตไม่ได้เปิดออกเน็ต

มี 2 ทางเลือก: **Tailscale** (ง่ายสุด แนะนำ) และ **WireGuard** (self-host เต็มตัว)

---

## ตัวเลือก A — Tailscale (แนะนำ)

ข้อดี: ไม่ต้องเปิดพอร์ตสาธารณะ, ไม่ต้องแจกไฟล์คีย์, เพิ่ม/ลบคนคลิกเดียว,
ได้ HTTPS ในตัว (ไม่ต้องมีโดเมน/Let's Encrypt)

### 1. ติดตั้งบนเซิร์ฟเวอร์ Jenkins

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up              # เปิดลิงก์ไป login → เครื่องเข้า tailnet, ได้ IP 100.x.y.z + ชื่อ MagicDNS
```

### 2. ให้เข้า Jenkins ผ่าน tailnet (เลือกอย่างใดอย่างหนึ่ง)

**ก) `tailscale serve` — ได้ HTTPS ฟรีในตัว (ง่ายสุด)**
```bash
sudo tailscale serve --bg 8080
# เข้าได้ที่ https://<machine>.<tailnet>.ts.net  (เฉพาะคนใน tailnet)
```
> ตั้ง `JENKINS_URL=https://<machine>.<tailnet>.ts.net/` ใน `.env` ให้ตรง

**ข) เข้าผ่าน Tailscale IP ตรง ๆ** — คง `BIND_ADDR=127.0.0.1` แล้วเข้าที่ `http://100.x.y.z:8080`
(ต้องให้ Jenkins ฟังบน tailscale IP ด้วย เช่นตั้ง `BIND_ADDR=100.x.y.z`)

### 3. เชิญทีมเข้า tailnet

- Admin console → **Users → Invite** (ส่งลิงก์ หรือใส่อีเมล)
- ถ้าทีมใช้ Google Workspace / GitHub org เดียวกัน → แค่ให้ login ด้วยบัญชีนั้น
- สมาชิกลงแอป Tailscale (Mac/Win/Linux/iOS/Android) → login → เข้า tailnet อัตโนมัติ
- **ไม่มีการส่งไฟล์คีย์ใด ๆ**

### 4. จำกัดให้เห็นเฉพาะ Jenkins (ACL)

ใน Admin console → Access Controls:
```json
{
  "groups": { "group:devs": ["alice@example.com", "bob@example.com"] },
  "tagOwners": { "tag:jenkins": ["group:devs"] },
  "acls": [
    { "action": "accept", "src": ["group:devs"], "dst": ["tag:jenkins:8080,443"] }
  ]
}
```
(ติด tag เครื่อง Jenkins: `sudo tailscale up --advertise-tags=tag:jenkins`)

### 5. เปิด device approval (ออปชัน)

Admin → Settings → เปิด **Device approval** → อุปกรณ์ใหม่ต้องให้แอดมินกดอนุมัติก่อน

### 6. ถอนสิทธิ

ลบ user/device ใน admin console → ตัดการเข้าถึงทันที ไม่ต้องแก้ไฟล์ที่เซิร์ฟเวอร์

---

## ตัวเลือก B — WireGuard (self-host) + wg-easy

ถ้าต้องการ self-host เต็มตัว ใช้ **wg-easy** (web UI จัดการ WireGuard + แจก config/QR)

### 1. เพิ่ม service ใน `docker-compose.yml`

```yaml
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:14
    container_name: wg-easy
    restart: unless-stopped
    environment:
      WG_HOST: ${WG_HOST}              # โดเมน/IP สาธารณะของเซิร์ฟเวอร์
      PASSWORD_HASH: ${WG_PASSWORD_HASH} # รหัสเข้าหน้า admin (bcrypt)
      WG_DEFAULT_DNS: "1.1.1.1"
    volumes:
      - ./data/wireguard:/etc/wireguard
    ports:
      - "51820:51820/udp"                       # WireGuard tunnel (เปิดสู่สาธารณะ)
      - "127.0.0.1:51821:51821"                 # หน้า admin UI (เข้าผ่าน SSH tunnel)
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
```

### 2. แจกจ่ายให้ทีม

- เปิดหน้า admin (ผ่าน SSH tunnel: `ssh -L 51821:localhost:51821 user@server` → `http://localhost:51821`)
- กด **+ New Client** ต่อสมาชิก 1 คน (1 client = 1 คน ห้ามใช้ร่วม)
- ให้ไฟล์ `.conf` หรือสแกน **QR code** (สำหรับมือถือ)
- ⚠️ ไฟล์ `.conf` มี private key — ส่งผ่านช่องปลอดภัย (password manager/encrypted) อย่าส่ง email เปล่า

### 3. ให้ Jenkins เห็นเฉพาะใน VPN

- คง `BIND_ADDR=127.0.0.1` หรือ bind กับ IP ของ WireGuard subnet (เช่น `10.8.0.1`)
- ทีมต่อ WireGuard ก่อน → เข้า `http://10.8.0.1:8080`

### 4. ถอนสิทธิ

ในหน้า wg-easy กดลบ client ของคนนั้น → ตัดการเข้าถึงทันที

---

## เทียบสั้น ๆ

| | Tailscale | WireGuard + wg-easy |
| --- | --- | --- |
| เปิดพอร์ตสาธารณะ | ไม่ต้อง | ต้องเปิด UDP 51820 |
| แจกให้ทีม | เชิญด้วยอีเมล/SSO (ไม่มีไฟล์) | สร้าง client + ส่ง .conf/QR ต่อคน |
| HTTPS | มีในตัว (`tailscale serve`) | ต้องทำ proxy เพิ่มเอง |
| เพิ่ม/ลบคน | คลิกใน admin | คลิกใน wg-easy |
| เหมาะกับ | ทีมที่อยากง่าย | ทีมที่อยาก self-host |

## สรุป

- **เฉพาะทีม + อยากง่าย → Tailscale** (`tailscale serve` ได้ HTTPS ฟรี ไม่ต้องมีโดเมน)
- **อยาก self-host → WireGuard + wg-easy**
- ทั้งคู่: Jenkins ยัง bind `127.0.0.1` (ไม่เปิดสาธารณะ) — VPN เป็นทางเข้าเดียวสำหรับทีม
