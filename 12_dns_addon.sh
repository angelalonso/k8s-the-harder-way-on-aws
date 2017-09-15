#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

dns_addon() {
  echo "Deploying Cluster DNS addon"
  #TODO: This does not work.
  # TODO: /etc/hosts with <ip> worker$i needed
  # I get on the final step:
#kubectl exec -ti $POD_NAME -- nslookup kubernetes
#Server:    10.32.0.10
#Address 1: 10.32.0.10

#nslookup: can't resolve 'kubernetes.default.svc.cluster.local'

#
# instead of
# output
# Server:    10.32.0.10
# Address 1: 10.32.0.10 kube-dns.kube-system.svc.cluster.local

# Name:      kubernetes
# Address 1: 10.32.0.1 kubernetes.default.svc.cluster.local

  #kubectl create -f https://storage.googleapis.com/kubernetes-the-hard-way/kube-dns.yaml
  kubectl create -f https://raw.githubusercontent.com/angelalonso/k8s-the-harder-way-on-aws/master/yaml/kube-dns.yaml
  sleep 30
  echo "creating a busybox deployment"y
  kubectl run busybox --image=busybox --command -- sleep 3600

 # echo "Deploying dashboard"
  #TODO: kubectl proxy gives an error:
  # (solution 1 - increase instance size)
  # Not showing on 127.0.0.1:8001/ui
  ## I0910 09:15:58.832475    7889 logs.go:41] http: proxy error: unexpected EOF

  # https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/#accessing-the-dashboard-ui
  kubectl create -f https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml
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
