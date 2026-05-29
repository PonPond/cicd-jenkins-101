# Jenkins controller สำหรับเดโมบนเครื่อง — ฝัง docker CLI + docker compose + plugins + JCasC
# (ไม่มี kubectl/kustomize เพราะ repo นี้ deploy เป็น Docker container ไม่ใช้ Kubernetes)
FROM jenkins/jenkins:lts-jdk17

USER root

ARG DOCKER_VER=27.3.1
ARG COMPOSE_VER=2.29.7

# โหลด docker CLI (binary static) + docker compose v2 ตรงจาก official —
# วิธีนี้ชัวร์กว่า apt และ `docker --version` ท้าย RUN จะทำให้ build ล้มทันทีถ้าโหลดไม่สำเร็จ
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*; \
    arch="$(uname -m)"; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${arch}/docker-${DOCKER_VER}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /usr/local/bin --strip-components=1 docker/docker; \
    rm /tmp/docker.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VER}/docker-compose-linux-${arch}" \
         -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; \
    docker --version; \
    docker compose version

# ติดตั้ง plugins ตามรายการ
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# ข้าม setup wizard และชี้ไปยังไฟล์ JCasC
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml

USER jenkins
