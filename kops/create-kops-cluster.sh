#!/bin/bash
# Based on https://icicimov.github.io/blog/virtualization/Kubernetes-Cluster-in-AWS-with-Kops/

# STEPS, including preparation:
# Create a DNS Zone on AWS for $STACK.$DOMAIN
# Add the NS Records accordingly in, say, Cloudflare
# Create an S3 bucket named clusters.$STACK.$DOMAIN

export STACK="afonseca-k8s"
export DOMAIN="fodpanda.com"
export NAME="${STACK}.${DOMAIN}"
export AWS_PROFILE="test-k8s"
export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}
#export KOPS_FEATURE_FLAGS="+UseLegacyELBName"
#export KOPS_FEATURE_FLAGS="+DrainAndValidateRollingUpdate"
export NETWORK_CIDR="10.44.0.0/20"
export ZONES="us-west-2a,us-west-2b,us-west-2c"
export SSH_PUBLIC_KEY="~/.ssh/kops_rsa.pub"
export DNS_ZONE_PRIVATE_ID="Z1OLJP0EMAUEGM"

export NODE_SIZE="t2.micro"
export NODE_COUNT=3
export MASTER_SIZE="t2.small"
export MASTER_COUNT=3
export KUBERNETES_VERSION="1.7.4"



info_before() {
  echo "ATTENTION! Make sure you have done the following already:"
  echo " - Created a Hosted Zone on Route 53 for ${STACK}.${DOMAIN}"
  echo " - Subdomain delegation for ${STACK}.${DOMAIN}"
  echo " - S3 bucket named clusters.${STACK}.${DOMAIN}"
}

info_after() {
   echo "NOTE:"
   echo "run the following instead to create your cluster:"
   echo "export AWS_PROFILE=${AWS_PROFILE}; export KOPS_STATE_STORE=s3://clusters.${STACK}.${DOMAIN}; kops update cluster ${NAME} --yes"

   echo 
   echo "=========================================================================="
   echo 
   echo "  To add encryption at rest https://github.com/kubernetes/kops/pull/3368"
   echo "head -c 32 /dev/urandom | base64"
   echo "  paste the result into secrets/encryptionconfig.yaml"
   echo "export AWS_PROFILE=test-k8s; export KOPS_STATE_STORE=s3://clusters.afonseca-k8s.fodpanda.com; kops create secret encryptionconfig -f secrets/encryptionconfig.yaml"
   echo "export AWS_PROFILE=test-k8s; export KOPS_STATE_STORE=s3://clusters.afonseca-k8s.fodpanda.com; kops edit cluster afonseca-k8s.fodpanda.com"
   echo "  adding encryptionConfig: true to the cluster spec"
   echo "export AWS_PROFILE=test-k8s; export KOPS_STATE_STORE=s3://clusters.afonseca-k8s.fodpanda.com; kops update cluster --yes"

}

create_min() {

info_before
echo "press a key to continue..."
read answer

kops create cluster \
    --name "${NAME}" \
    --cloud aws \
    --dns-zone "${DNS_ZONE_PRIVATE_ID}" \
    --zones "${ZONES}" \
    --master-count ${MASTER_COUNT} \
    --master-size "${MASTER_SIZE}" \
    --node-count "${NODE_COUNT}" \
    --node-size "${NODE_SIZE}" \
    --api-loadbalancer-type public \
    --topology private \
    --kubernetes-version ${KUBERNETES_VERSION} \
    --cloud-labels "Environment=\"tftest\",Type=\"k8s\",Role=\"node\",Provisioner=\"kops\"" \
    --networking calico \
    --authorization=RBAC \
    --bastion \
    --ssh-public-key ${SSH_PUBLIC_KEY}

#kops update cluster \
#    --master-zones "${ZONES}" \
#    --network-cidr "${NETWORK_CIDR}" \

info_after

}


create_min
