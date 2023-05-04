#!/bin/bash

if ! (( $(id -u) == 0 )); then
 echo "Run this script as root !"
 exit 1
fi

SCRIPT_PATH="$(dirname $(realpath -- $0))"

#Move docker root path
#Docker data will be copied in a "docker" subfolder
#DOCKER_DATA_ROOT_PARENT_PATH="/var/lib"
#[[ "${DOCKER_DATA_ROOT_PARENT_PATH}" == */ ]] && DOCKER_DATA_ROOT_PARENT_PATH="${DOCKER_DATA_ROOT_PARENT_PATH::-1}"

JOIN_COMMAND_FILE="${SCRIPT_PATH}/join_command"
if ! [[ -s "${JOIN_COMMAND_FILE}" ]] || ! (( $(cat "${JOIN_COMMAND_FILE}"|wc -l) == 1 )) || ! (( $(grep -cP "^kubeadm\sjoin" "${JOIN_COMMAND_FILE}") == 1  )); then
  echo "Please copy the k8s cluster join command inside ${JOIN_COMMAND_FILE} first !"
  echo "Also, please check the file contains only one line beggining with 'kubeadm join'"
  exit 2
fi

KUBECONFIG_FILE="${SCRIPT_PATH}/admin.conf"

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
apt install -y rsync apt-transport-https ca-certificates curl gnupg2 software-properties-common ethtool ebtables socat docker.io

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
$(cat "${JOIN_COMMAND_FILE}")

if ! [[ -s "${KUBECONFIG_FILE}" ]]; then
 cp "${KUBECONFIG_FILE}" /etc/kubernetes/admin.conf
else
 echo "Please fetch K8S master /etc/kubernetes/admin.conf content and paste it in K8S worker /etc/kubernetes/admin.conf"
fi

#Config K8S CLI
cat <<EOF >>~/.bashrc
source <(kubectl completion bash)
source <(kubeadm completion bash)
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF

source ~/.bashrc
