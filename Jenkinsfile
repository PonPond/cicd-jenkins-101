// CI/CD pipeline (declarative) — Jenkins ทำทั้ง CI และ CD (push-based deploy)
// Jenkins build/test/scan → push image ขึ้น GHCR → deploy ลง cluster เองด้วย kubectl
//
// ต้องมี credential ใน Jenkins:
//   - github-pat : GitHub Personal Access Token (scope: write:packages) สำหรับ push image ขึ้น GHCR
//   - kubeconfig : Secret file = kubeconfig ของ cluster ปลายทาง สำหรับ kubectl deploy
//
// ดูวิธียก Jenkins บนเครื่อง: jenkins/docker-compose.yml (หรือ `make jenkins-up`)

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    REGISTRY = 'ghcr.io'
    IMAGE    = 'ghcr.io/ponpond/cicd-jenkins-101'
  }

  stages {
    // คำนวณ tag จาก commit
    stage('Prepare') {
      steps {
        script {
          env.TAG = 'sha-' + sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
        }
        echo "Image ที่จะ build: ${IMAGE}:${TAG}"
      }
    }

    // --- ด่านตรวจคุณภาพ ---
    stage('Lint') {
      agent { docker { image 'node:20'; reuseNode true } }
      steps { dir('app') { sh 'npm ci && npm run lint' } }
    }

    stage('Test') {
      agent { docker { image 'node:20'; reuseNode true } }
      steps { dir('app') { sh 'npm ci && npm run test:ci' } }
    }

    stage('Security') {
      parallel {
        stage('npm audit') {
          agent { docker { image 'node:20'; reuseNode true } }
          steps { dir('app') { sh 'npm audit --omit=dev --audit-level=high' } }
        }
        stage('Trivy filesystem') {
          agent {
            docker { image 'aquasec/trivy:0.58.0'; args '--entrypoint='; reuseNode true }
          }
          steps {
            sh 'trivy fs --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed --no-progress .'
          }
        }
      }
    }

    // --- ด่านวัดประสิทธิภาพด้วย k6 บน container จริง ---
    stage('k6 perf gate') {
      steps {
        sh '''
          set -e
          NET="ci-${BUILD_NUMBER}"
          APP="demo-${BUILD_NUMBER}"
          docker network create "$NET" >/dev/null 2>&1 || true
          docker build -t demo:ci-${BUILD_NUMBER} app
          docker run -d --name "$APP" --network "$NET" demo:ci-${BUILD_NUMBER}

          # รอจน service พร้อม (ตรวจ /readyz สูงสุด 30 วินาที)
          ready=false
          for i in $(seq 1 30); do
            if docker run --rm --network "$NET" curlimages/curl:8.11.1 \
                 -fsS "http://$APP:3000/readyz" >/dev/null 2>&1; then ready=true; break; fi
            sleep 1
          done
          [ "$ready" = true ] || { echo "service ไม่พร้อมใช้งาน"; docker logs "$APP"; exit 1; }

          # build k6 image ที่ฝัง test ไว้ เพื่อให้ relative import (../lib/options.js) ทำงาน
          printf 'FROM grafana/k6:0.55.0\\nCOPY tests/k6 /k6\\n' > k6.Dockerfile
          docker build -f k6.Dockerfile -t k6-ci:${BUILD_NUMBER} .

          docker run --rm --network "$NET" -e BASE_URL="http://$APP:3000" k6-ci:${BUILD_NUMBER} run /k6/smoke.js
          docker run --rm --network "$NET" -e BASE_URL="http://$APP:3000" k6-ci:${BUILD_NUMBER} run /k6/load.js
        '''
      }
      post {
        always {
          sh '''
            docker rm -f "demo-${BUILD_NUMBER}" >/dev/null 2>&1 || true
            docker network rm "ci-${BUILD_NUMBER}" >/dev/null 2>&1 || true
            docker rmi "demo:ci-${BUILD_NUMBER}" "k6-ci:${BUILD_NUMBER}" >/dev/null 2>&1 || true
            rm -f k6.Dockerfile
          '''
        }
      }
    }

    // --- สร้าง artifact: build → push GHCR → สแกน image ---
    stage('Build & Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-pat',
                         usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          sh '''
            set -e
            echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin
            docker build -t ${IMAGE}:${TAG} -t ${IMAGE}:latest app
            docker push ${IMAGE}:${TAG}
            docker push ${IMAGE}:latest
          '''
        }
        // สแกน image ที่เพิ่ง push (HIGH,CRITICAL → fail)
        sh '''
          docker run --rm aquasec/trivy:0.58.0 image \
            --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed --no-progress ${IMAGE}:${TAG}
        '''
      }
    }

    // --- CD: Jenkins deploy ลง staging เองด้วย kubectl (push-based) ---
    stage('Deploy to staging') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          sh '''
            set -e
            # ชี้ overlay ให้ใช้ image tag ที่เพิ่ง build
            ( cd k8s/overlays/staging && kustomize edit set image app=${IMAGE}:${TAG} )
            kubectl create namespace demo-staging --dry-run=client -o yaml | kubectl apply -f -
            kustomize build k8s/overlays/staging | kubectl apply -f -
            kubectl -n demo-staging rollout status deploy/cicd-jenkins-101-staging --timeout=180s
          '''
        }
      }
    }
  }

  post {
    success {
      echo "สำเร็จ: deploy ${IMAGE}:${TAG} ลง namespace demo-staging แล้ว"
    }
    failure {
      echo "ล้มเหลว: pipeline ไม่ผ่าน — staging ยังไม่ถูกอัปเดต"
    }
  }
}
