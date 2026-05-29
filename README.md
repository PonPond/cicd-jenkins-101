# cicd-gitops-jenkins-101

`cicd-gitops-jenkins-101` เป็นโปรเจกต์ตัวอย่าง (demo) ที่สาธิต **CI/CD + GitOps
pipeline ระดับโปรดักชัน** โดยใช้ **Jenkins** เป็นตัวขับเคลื่อน CI ครอบคลุมตั้งแต่การ
commit โค้ดไปจนถึงการนำขึ้นใช้งานบน production ประกอบด้วยด่านตรวจสอบคุณภาพ
(quality gate), การสแกนความปลอดภัยของ supply chain, การทดสอบประสิทธิภาพด้วย k6,
การจัดการ environment ด้วย Kustomize และการ deploy แบบ GitOps ผ่าน ArgoCD ซึ่ง
กำหนดให้ production ต้องผ่านการอนุมัติโดยบุคคล

> เป็น repo คู่กับ [**cicd-gitops-101**](https://github.com/PonPond/cicd-gitops-101)
> ซึ่งเป็น pipeline เดียวกันแต่ขับเคลื่อนด้วย **GitHub Actions** — repo ทั้งสองใช้
> แอป, ชุดทดสอบ, Kustomize และ ArgoCD ชุดเดียวกัน ต่างกันที่ "ตัวสั่งงาน CI" เท่านั้น
> จึงเปรียบเทียบแนวคิดเดียวกันบนคนละเครื่องมือได้โดยตรง

ตัวแอปพลิเคชันถูกออกแบบให้เรียบง่ายโดยตั้งใจ เนื่องจากจุดสำคัญของโปรเจกต์นี้อยู่ที่
**delivery pipeline** มิใช่ตัวแอปพลิเคชัน

## ภาพรวม pipeline

```
push เข้า main ─▶ Jenkins job "cicd-gitops-jenkins-101"
   Lint ─▶ Test ─▶ Security (npm audit + Trivy) ─▶ k6 perf gate
        ─▶ Build & Push (GHCR + Trivy image scan)
        ─▶ Promote staging (kustomize edit set image → git commit)
ArgoCD ตรวจพบ commit ─▶ auto-sync STAGING

job "promote-to-production" (สั่งเอง) ─▶ input อนุมัติ ─▶ bump prod overlay ─▶ git commit
ArgoCD production = manual-sync ─▶ กด Sync เพื่อ deploy
```

## เจาะลึกแต่ละขั้น (อ้างอิงไฟล์จริง)

ทั้งหมดนิยามไว้ใน [`Jenkinsfile`](Jenkinsfile) (declarative pipeline) และ
[`jenkins/Jenkinsfile.promote`](jenkins/Jenkinsfile.promote)

### ขั้นที่ 1 — Lint / Test / Security / k6 (ด่านคุณภาพ)

- **Lint** และ **Test** รันในคอนเทนเนอร์ `node:20` ผ่าน `npm ci` → `npm run lint` และ `npm run test:ci`
- **Security** ทำงาน 2 อย่างแบบขนาน (`parallel`):
  - `npm audit --omit=dev --audit-level=high` — ตรวจ dependency ที่ใช้งานจริง
  - **Trivy** สแกนไฟล์ (`fs`) ที่ระดับ `HIGH,CRITICAL` พบแล้ว exit ทันที (ข้ามรายการที่ยังไม่มีแพตช์)
- **k6 perf gate** — build image แล้วรันใน container จริง, รอ `/readyz` พร้อม จากนั้นรัน k6 `smoke` และ `load` (ไม่ผ่านหากค่า p95 หรืออัตรา error เกิน SLO)

### ขั้นที่ 2 — Build & Push (สร้าง artifact)

- คำนวณ **tag = `sha-` ตามด้วย 7 อักขระแรกของ commit** (เช่น `sha-abc1234`)
- `docker login ghcr.io` ด้วย credential `github-pat` แล้ว build จาก `app/` และ push 2 tag (`:sha-xxxxxxx`, `:latest`)
- **Trivy** สแกน image ที่เพิ่ง push (`HIGH,CRITICAL`) หากพบช่องโหว่จะไม่ปล่อยต่อ

### ขั้นที่ 3 — Promote staging (หัวใจ GitOps)

- `kustomize edit set image` ปรับ image tag ใน `gitops/overlays/staging`
- `jenkins-bot` commit และ push การเปลี่ยนแปลงกลับเข้า git → ArgoCD ([`argocd/staging.yaml`](argocd/staging.yaml)) ตั้งเป็น auto-sync จึงปรับ cluster ให้ตรงโดยอัตโนมัติ

### ขั้นที่ 4 — Promote ขึ้น production (โดยบุคคล)

- job แยกชื่อ `promote-to-production` (สั่งงานเอง พร้อมระบุ `IMAGE_TAG`)
- มีด่าน **`input`** ให้กดอนุมัติก่อน (เทียบเท่า GitHub Environment required reviewers)
- เมื่ออนุมัติแล้ว bump `gitops/overlays/production` แล้ว commit — ArgoCD production เป็น **manual-sync** จึงต้องกด **Sync** ใน ArgoCD อีกครั้ง

### ขั้นที่ 5 — กรณี production เกิดปัญหา: rollback ด้วย `git revert`

- ใช้ `git revert` กับ commit ที่ปรับ tag แล้ว push — ArgoCD จะ sync cluster กลับสู่เวอร์ชันเดิม
- ไม่ต้อง build ใหม่ เพราะ image เวอร์ชันเดิมยังอยู่ใน GHCR เพียงชี้ tag กลับ

## เปรียบเทียบ: GitHub Actions ↔ Jenkins

ทั้งสอง repo ทำสิ่งเดียวกัน ต่างกันที่กลไกของตัวสั่งงาน CI

| หัวข้อ | GitHub Actions ([repo](https://github.com/PonPond/cicd-gitops-101)) | Jenkins (repo นี้) |
| --- | --- | --- |
| นิยาม pipeline | `.github/workflows/*.yaml` | `Jenkinsfile` (Groovy, declarative) |
| สภาพแวดล้อมรัน | GitHub runner (managed) | Jenkins controller + agent (ดูแลเอง) |
| ด่านอนุมัติ production | GitHub Environment + required reviewers | `input` step |
| การเก็บ secret | GitHub Secrets | Jenkins Credentials + `withCredentials` |
| config ของระบบ CI | อยู่ในไฟล์ workflow | **JCasC** ([`jenkins/casc.yaml`](jenkins/casc.yaml)) + Job DSL |
| รันบนเครื่อง | (รันบน GitHub) | docker-compose ([`jenkins/`](jenkins/)) |
| app / gitops / argocd / k6 / Trivy | — เหมือนกันทั้งสอง repo — | |

## การรัน Jenkins บนเครื่อง

**ต้องมี:** Docker (Docker Desktop), `make`

```bash
# ยก Jenkins (controller + docker CLI + kustomize + plugins + JCasC)
make jenkins-up        # เปิด http://localhost:8088  (admin / admin)

# ดู log ระหว่างบูต (ครั้งแรกจะโหลด plugin สักครู่)
make jenkins-logs

# ปิด
make jenkins-down
```

JCasC จะสร้าง job ให้อัตโนมัติ 2 ตัว: `cicd-gitops-jenkins-101` (CI หลัก) และ
`promote-to-production`

> **หมายเหตุเรื่อง credential:** ด่าน Lint / Test / Security / k6 รันได้ทันที
> ส่วนด่าน **Build & Push** และ **Promote** ต้องมี credential `github-pat`
> (GitHub PAT scope `repo` + `write:packages`) ตั้งได้ 2 วิธี:
> - ส่งผ่าน env ตอนยก Jenkins: `GH_TOKEN=ghp_xxx make jenkins-up`
> - หรือเพิ่มใน UI: **Manage Jenkins → Credentials** (id: `github-pat`)

## โครงสร้างโปรเจกต์

```
app/                  Node (Express) service + เทส + Dockerfile
tests/k6/             k6 smoke / load / stress (ใช้ SLO threshold ร่วมกัน)
gitops/
  base/               Kustomize base (Deployment, Service, HPA)
  overlays/staging/    config staging (Jenkins ปรับ image tag ที่นี่อัตโนมัติ)
  overlays/production/ config production (promote โดยบุคคล)
argocd/               ArgoCD Application manifests (staging + production)
Jenkinsfile           CI หลัก (lint → test → security → k6 → build → push → bump overlay)
jenkins/
  Jenkinsfile.promote โหมด promote production (มี input อนุมัติ)
  docker-compose.yml  ยก Jenkins บนเครื่อง
  Dockerfile          Jenkins controller + docker CLI + kustomize
  casc.yaml           Jenkins Configuration as Code (สร้าง job + credential)
  plugins.txt         รายการ plugin
Makefile              คำสั่งสำหรับ dev, k6, kind/ArgoCD และ jenkins-up/down
```

## การจัดการแอปและ GitOps (บนเครื่อง)

```bash
make install            # ติดตั้ง dependency
make test               # unit test + coverage
make docker-build       # build image cicd-gitops-jenkins-101:dev

# รันระบบ GitOps บน cluster ในเครื่อง (ต้องมี kind + kubectl + argocd)
make demo               # kind cluster + ArgoCD + ลงทะเบียน Applications
make argocd-ui          # เปิด https://localhost:8080
make argocd-password
```

## การนำไปใช้ต่อ (fork)

manifest ทั้งหมดตั้งค่าไว้สำหรับบัญชี **`ponpond`** (image
`ghcr.io/ponpond/cicd-gitops-jenkins-101`, repo
`github.com/ponpond/cicd-gitops-jenkins-101`) หากนำไปใช้กับบัญชีของท่านเอง
ให้ปรับให้ชี้มายังบัญชีของท่าน:

```bash
grep -rl ponpond . --exclude-dir=.git | xargs sed -i '' 's/ponpond/<your-username>/g'   # macOS
```

จากนั้น:

1. **สร้าง lockfile**: รัน `make install` แล้ว commit `app/package-lock.json`
2. เพิ่ม credential `github-pat` ใน Jenkins (PAT scope `repo` + `write:packages`)
3. ตั้ง ArgoCD ฝั่ง production เป็น manual-sync (ตั้งไว้แล้วใน `argocd/production.yaml`)

## เหตุผลเชิงออกแบบ (design decisions)

- **GitOps แทนการ deploy แบบสั่งด้วยมือ** — git เป็น source of truth; Jenkins ไม่เข้าไปแก้ไข cluster โดยตรง; การ rollback ทำผ่าน `git revert`
- **build ครั้งเดียวแล้ว promote artifact เดิม** — image ที่ผ่าน staging คือ image ตัวเดียวกับที่นำขึ้น production
- **การป้องกันแบบหลายชั้นบน supply chain** — ตรวจ dependency, สแกนไฟล์, สแกน image และใช้ runtime แบบ distroless + non-root
- **กำหนดให้ประสิทธิภาพเป็นด่านหนึ่ง** — k6 threshold ทำให้ pipeline ไม่ผ่านเมื่อ latency หรือ error เกิน SLO
- **ระบบ CI เองก็เป็นโค้ด** — Jenkins ทั้งชุดนิยามด้วย JCasC + Job DSL จึงสร้างใหม่ได้เหมือนเดิมทุกครั้ง

## สัญญาอนุญาต (License)

MIT
