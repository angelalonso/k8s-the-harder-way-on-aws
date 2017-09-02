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
CIDR_OTHER="10.200.0.0/16"
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

auth_config() {

echo "CONFIGURING AUTH!"

K8S_PUBLIC_ADDRESS=${ELB_DNS}
#kubelet Kubernetes Configuration File
for i in $(seq -w $NR_WORKERS); do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=${CA_FOLDR}/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config set-credentials system:node:worker${i} \
    --client-certificate=${CA_FOLDR}/worker${i}.pem \
    --client-key=${CA_FOLDR}/worker${i}-key.pem \
    --embed-certs=true \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:worker${i} \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config use-context default --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig
done

#kube-proxy Kubernetes Configuration File
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_FOLDR}/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=${CA_FOLDR}/kube-proxy.pem \
  --client-key=${CA_FOLDR}/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig

for i in $(seq -w $NR_WORKERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/worker${i}.kubeconfig ${CA_FOLDR}/kube-proxy.kubeconfig ubuntu@${WORKER_IP_PUB[$i]}:~/
done

}

testing() {
  echo
}

auth_config
#testing
