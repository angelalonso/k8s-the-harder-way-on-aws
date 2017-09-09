#!/bin/bash

AWSPROF="test-k8s" # Profile in your ~/.aws config file
STACK="af-k8s"
DOMAIN="fodpanda.com"
AZS="us-west-2a,us-west-2b,us-west-2c"

export AWS_PROFILE=${AWSPROF}
export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}

delete() {
   kops delete cluster kops.${STACK}.${DOMAIN} --yes
}

delete
