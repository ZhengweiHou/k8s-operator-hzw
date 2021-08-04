kubeadm init \
 --apiserver-advertise-address=192.168.32.100 \
 --image-repository registry.aliyuncs.com/google_containers \
 --kubernetes-version v1.19.0 \
 --service-cidr=10.10.0.0/16 \
 --pod-network-cidr=10.244.0.0/16
