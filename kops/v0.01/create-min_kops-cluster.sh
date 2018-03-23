#!/bin/bash
# Based on https://icicimov.github.io/blog/virtualization/Kubernetes-Cluster-in-AWS-with-Kops/


export STACK="af-k8s"
export DOMAIN="fodpanda.com"
export NAME="${STACK}.${DOMAIN}"
export AWS_PROFILE="test-k8s"
export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}
#export KOPS_FEATURE_FLAGS="+UseLegacyELBName"
#export KOPS_FEATURE_FLAGS="+DrainAndValidateRollingUpdate"
# needed?
#export VPC_ID="vpc-xxxxxxxx"
export NETWORK_CIDR="10.44.0.0/20"
export ZONES="us-west-2a,us-west-2b,us-west-2c"
export SSH_PUBLIC_KEY="~/.ssh/kops_rsa.pub"
# needed?
#export ADMIN_ACCESS="[${NETWORK_CIDR},210.10.195.106/32,123.243.200.245/32]"
export DNS_ZONE_PRIVATE_ID="Z22J8RVEAKU7B7"

# needed?
#export DNS_ZONE_ID="ZXXXXXXXXXXXXI"
export NODE_SIZE="t2.micro"
export NODE_COUNT=2
export MASTER_SIZE="t2.small"
export MASTER_COUNT=2
export KUBERNETES_VERSION="1.7.4"



info_before() {
  echo "You'll need to prepare:"
  echo " - subdomain delegation for ${STACK}.${DOMAIN}"
  echo " - S3 bucket named clusters.${STACK}.${DOMAIN}"
  echo " - a VPC (get its ID in this script as a variable)"
}

info_after() {
   echo "NOTE:"
   echo "run the following instead to create your cluster:"
   echo "export AWS_PROFILE=${AWS_PROFILE}; export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}; kops update cluster ${NAME} --yes"
}

create_min() {

info_before

kops create cluster \
#kops update cluster \
    --name "${NAME}" \
    --cloud aws \
    --ssh-public-key ${SSH_PUBLIC_KEY} \
    --kubernetes-version ${KUBERNETES_VERSION} \
    --cloud-labels "Environment=\"tftest\",Type=\"k8s\",Role=\"node\",Provisioner=\"kops\"" \
    --zones "${ZONES}"

#    --node-count ${NODE_COUNT} \
#    --master-count ${MASTER_COUNT} \
#    --master-zones "${ZONES}" \
#    --topology private \
#    --dns-zone "${DNS_ZONE_PRIVATE_ID}" \
#    --node-size "${NODE_SIZE}" \
#    --node-count "${NODE_COUNT}" \
#    --master-size "${MASTER_SIZE}" \
#    --master-count "${MASTER_COUNT}" \
#    --network-cidr "${NETWORK_CIDR}" \
#    --networking calico \
#    --bastion

info_after

}

create_min
