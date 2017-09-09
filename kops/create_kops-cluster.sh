#!/bin/bash

AWSPROF="test-k8s" # Profile in your ~/.aws config file
STACK="af-k8s"
DOMAIN="fodpanda.com"
AZS="us-west-2a,us-west-2b,us-west-2c"
MASTERAZS="us-west-2a,us-west-2b,us-west-2c"

export AWS_PROFILE=${AWSPROF}
export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}

create() {
  echo "You'll need to prepare:"
  echo " - subdomain delegation for ${STACK}.${DOMAIN}"
  echo " - S3 bucket named clusters.${STACK}.${DOMAIN}"

  kops create cluster \
    --master-count 1 \
    --node-count 3 \
    --zones ${AZS} \
    --node-size t2.small \
    --master-size t2.small \
    kops.${STACK}.${DOMAIN}

   echo "NOTE:"
   echo "run the following instead to create your cluster:"
   echo "export AWS_PROFILE=${AWSPROF}; export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}; kops update cluster kops.${STACK}.${DOMAIN} --yes"
}

create
