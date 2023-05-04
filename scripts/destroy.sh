kubeadm reset
rm -rf /etc/kubernetes
rm -rf /root/.kube
rm -rf /home/*/.kube
rm -rf /etc/cni/net.d
iptables -F
iptables -X
#apt remove --purge docker.io
#rm -rf /etc/docker
#rm -rf /var/lib/docker #or /DATA/docker or anywhere else
