#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

delete_all() {
  aws --profile=${AWSPROF} ec2 delete-key-pair --key-name ${STACK}-key
  # subnets
  # igw
  for i in $(seq -w $NR_MASTERS); do
    aws --profile=${AWSPROF} ec2 terminate-instances --instance-ids ${MASTER_ID[$i]}
  done
  for i in $(seq -w $NR_WORKERS); do
    aws --profile=${AWSPROF} ec2 terminate-instances --instance-ids ${WORKER_ID[$i]}
  done
  # TODO: wait until instances are gone
  aws --profile=${AWSPROF} elb delete-load-balancer --load-balancer-name ${ELB}
  aws --profile=${AWSPROF} ec2 delete-route-table --route-table-id ${RTB}

  aws --profile=${AWSPROF} ec2 delete-security-group --group-id ${SG}
  aws --profile=${AWSPROF} ec2 detach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPCID}
  aws --profile=${AWSPROF} ec2 delete-internet-gateway --internet-gateway-id ${IGW}
  aws --profile=${AWSPROF} ec2 delete-subnet --subnet-id ${SUBNET}
  aws --profile=${AWSPROF} ec2 delete-vpc --vpc-id ${VPCID}
  for i in $(seq -w $NR_MASTERS); do
    ssh-keygen -f "/home/aaf/.ssh/known_hosts" -R master$i
  done
  for i in $(seq -w $NR_WORKERS); do
    ssh-keygen -f "/home/aaf/.ssh/known_hosts" -R worker$i
  done
}

delete_all
