#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

auth_config() {

echo "CONFIGURING AUTH!"

K8S_PUBLIC_ADDRESS=${ENTRY}
#kubelet Kubernetes Configuration File
for i in $(seq -w $NR_WORKERS); do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=${CA_FOLDR}/ca.pem \
    --embed-certs=true \
    --server=https://${K8S_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config set-credentials system:node:worker${i} \
    --client-certificate=${CA_FOLDR}/worker${i}.pem \
    --client-key=${CA_FOLDR}/worker${i}-key.pem \
    --embed-certs=true \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:worker${i} \
    --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig

  kubectl config use-context default --kubeconfig=${CA_FOLDR}/worker${i}.kubeconfig
done

#kube-proxy Kubernetes Configuration File
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=${CA_FOLDR}/ca.pem \
  --embed-certs=true \
  --server=https://${K8S_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=${CA_FOLDR}/kube-proxy.pem \
  --client-key=${CA_FOLDR}/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=${CA_FOLDR}/kube-proxy.kubeconfig

for i in $(seq -w $NR_WORKERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/worker${i}.kubeconfig ${CA_FOLDR}/kube-proxy.kubeconfig ubuntu@${WORKER_IP_PUB[$i]}:~/
done

}

testing() {
  echo
}

auth_config
#testing
