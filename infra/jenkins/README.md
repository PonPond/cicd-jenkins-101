# Jenkins (infra)

ชุด docker compose สำหรับ **ลง Jenkins บนเซิร์ฟเวอร์จริง** — มี docker CLI +
docker compose + plugins + JCasC ติดมาในตัว และออกแบบให้ **ข้อมูลไม่หายแม้ลบ volume**

> ต่างจากโฟลเดอร์ [`../../jenkins/`](../../jenkins) ที่ไว้เดโม pipeline บนเครื่อง —
> โฟลเดอร์นี้คือ "ตัว Jenkins server" ที่เอาไปรันจริง

## ⭐ ทำไมลบ volume แล้วข้อมูลไม่หาย

เราเก็บ `JENKINS_HOME` ด้วย **bind mount ไปโฟลเดอร์บน host** (ไม่ใช่ named volume):

```yaml
volumes:
  - ${JENKINS_HOME_DIR:-./data/jenkins_home}:/var/jenkins_home   # ← โฟลเดอร์บน host จริง
```

ผลคือข้อมูลอยู่บนดิสก์ของเซิร์ฟเวอร์โดยตรง — คำสั่งพวกนี้ **ไม่แตะข้อมูลเลย**:

| คำสั่ง | named volume | bind mount (ที่เราใช้) |
| --- | --- | --- |
| `docker compose down` | คงอยู่ | ✅ คงอยู่ |
| `docker compose down -v` | **ถูกลบ** | ✅ คงอยู่ |
| `docker volume rm` / `prune` | **ถูกลบ** | ✅ คงอยู่ (ไม่ใช่ volume) |
| ลบ/สร้าง container ใหม่ | คงอยู่ | ✅ คงอยู่ |

เสริมอีกชั้น: config ของ Jenkins เป็นโค้ดใน `casc.yaml` + `plugins.txt` → ต่อให้
ลบทุกอย่างทิ้ง สร้างใหม่ก็ได้ค่าเดิมกลับมา (เก็บโฟลเดอร์นี้ไว้ใน git)

## การติดตั้งบนเซิร์ฟเวอร์

ต้องมี: Docker + Docker Compose v2 บนเซิร์ฟเวอร์

```bash
# 1. ก๊อปโฟลเดอร์นี้ขึ้นเซิร์ฟเวอร์ แล้วตั้งค่า
cp .env.example .env
nano .env                      # ตั้ง JENKINS_ADMIN_PASSWORD, JENKINS_URL, (GH_TOKEN ถ้าใช้)

# 2. สร้างโฟลเดอร์เก็บข้อมูล (จะอยู่นอก docker volume)
mkdir -p data/jenkins_home

# 3. build + run
docker compose up -d --build

# 4. ดู log จนขึ้น "Jenkins is fully up and running"
docker compose logs -f
```

เปิด `JENKINS_URL` (เช่น `http://your-server:8080`) → ล็อกอินด้วย admin / รหัสใน `.env`

## คำสั่งที่ใช้บ่อย

```bash
docker compose ps                 # สถานะ
docker compose logs -f            # ดู log
docker compose restart            # รีสตาร์ท
docker compose up -d --build      # อัปเดต/รีบิลด์ (ข้อมูลคงอยู่)
docker compose down               # หยุด (ข้อมูลคงอยู่)
docker exec jenkins docker --version   # เช็คว่า Jenkins สั่ง docker ได้
```

## สำรองข้อมูล (backup)

ข้อมูลทั้งหมดอยู่ในโฟลเดอร์เดียว — แค่ tar เก็บไว้:

```bash
tar czf jenkins-backup-$(date +%F).tgz -C "$JENKINS_HOME_DIR" .
# กู้คืน: แตกกลับเข้าโฟลเดอร์เดิม แล้ว docker compose up -d
```

## อัปเกรด Jenkins

แก้ tag ใน `Dockerfile` (`FROM jenkins/jenkins:lts-jdk17`) แล้ว:
```bash
docker compose up -d --build      # ข้อมูลใน bind mount คงอยู่ครบ
```

## หมายเหตุด้านความปลอดภัย (production)

- ตอนนี้รัน `user: root` เพื่อให้เข้าถึง bind mount + docker.sock ง่าย — เหมาะกับเซิร์ฟเวอร์ CI ภายใน
  หากต้องการ **non-root**: เปลี่ยนเจ้าของโฟลเดอร์เป็น UID 1000 (`chown -R 1000:1000 data/jenkins_home`),
  เอา `user: root` ออก, แล้วเพิ่มสิทธิ docker.sock ด้วย `group_add: ["<docker gid>"]`
- mount docker.sock = ให้สิทธิเทียบเท่า root บน host — ใช้เฉพาะกับ job ที่เชื่อถือได้
- แนะนำวาง **reverse proxy + HTTPS** (เช่น Caddy/Nginx/Traefik) หน้า Jenkins และจำกัดพอร์ต 8080 ไว้ภายใน
- เปลี่ยน `JENKINS_ADMIN_PASSWORD` เป็นรหัสที่แข็งแรง และพิจารณาใช้ `matrix-auth` สำหรับสิทธิแบบละเอียด
