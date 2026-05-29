# cicd-jenkins-101

`cicd-jenkins-101` เป็นโปรเจกต์ตัวอย่าง (demo) ที่สาธิต **CI/CD pipeline ระดับ
โปรดักชันด้วย Jenkins** แบบครบในเครื่องมือเดียว — Jenkins ทำทั้งฝั่ง **CI**
(build / test / scan) และฝั่ง **CD** (deploy ลง Kubernetes เองด้วย `kubectl`
แบบ push-based) ครอบคลุมตั้งแต่การ commit โค้ดไปจนถึงการนำขึ้นใช้งานบน
production ประกอบด้วยด่านตรวจสอบคุณภาพ, การสแกนความปลอดภัยของ supply chain,
การทดสอบประสิทธิภาพด้วย k6, การจัดการ environment ด้วย Kustomize และด่านอนุมัติ
production โดยบุคคล

> **repo คู่กัน:** [**cicd-gitops-101**](https://github.com/PonPond/cicd-gitops-101)
> ใช้ **GitHub Actions** เป็น CI และ **ArgoCD (GitOps)** เป็น CD —
> repo นั้น deploy แบบ *pull* (ArgoCD ดึงจาก git) ส่วน repo นี้ deploy แบบ
> *push* (Jenkins สั่ง `kubectl` เอง) เป็นตัวอย่างของ delivery สองแนวทางบนแอป
> ชุดเดียวกัน

ตัวแอปพลิเคชันถูกออกแบบให้เรียบง่ายโดยตั้งใจ เนื่องจากจุดสำคัญของโปรเจกต์นี้อยู่ที่
**delivery pipeline** มิใช่ตัวแอปพลิเคชัน

## ภาพรวม pipeline

```
push เข้า main ─▶ Jenkins job "cicd-jenkins-101"
   Lint ─▶ Test ─▶ Security (npm audit + Trivy) ─▶ k6 perf gate
        ─▶ Build & Push image (GHCR + Trivy image scan)
        ─▶ Deploy to staging  (kubectl apply -k → namespace demo-staging)

job "promote-to-production" (สั่งเอง) ─▶ input อนุมัติ ─▶ Deploy to production (kubectl)
```

ฝั่ง CD เป็นแบบ **push** — Jenkins ถือ kubeconfig แล้วสั่ง `kubectl apply` ลง cluster
โดยตรง (ไม่มี ArgoCD)

## เจาะลึกแต่ละขั้น (อ้างอิงไฟล์จริง)

ทั้งหมดนิยามไว้ใน [`Jenkinsfile`](Jenkinsfile) และ
[`jenkins/Jenkinsfile.promote`](jenkins/Jenkinsfile.promote)

### ขั้นที่ 1 — Lint / Test / Security / k6 (ด่านคุณภาพ)

- **Lint** และ **Test** รันในคอนเทนเนอร์ `node:20` ผ่าน `npm ci` → `npm run lint` และ `npm run test:ci`
- **Security** ทำงาน 2 อย่างแบบขนาน (`parallel`):
  - `npm audit --omit=dev --audit-level=high` — ตรวจ dependency ที่ใช้งานจริง
  - **Trivy** สแกนไฟล์ (`fs`) ที่ระดับ `HIGH,CRITICAL` พบแล้ว exit ทันที
- **k6 perf gate** — build image แล้วรันใน container จริง, รอ `/readyz` พร้อม จากนั้นรัน k6 `smoke` และ `load` (ไม่ผ่านหากค่า p95 หรืออัตรา error เกิน SLO)

### ขั้นที่ 2 — Build & Push (สร้าง artifact)

- คำนวณ **tag = `sha-` ตามด้วย 7 อักขระแรกของ commit** (เช่น `sha-abc1234`)
- `docker login ghcr.io` ด้วย credential `github-pat` แล้ว build จาก `app/` และ push 2 tag (`:sha-xxxxxxx`, `:latest`)
- **Trivy** สแกน image ที่เพิ่ง push (`HIGH,CRITICAL`) หากพบช่องโหว่จะไม่ปล่อยต่อ

### ขั้นที่ 3 — Deploy to staging (CD แบบ push)

- ใช้ `kustomize edit set image` ชี้ overlay ไปยัง image tag ที่เพิ่ง build
- Jenkins ใช้ credential `kubeconfig` แล้วสั่ง `kustomize build k8s/overlays/staging | kubectl apply -f -` ลง namespace `demo-staging`
- รอ `kubectl rollout status` จนกว่า deployment จะพร้อม

### ขั้นที่ 4 — Promote ขึ้น production (โดยบุคคล)

- job แยกชื่อ `promote-to-production` (สั่งงานเอง พร้อมระบุ `IMAGE_TAG` ที่ผ่าน staging แล้ว)
- มีด่าน **`input`** ให้กดอนุมัติก่อน — pipeline จะหยุดรอจนกว่าจะมีคนกด Promote
- เมื่ออนุมัติแล้ว Jenkins `kubectl apply` overlay `production` ลง namespace `demo-production`

### ขั้นที่ 5 — กรณี production เกิดปัญหา: rollback

- รัน job `promote-to-production` อีกครั้งด้วย `IMAGE_TAG` ของเวอร์ชันเดิมที่ดีอยู่
- Jenkins `kubectl apply` ทับด้วย image เก่า — ไม่ต้อง build ใหม่ เพราะ image เดิมยังอยู่ใน GHCR
- (หรือใช้ `kubectl rollout undo deploy/cicd-jenkins-101-production -n demo-production` เพื่อย้อน revision ทันที)

## เปรียบเทียบกับเวอร์ชัน GitOps

แอป / ชุดทดสอบ / Kustomize เหมือนกันทั้งสอง repo ต่างกันที่ "ใครสั่งงาน" และ "deploy อย่างไร"

| หัวข้อ | repo นี้ — Jenkins (push) | [cicd-gitops-101](https://github.com/PonPond/cicd-gitops-101) — Actions + ArgoCD (pull) |
| --- | --- | --- |
| ตัวสั่ง CI | Jenkins (`Jenkinsfile`) | GitHub Actions (`.github/workflows`) |
| ตัว deploy (CD) | **Jenkins สั่ง `kubectl` เอง** | **ArgoCD** ดึง manifest จาก git |
| โมเดล deploy | push-based | pull-based (GitOps) |
| แหล่งความจริงของ cluster | คำสั่ง `kubectl` ครั้งล่าสุด | git (ArgoCD reconcile ตลอด) |
| ด่านอนุมัติ production | `input` step | GitHub Environment reviewers |
| เก็บ secret | Jenkins Credentials | GitHub Secrets |
| config ระบบ CI | **JCasC** + Job DSL ([`jenkins/`](jenkins/)) | ไฟล์ workflow |

## การรัน Jenkins บนเครื่อง

**ต้องมี:** Docker (Docker Desktop), `make`

```bash
make jenkins-up        # ยก Jenkins → http://localhost:8088  (admin / admin)
make jenkins-logs      # ดู log ระหว่างบูต (ครั้งแรกโหลด plugin สักครู่)
make jenkins-down      # ปิด
```

JCasC จะสร้าง job ให้อัตโนมัติ 2 ตัว: `cicd-jenkins-101` (CI/CD หลัก) และ `promote-to-production`

> **credential ที่ต้องตั้ง** (Manage Jenkins → Credentials):
> - `github-pat` — GitHub PAT (scope `write:packages`) สำหรับ push image ขึ้น GHCR
>   *(ตั้งผ่าน env ได้: `GH_TOKEN=ghp_xxx make jenkins-up`)*
> - `kubeconfig` — Secret file = kubeconfig ของ cluster ปลายทาง สำหรับขั้น deploy
>
> ด่าน Lint / Test / Security / k6 รันได้ทันทีโดยไม่ต้องมี credential
> ส่วน Build & Push ต้องมี `github-pat` และ Deploy ต้องมี `kubeconfig`

> **หมายเหตุ networking:** เมื่อ Jenkins รันในคอนเทนเนอร์แต่ cluster เป็น kind บน host
> kubeconfig ต้องชี้ไปยัง API server ที่คอนเทนเนอร์เข้าถึงได้ (เช่น `kind get kubeconfig --internal`
> หรือใช้ `host.docker.internal`) — เป็นรายละเอียดของสภาพแวดล้อม ไม่ใช่ของ pipeline

## โครงสร้างโปรเจกต์

```
app/                  Node (Express) service + เทส + Dockerfile
tests/k6/             k6 smoke / load / stress (ใช้ SLO threshold ร่วมกัน)
k8s/
  base/               Kustomize base (Deployment, Service, HPA)
  overlays/staging/    overlay staging (namespace demo-staging)
  overlays/production/ overlay production (namespace demo-production)
Jenkinsfile           CI/CD หลัก (lint → test → security → k6 → build → push → deploy staging)
jenkins/
  Jenkinsfile.promote โหมด promote production (มี input อนุมัติ)
  docker-compose.yml  ยก Jenkins บนเครื่อง
  Dockerfile          Jenkins controller + docker CLI + kustomize + kubectl
  casc.yaml           Jenkins Configuration as Code (สร้าง job + credential)
  plugins.txt         รายการ plugin
Makefile              คำสั่งสำหรับ dev, k6, kind/deploy และ jenkins-up/down
```

## การจัดการแอปและ deploy (บนเครื่อง)

```bash
make install            # ติดตั้ง dependency
make test               # unit test + coverage
make docker-build       # build image cicd-jenkins-101:dev

# deploy ลง cluster ในเครื่อง (ต้องมี kind + kubectl + kustomize)
make demo               # kind cluster + deploy overlay staging (ดึง image จาก GHCR)
make deploy-production  # deploy overlay production
make clean              # ลบ kind cluster
```

## การนำไปใช้ต่อ (fork)

manifest ตั้งค่าไว้สำหรับบัญชี **`ponpond`** (image
`ghcr.io/ponpond/cicd-jenkins-101`) หากนำไปใช้กับบัญชีของท่านเอง ให้ปรับให้ชี้มา
ยังบัญชีของท่าน:

```bash
grep -rl ponpond . --exclude-dir=.git | xargs sed -i '' 's/ponpond/<your-username>/g'   # macOS
```

จากนั้น:

1. **สร้าง lockfile**: รัน `make install` แล้ว commit `app/package-lock.json`
2. เพิ่ม credential `github-pat` (PAT scope `write:packages`) และ `kubeconfig` ใน Jenkins
3. ตั้งให้ GHCR package เป็น public หรือเพิ่ม imagePullSecret ใน cluster เพื่อให้ดึง image ได้

## เหตุผลเชิงออกแบบ (design decisions)

- **Jenkins ทำทั้ง CI และ CD** — pipeline เดียวจบตั้งแต่ build จนถึง deploy เป็นรูปแบบ push-based ที่ใช้กันแพร่หลายในองค์กร
- **build ครั้งเดียวแล้ว promote artifact เดิม** — image ที่ผ่าน staging คือ image ตัวเดียวกับที่นำขึ้น production
- **การป้องกันแบบหลายชั้นบน supply chain** — ตรวจ dependency, สแกนไฟล์, สแกน image และใช้ runtime แบบ distroless + non-root
- **กำหนดให้ประสิทธิภาพเป็นด่านหนึ่ง** — k6 threshold ทำให้ pipeline ไม่ผ่านเมื่อ latency หรือ error เกิน SLO
- **ด่านอนุมัติโดยบุคคลก่อนขึ้น production** — `input` step หยุดรอการอนุมัติ ป้องกันการ deploy production โดยไม่ตั้งใจ
- **ระบบ CI เองก็เป็นโค้ด** — Jenkins ทั้งชุดนิยามด้วย JCasC + Job DSL จึงสร้างใหม่ได้เหมือนเดิมทุกครั้ง

## สัญญาอนุญาต (License)

MIT
