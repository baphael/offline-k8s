#!/bin/bash

SCRIPT_PATH="$(dirname $(realpath -- $0))"

IMAGES_PATH="${SCRIPT_PATH}/images"

mkdir -p "${IMAGES_PATH}"
cd "${IMAGES_PATH}"

K8S_IMAGES=(
"k8simage/kube-apiserver:v1.23.1"
"k8simage/kube-proxy:v1.23.1"
"k8simage/kube-controller-manager:v1.23.1"
"k8simage/kube-scheduler:v1.23.1"
"k8simage/kube-state-metrics:v2.3.0"
"k8simage/metrics-server:v0.5.2"
"k8simage/etcd:3.5.1-0"
"k8simage/coredns:v1.8.6"
"k8simage/pause:3.6"
"calico/node:release-v3.22"
"calico/cni:release-v3.22"
"calico/kube-controllers:release-v3.22"
"calico/pod2daemon-flexvol:release-v3.22"
)

for img in "${K8S_IMAGES[@]}"; do
 docker image pull "${img}"
 #Remove image prefix and suffix
 IMAGE_FILE="$(echo $img|sed -r 's/^.*\/(.*):.*/\1/')"
 docker image save "${img}" > "${IMAGE_FILE}"
done

cd "${SCRIPT_PATH}"

tar -cvzf "images.tar.gz" "${IMAGES_PATH}"

rm -rf "${IMAGES_PATH}"

#Clean images from local machine
#for img in "${K8S_IMAGES[@]}"; do
# docker image rm "${img}"
#done
