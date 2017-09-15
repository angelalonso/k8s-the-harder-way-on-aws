#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

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
