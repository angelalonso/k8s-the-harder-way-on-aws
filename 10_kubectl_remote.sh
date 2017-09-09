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

kubectl_remote() {
  echo "Configuring Kubectl for remote access"
  K8S_PUBLIC_ADDRESS=${ENTRY}
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=${CA_FOLDR}/ca.pem \
    --embed-certs=true \
    --server=https://${K8S_PUBLIC_ADDRESS}:6443
  kubectl config set-credentials admin \
    --client-certificate=${CA_FOLDR}/admin.pem \
    --client-key=${CA_FOLDR}/admin-key.pem
  kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin
  kubectl config use-context kubernetes-the-hard-way
}

testing() {
  echo
}

kubectl_remote
#testing
