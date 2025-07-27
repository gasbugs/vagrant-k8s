# /bin/bash
k8s_ver="1.33.0-00"

#################################
# 1. 스왑 끄기 
sudo swapoff -a # 현재 시스템에서만 적용
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab # 리부팅 후부터 시스템 적용
sudo sed -i 's|^/swap\.img|#/swap.img|' /etc/fstab # 리부팅 후부터 시스템 적용

#################################
# 2. 컨테이너 런타임 설치
sudo apt update && sudo apt install containerd -y
sudo ctr version

#################################
# 3. 컨테이너 런타임 설정
# iptables 설정
# k8s.conf 파일에 필요한 커널 모듈을 추가
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# overlay 네트워크와 br_netfilter 모듈을 즉시 로드
sudo modprobe overlay
sudo modprobe br_netfilter

# 쿠버네티스에 필요한 네트워크 설정을 sysctl 파일에 추가
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# 시스템 전체에 sysctl 설정을 적용
sudo sysctl --system

# containerd 설정 디렉토리 생성
sudo mkdir -p /etc/containerd

# containerd의 기본 설정을 파일로 저장
sudo containerd config default | sudo tee /etc/containerd/config.toml

# containerd 설정 파일에서 SystemdCgroup을 true로 변경
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# CRI 표준 인터페이스 활성화 (Disable 목록에서 삭제)
# disabled_plugins = []

# containerd 서비스 재시작
sudo systemctl restart containerd

#################################
# 4. kubeadm, kubelet, kubectl 설치
# kube_install.sh 파일을 생성하는 명령어 
cat <<EOF > kube_install.sh
# These instructions are for Kubernetes v1.33.
# Update the apt package index and install packages needed to use the Kubernetes apt repository:
sudo apt-get update

# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

#Note:
#In releases older than Debian 12 and Ubuntu 22.04, directory /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
#Add the appropriate Kubernetes apt repository. Please note that this repository have packages only for Kubernetes 1.33; for other Kubernetes minor versions, you need to change the Kubernetes minor version in the URL to match your desired minor version (you should also check that you are reading the documentation for the version of Kubernetes that you plan to install).

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update the apt package index, install kubelet, kubeadm and kubectl, and pin their version:
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

#(Optional) Enable the kubelet service before running kubeadm:
sudo systemctl enable --now kubelet
EOF

sudo bash kube_install.sh

# kubeadm, kubelet, kubectl 버전 확인
echo "Kubernetes versions:"
kubeadm version
kubectl version
kubelet --version
