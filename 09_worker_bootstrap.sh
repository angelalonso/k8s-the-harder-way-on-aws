#!/usr/bin/env bash

#VARS
MYIP=$(curl ipinfo.io/ip)
FOLDR="~/k8s-aws"
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"
CA_FOLDR="${FOLDR}/ca"
AWSPROF="test-k8s" # Profile in your ~/.aws config file

STACK="af-k8s"
SSHKEY="$HOME/.ssh/$STACK-key.priv"
CIDR_VPC="10.240.0.0/16"
CIDR_SUBNET="10.240.0.0/24"
CIDR_CLUSTER="10.200.0.0/16"
#TODO: Check what this is really used for
K8S_DNS="10.32.0.10"

PORT_SSH="22"
# TODO: are these correct?
PORT_ETCD="2379"
PORT_ETCDCTL="2380"

AMI="ami-835b4efa"
INSTANCE_TYPE="t2.small"

NR_MASTERS=3
NR_WORKERS=3

mkdir -p ${FOLDR}

. ${CFG}


workers() {
  #TODO: this does not work
  echo "CONFIGURING WORKERS"
  kubectl --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig get componentstatuses

# Bootstrapping Kubernetes Workers
ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[1]} "kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap"

for i in $(seq -w $NR_WORKERS); do
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mkdir -p /var/lib/{kubelet,kube-proxy,kubernetes}"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mkdir -p /var/run/kubernetes && sudo mv bootstrap.kubeconfig /var/lib/kubelet"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy && sudo mv ca.pem /var/lib/kubernetes"
  # Install Docker
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.6.tgz"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "tar -xvf docker-1.12.6.tgz && sudo cp docker/docker* /usr/bin/"
  # Create the Docker systemd unit file:
cat > ${CA_FOLDR}/docker.service.worker$i <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
ExecStart=/usr/bin/docker daemon \\
  --iptables=false \\
  --ip-masq=false \\
  --host=unix:///var/run/docker.sock \\
  --log-level=error \\
  --storage-driver=overlay
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  # Start the docker service:
  scp -i ${SSHKEY} ${CA_FOLDR}/docker.service.worker$i ubuntu@${WORKER_IP_PUB[$i]}:/home/ubuntu/docker.service
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv docker.service /etc/systemd/system/docker.service"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl daemon-reload && sudo systemctl enable docker"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl start docker && sudo docker version"
  # Install the kubelet
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mkdir -p /opt/cni"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget https://storage.googleapis.com/kubernetes-release/network-plugins/cni-amd64-0799f5732f2a11b329d9e3d51b9c8f2e3759f2ff.tar.gz"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo tar -xvf cni-amd64-0799f5732f2a11b329d9e3d51b9c8f2e3759f2ff.tar.gz -C /opt/cni"
  # Download and install the Kubernetes worker binaries
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kubectl"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kube-proxy"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/kubelet"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "chmod +x kubectl kube-proxy kubelet && sudo mv kubectl kube-proxy kubelet /usr/bin/"
  # Create the kubelet systemd unit file:
  API_SERVERS=$(cat ${CA_FOLDR}/bootstrap.kubeconfig | grep server | cut -d ':' -f2,3,4 | tr -d '[:space:]')
cat > ${CA_FOLDR}/kubelet.service.worker$i <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/kubelet \\
  --api-servers=${API_SERVERS} \\
  --allow-privileged=true \\
  --cluster-dns=${K8S_DNS} \\
  --cluster-domain=cluster.local \\
  --container-runtime=docker \\
  --experimental-bootstrap-kubeconfig=/var/lib/kubelet/bootstrap.kubeconfig \\
  --network-plugin=kubenet \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --serialize-image-pulls=false \\
  --register-node=true \\
  --tls-cert-file=/var/lib/kubelet/kubelet-client.crt \\
  --tls-private-key-file=/var/lib/kubelet/kubelet-client.key \\
  --cert-dir=/var/lib/kubelet \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i ${SSHKEY} ${CA_FOLDR}/kubelet.service.worker$i ubuntu@${WORKER_IP_PUB[$i]}:/home/ubuntu/kubelet.service
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv kubelet.service /etc/systemd/system/kubelet.service"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl daemon-reload && sudo systemctl enable kubelet"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl start kubelet && sudo systemctl status kubelet --no-pager"

  # kube-proxy
cat > ${CA_FOLDR}/kube-proxy.service.worker$i <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-proxy \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --masquerade-all=true \\
  --kubeconfig=/var/lib/kube-proxy/kube-proxy.kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i ${SSHKEY} ${CA_FOLDR}/kube-proxy.service.worker$i ubuntu@${WORKER_IP_PUB[$i]}:/home/ubuntu/kube-proxy.service
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv kube-proxy.service /etc/systemd/system/kube-proxy.service"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl daemon-reload && sudo systemctl enable kube-proxy"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo systemctl start kube-proxy && sudo systemctl status kube-proxy --no-pager"

done

# ssh into one of the masters and, from there, List and approve the pending certificate requests:
ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[1]} "for i in $(kubectl get csr | grep -v NAME | cut -d' ' -f1); do kubectl certificate approve $i; done"

# Check that everything is fine
kubectl get nodes

}

kubectl_config() {
  echo
# Configuring the Remote Access Kubernetes Client
wget https://storage.googleapis.com/kubernetes-release/release/v1.7.0/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin

# K8S_PUBLIC_ADDRESS=${ELB_DNS}
# Build up the kubeconfig entry
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${K8S_PUBLIC_ADDRESS}:6443

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way

kubectl get componentstatuses
kubectl get nodes

}

network_config(){
 echo
## Create Routes
#TODO: find out which one is needed on AWS
#kubectl get nodes \
#  --output=jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address} {.spec.podCIDR} {"\n"}{end}'
# aws --profile=${AWSPROF} ec2 create-route --route-table-id ${RTB} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW}
# gcloud compute routes create kubernetes-route-10-200-0-0-24 \
#   --network kubernetes-the-hard-way \
#   --next-hop-address 10.240.0.20 \
#   --destination-range 10.200.0.0/24

}

dns_addon(){
## Deploying the Cluster DNS Add-on
kubectl create clusterrolebinding serviceaccounts-cluster-admin \
  --clusterrole=cluster-admin \
  --group=system:serviceaccounts

kubectl create -f yaml/svc_kubedns.yaml
kubectl --namespace=kube-system get svc

# Create the `kubedns` deployment:
kubectl create -f yaml/dply_kubedns.yaml
kubectl --namespace=kube-system get pods

}

testing() {
  echo
  kubectl --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig get componentstatuses
}
#workers
testing
