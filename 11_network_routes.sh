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

network_routes() {
  echo "Configuring Routes for POD network"
  # taken from https://github.com/squeed/rktnetes-the-hard-way/blob/master/docs/07-network.md
  for i in $(seq -w $NR_WORKERS); do
    aws --profile=${AWSPROF} ec2 create-route --route-table-id ${RTB} --destination-cidr-block 10.200.${i}.0/24 \
          --instance-id ${WORKER_ID[$i]}
  done
}

testing() {
  echo
}

network_routes
#testing
