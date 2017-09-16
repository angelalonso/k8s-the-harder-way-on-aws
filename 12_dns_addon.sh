#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

dns_addon() {
  echo "Deploying Cluster DNS addon"

  #kubectl create -f https://storage.googleapis.com/kubernetes-the-hard-way/kube-dns.yaml
  kubectl create -f https://raw.githubusercontent.com/angelalonso/k8s-the-harder-way-on-aws/master/yaml/kube-dns.yaml
  sleep 30
  echo "creating a busybox deployment"y
  kubectl run busybox --image=busybox --command -- sleep 3600

}

testing() {
  echo "Testing kube-dns is there"
  kubectl get pods -l k8s-app=kube-dns -n kube-system
  echo "Testing busybox"
  kubectl get pods -l run=busybox
  POD_NAME=$(kubectl get pods -l run=busybox -o jsonpath="{.items[0].metadata.name}")
  kubectl exec -ti $POD_NAME -- nslookup kubernetes
}

dns_addon
testing
