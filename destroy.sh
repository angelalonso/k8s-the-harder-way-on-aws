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
CIDR="10.4.0.0/16"
CIDR_MASTER="10.4.1.0/24"
CIDR_WORKER="10.4.2.0/24"
#TODO: Check what this is really used for
K8S_DNS="10.32.0.1"

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

testing() {
  aws --profile=${AWSPROF} ec2 delete-key-pair --key-name ${STACK}-key
  # subnets
  # igw
for i in $(seq -w $NR_MASTERS); do
  aws --profile=${AWSPROF} ec2 terminate-instances --instance-ids ${MASTER_ID[$i]}
done
for i in $(seq -w $NR_WORKERS); do
  aws --profile=${AWSPROF} ec2 terminate-instances --instance-ids ${WORKER_ID[$i]}
done
  aws --profile=${AWSPROF} ec2 delete-vpc --vpc-id ${VPCID}
}

testing
