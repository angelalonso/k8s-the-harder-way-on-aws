#!/bin/bash
# Based on https://icicimov.github.io/blog/virtualization/Kubernetes-Cluster-in-AWS-with-Kops/

# Source our aws environment
# needed in my case??
SOURCE_ENV="./aws.conf"
[[ -f ${SOURCE_ENV} ]] && . ${SOURCE_ENV}

export NAME="af-k8s.internal"
export AWS_PROFILE=${AWSPROF}
export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}
#export KOPS_FEATURE_FLAGS="+UseLegacyELBName"
#export KOPS_FEATURE_FLAGS="+DrainAndValidateRollingUpdate"
# needed?
#export VPC_ID="vpc-xxxxxxxx"
export NETWORK_CIDR="10.99.0.0/20"
export ZONES="us-west-2a,us-west-2b,us-west-2c"
export SSH_PUBLIC_KEY="~/.ssh/ec2key-pub.pem"
# needed?
#export ADMIN_ACCESS="[${NETWORK_CIDR},210.10.195.106/32,123.243.200.245/32]"
export DNS_ZONE_PRIVATE_ID="ZXXXXXXXXXXXY"
export DNS_ZONE_ID="ZXXXXXXXXXXXXI"
export NODE_SIZE="t2.micro"
export NODE_COUNT=6
export MASTER_SIZE="t2.small"
export MASTER_COUNT=3
export KUBERNETES_VERSION="1.7.4"




create() {
  echo "You'll need to prepare:"
  echo " - subdomain delegation for ${STACK}.${DOMAIN}"
  echo " - S3 bucket named clusters.${STACK}.${DOMAIN}"

kops create cluster \
    --name "${NAME}" \
    --cloud aws \
    --kubernetes-version ${KUBERNETES_VERSION} \
    --cloud-labels "Environment=\"tftest\",Type=\"k8s\",Role=\"node\",Provisioner=\"kops\"" \
    --node-count ${NODE_COUNT} \
    --master-count ${MASTER_COUNT} \
    --zones "${ZONES}" \
    --master-zones "${ZONES}" \
    --dns-zone "${DNS_ZONE_PRIVATE_ID}" \
    --dns private \
    --node-size "${NODE_SIZE}" \
    --master-size "${MASTER_SIZE}" \
    --topology private \
    --network-cidr "${NETWORK_CIDR}" \
    --networking calico \
    # needed?
   # --vpc "${VPC_ID}" \
    --ssh-public-key ${SSH_PUBLIC_KEY}
  kops create cluster \
    --master-count 3 \
    --node-count 3 \
    --zones ${AZS} \
    --node-size t2.micro \
    --master-size t2.small \
    kops.${STACK}.${DOMAIN}

   echo "NOTE:"
   echo "run the following instead to create your cluster:"
   echo "export AWS_PROFILE=${AWSPROF}; export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}; kops update cluster kops.${STACK}.${DOMAIN} --yes"
}

create
