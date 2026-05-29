# Jenkins controller สำหรับเดโมบนเครื่อง — ฝัง docker CLI + docker compose + plugins + JCasC
# (ไม่มี kubectl/kustomize เพราะ repo นี้ deploy เป็น Docker container ไม่ใช้ Kubernetes)
FROM jenkins/jenkins:lts-jdk17

USER root

# docker CLI (คุยกับ docker daemon ของ host ผ่าน socket ที่ mount เข้ามา) + docker compose v2
RUN apt-get update \
 && apt-get install -y --no-install-recommends docker.io curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /usr/local/lib/docker/cli-plugins \
 && curl -SL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose \
 && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ติดตั้ง plugins ตามรายการ
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# ข้าม setup wizard และชี้ไปยังไฟล์ JCasC
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml

USER jenkins
