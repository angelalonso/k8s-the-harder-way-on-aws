#!/usr/bin/env bash

#VARS
MYIP=$(curl ipinfo.io/ip)
FOLDR="~/k8s-aws"
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"
CA_FOLDR="${FOLDR}/ca"
AWSPROF="test-k8s" # Profile in your ~/.aws config file

STACK="af-k8s"
ENTRY="hw.af-k8s.fodpanda.com"
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
  echo "CONFIGURING WORKERS"
  #TODO: this does not work
 # kubectl --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig get componentstatuses
#kubectl get nodes --output=jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address} {.spec.podCIDR} {"\n"}{end}'
# it does not get the pod cidr

 # This was moved outside the loop to avoid duplicated work

cat > ${CA_FOLDR}/99-loopback.conf <<EOF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF
cat > ${CA_FOLDR}/crio.service <<EOF
[Unit]
Description=CRI-O daemon
Documentation=https://github.com/kubernetes-incubator/cri-o

[Service]
ExecStart=/usr/local/bin/crio
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
cat > ${CA_FOLDR}/kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --cluster-cidr=${CIDR_CLUSTER} \\
  --kubeconfig=/var/lib/kube-proxy/kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for i in $(seq -w $NR_WORKERS); do
  # Install the cri-o OS Dependencies
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo add-apt-repository -y ppa:alexlarsson/flatpak && \
    sudo apt-get update && \
    sudo apt-get install -y socat libgpgme11 libostree-1-1"

  # download and install worker binaries
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "wget -q --show-progress --https-only --timestamping \
    https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
    https://github.com/opencontainers/runc/releases/download/v1.0.0-rc4/runc.amd64 \
    https://storage.googleapis.com/kubernetes-the-hard-way/crio-amd64-v1.0.0-beta.0.tar.gz \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kubectl \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-proxy \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kubelet"
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mkdir -p \
    /etc/containers \
    /etc/cni/net.d \
    /etc/crio \
    /opt/cni/bin \
    /usr/local/libexec/crio \
    /var/lib/kubelet \
    /var/lib/kube-proxy \
    /var/lib/kubernetes \
    /var/run/kubernetes"
  # NOTE: I had to manually re-install runc on one of the nodes. It segfaulted but the others didnt (?)
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/ && \
    tar -xvf crio-amd64-v1.0.0-beta.0.tar.gz && \
    chmod +x kubectl kube-proxy kubelet runc.amd64 && \
    sudo mv runc.amd64 /usr/local/bin/runc && \
    sudo mv crio crioctl kpod kubectl kube-proxy kubelet /usr/local/bin/ && \
    sudo mv conmon pause /usr/local/libexec/crio/"

#TODO: Check where this really is used for
  CIDR_POD="10.200.${i}.0/24"
  cat > ${CA_FOLDR}/10-bridge.conf.worker${i} <<EOF
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${CIDR_POD}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
  # Configure CNI networking
  scp -i ${SSHKEY} ${CA_FOLDR}/10-bridge.conf.worker${i} ${CA_FOLDR}/99-loopback.conf ${CA_FOLDR}/crio.service ubuntu@${WORKER_IP_PUB[$i]}:~/
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv 10-bridge.conf.worker${i} 10-bridge.conf ; sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/"

  # Configure the CRI-O Container Runtime
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv crio.conf seccomp.json /etc/crio/ && \
    sudo mv policy.json /etc/containers/"

  # Configure the kubelet
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv worker${i}-key.pem worker${i}.pem /var/lib/kubelet/ && \
    sudo mv worker${i}.kubeconfig /var/lib/kubelet/kubeconfig && \
    sudo mv ca.pem /var/lib/kubernetes/"

  cat > ${CA_FOLDR}/kubelet.service.worker${i} <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=crio.service
Requires=crio.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --cluster-dns=10.32.0.10 \\
  --cluster-domain=cluster.local \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/crio.sock \\
  --enable-custom-metrics \\
  --image-pull-progress-deadline=2m \\
  --image-service-endpoint=unix:///var/run/crio.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --pod-cidr=${CIDR_POD} \\
  --register-node=true \\
  --require-kubeconfig \\
  --runtime-request-timeout=10m \\
  --tls-cert-file=/var/lib/kubelet/worker${i}.pem \\
  --tls-private-key-file=/var/lib/kubelet/worker${i}-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i ${SSHKEY} ${CA_FOLDR}/kubelet.service.worker${i} ubuntu@${WORKER_IP_PUB[$i]}:~/kubelet.service

  #Configure the Kubernetes Proxy
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig"

  scp -i ${SSHKEY} ${CA_FOLDR}/kube-proxy.service ubuntu@${WORKER_IP_PUB[$i]}:~/
  # NOTE: hostname MUST be workerX for the node to register successfully
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo mv crio.service kubelet.service kube-proxy.service /etc/systemd/system/ && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable crio kubelet kube-proxy && \
    sudo systemctl start crio kubelet kube-proxy"
done

for i in $(seq -w $NR_MASTERS); do
  #TODO: ERROR: his command gets no resources
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "kubectl get nodes"

done
}


testing() {
  echo
  kubectl --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig get componentstatuses
}
workers
#testing
