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

etcd_bootstrap() {
  echo "BOOTSTRAPPING ETCD!"

for i in $(seq -w $NR_MASTERS); do
  # Install etcd binaries
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "wget -q --show-progress --https-only --timestamping \
    https://github.com/coreos/etcd/releases/download/v3.2.6/etcd-v3.2.6-linux-amd64.tar.gz"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "tar -xvf etcd-v3.2.6-linux-amd64.tar.gz"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mv etcd-v3.2.6-linux-amd64/etcd* /usr/local/bin/"
  # Configure etcd server
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mkdir -p /etc/etcd /var/lib/etcd"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/"

  ETCD_NAME[$i]=master$i

  cat > ${CA_FOLDR}/etcd.service.${ETCD_NAME[$i]} <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME[$i]} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${MASTER_IP_INT[$i]}:2380 \\
  --listen-peer-urls https://${MASTER_IP_INT[$i]}:2380 \\
  --listen-client-urls https://${MASTER_IP_INT[$i]}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls https://${MASTER_IP_INT[$i]}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
EOF
LINE="  --initial-cluster "
for j in $(seq -w $NR_MASTERS); do
  LINE="${LINE}master$j=https://${MASTER_IP_INT[$j]}:2380"
  if [ $j -lt $NR_MASTERS ]; then
    LINE="${LINE},"
  else
    LINE="${LINE} \\"
  fi
done
echo ${LINE} >> ${CA_FOLDR}/etcd.service.${ETCD_NAME[$i]}
  cat >> ${CA_FOLDR}/etcd.service.${ETCD_NAME[$i]} <<EOF
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i ${SSHKEY} ${CA_FOLDR}/etcd.service.${ETCD_NAME[$i]} ubuntu@${MASTER_IP_PUB[$i]}:~/etcd.service

  # Start the ETCD server
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mv etcd.service /etc/systemd/system/ && \
    sudo systemctl daemon-reload && \
    sudo systemctl enable etcd && \
    sudo systemctl start etcd"
  # Verify
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "ETCDCTL_API=3 etcdctl member list"

done

}

testing() {
  echo
}

etcd_bootstrap
#testing
