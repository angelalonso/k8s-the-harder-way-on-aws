#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

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
