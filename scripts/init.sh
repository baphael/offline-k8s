#!/bin/bash

#PLEASE, MAKE SURE YOU EDITED ALL YAML FILES (in 'config/') FIRST !
#or, apply them afterwards...

if ! (( $(id -u) == 0 )); then
 echo "Run this script as root !"
 exit 1
fi

SCRIPT_PATH="$(dirname $(realpath -- $0))"

IPV4_PATTERN="(\d{1,3}\.){3}\d{1,3}"
IPV4_CIDR_PATTERN="${IPV4_PATTERN}/\d{1,2}"

#Move docker root path
#Docker data will be copied in a "docker" subfolder
#DOCKER_DATA_ROOT_PARENT_PATH="/var/lib"
#[[ "${DOCKER_DATA_ROOT_PARENT_PATH}" == */ ]] && DOCKER_DATA_ROOT_PARENT_PATH="${DOCKER_DATA_ROOT_PARENT_PATH::-1}"

JOIN_COMMAND_FILE="${SCRIPT_PATH}/join_command"
KUBECONFIG_FILE="${SCRIPT_PATH}/admin.conf"

# WARNING : adapt with your own iface name (ens0)
K8S_PUBLIC_IPV4=$(ip a show ens0 | grep -oP "${IPV4_PATTERN}" | head -1)
if ! (( $(echo "${K8S_PUBLIC_IPV4}" | grep -cP "^${IPV4_PATTERN}$") == 1 )); then
 echo "K8S_PUBLIC_IPV4 not in IPv4 format (${K8S_PUBLIC_IPV4}) !"
 exit 2
fi
K8S_PORT=443

K8S_VERSION=1.23.1

#Should match with ${SCRIPT_PATH}/../config/cni/calico/snat.yaml (IPPool spec.cidr)
#And not overlap with any internal IP subnet
K8S_PODS_CIDR=192.168.224.0/19
if ! (( $(echo "${K8S_PODS_CIDR}" | grep -cP "^${IPV4_CIDR_PATTERN}$") == 1 )); then
 echo "K8S_PODS_CIDR not in IPv4 CIDR format (${K8S_PODS_CIDR}) !"
 exit 3
fi
K8S_IMAGES_REPO=k8simage

#Set this to false to delete docker images right after they're loaded
#This will spare some space...
KEEP_IMAGES_AFTER_LOAD=true

#Deactivate swap
swapoff -a
#Comment swap line in automount (/etc/fstab) file
sed -ri "s/^([^#].*\bswap\b.*)/#\1/g" /etc/fstab
#Effective after reboot

#Clear iptables
iptables -F
iptables -X

#Install docker and deps
apt update
apt upgrade -y
apt install -y rsync apt-transport-https ca-certificates curl gnupg2 software-properties-common ethtool ebtables socat docker.io conntrack

#Configure docker daemon
cat <<EOF >/etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "data-root": "${DOCKER_DATA_ROOT_PARENT_PATH:-/var/lib}/docker"
}
EOF

systemctl stop docker
# optional : backup default docker data root
#rsync -av "/var/lib/docker" "${DOCKER_DATA_ROOT_PARENT_PATH}/"
#rm -rf /var/lib/docker
systemctl daemon-reload
systemctl start docker

#Install K8S deps
cd "${SCRIPT_PATH}/../images"
#Will break after first run... Improvise, adapt, overcome
tar -xvzf images.tar.gz && rm images.tar.gz
find . -type f ! -name "*.gz" -print0 | xargs -0rI % bash -c '
 docker image load < %
 if (( $? > 0 )); then
  echo "Something went wrong when loading docker image %. Please check !"
  exit 4
 else
  if [[ ${KEEP_IMAGES_AFTER_LOAD} == false ]]; then
   rm %
  fi
 fi
'
cd "${SCRIPT_PATH}/../debs"
dpkg -i cri-tools*.deb
apt --fix-broken install
dpkg -i kubernetes-cni*.deb
dpkg -i kubectl*.deb
dpkg -i kubelet*.deb
dpkg -i kubeadm*.deb
cd ..

#Init K8S cluster
kubeadm init --kubernetes-version=${K8S_VERSION} --apiserver-advertise-address=${K8S_PUBLIC_IPV4} --apiserver-bind-port=${K8S_PORT} --pod-network-cidr=${K8S_PODS_CIDR} --image-repository ${K8S_IMAGES_REPO} -v=5

#Config K8S CLI
cat <<EOF >>~/.bashrc
source <(kubectl completion bash)
source <(kubeadm completion bash)
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF

source ~/.bashrc

#Config K8S cluster
kubectl apply -f "${SCRIPT_PATH}/../config/cni/calico/calico.yaml"
chmod +x "${SCRIPT_PATH}/../calicoctl"
"${SCRIPT_PATH}/../calicoctl" apply -f "${SCRIPT_PATH}/../config/cni/calico/policy.yaml"
"${SCRIPT_PATH}/../calicoctl" apply -f "${SCRIPT_PATH}/../config/cni/calico/snat.yaml"
kubectl apply -f "${SCRIPT_PATH}/../config/adminuser.yaml"
kubectl apply -f "${SCRIPT_PATH}/../config/limitranges.yaml"
#kubectl apply -f "${SCRIPT_PATH}/../config/logging/fluentd.yaml"

echo "COPY THE FOLLOWING IN K8S NODES /etc/kubernetes/admin.conf FILE :"
echo "##########"
cat /etc/kubernetes/admin.conf | tee -a "${KUBECONFIG_FILE}"
echo "##########"

#for EAM
echo "Admin user token :"
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk "{print $1}") | grep -Po "token:\s+\K.+"

#Join command
kubeadm token create --print-join-command | tee -a "${JOIN_COMMAND_FILE}"
