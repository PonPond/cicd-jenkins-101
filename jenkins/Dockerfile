# Jenkins controller สำหรับเดโมบนเครื่อง — ฝัง docker CLI + kustomize + kubectl + plugins + JCasC
FROM jenkins/jenkins:lts-jdk17

USER root

# docker CLI (คุยกับ docker daemon ของ host ผ่าน socket ที่ mount เข้ามา) + kustomize + kubectl
RUN apt-get update \
 && apt-get install -y --no-install-recommends docker.io curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl -sSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash \
 && mv kustomize /usr/local/bin/kustomize \
 && ARCH="$(dpkg --print-architecture)" \
 && curl -sSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -sSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl

# ติดตั้ง plugins ตามรายการ
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# ข้าม setup wizard และชี้ไปยังไฟล์ JCasC
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml

USER jenkins
