#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

smoketest() {
  echo "SMOKE TESTS!"

  echo "Data Encrpytion"
  kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[1]} "ETCDCTL_API=3 etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C"

  echo "Deployments"
  echo "Deploying nginx"
  kubectl run nginx --image=nginx
  sleep 5
  kubectl get pods -l run=nginx

  echo "Deploying dashboard... because you probably will like having it"
  kubectl create -f https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml

  echo "Checking exec"
  kubectl exec -ti $POD_NAME -- nginx -v

  echo
  echo "FROM HERE ON YOU'LL HAVE TO RUN THE FOLLOWING COMMANDS YOURSELF"
  echo
  echo " - Checking Port forwarding:"
  echo "   RUN:"
  echo "kubectl port-forward $POD_NAME 8080:80"
  echo "   then, on a new terminal:"
  echo "curl --head http://127.0.0.1:8080"
  echo "   , and exit with ^C when you are done"
  echo
  POD_NAME=$(kubectl get pods -l run=nginx -o jsonpath="{.items[0].metadata.name}")
  echo " - Checking logs"
  echo "   RUN:"
  echo "kubectl logs $POD_NAME"

  # TODO: add the services smoke test (creating ELB and so on)

}

smoketest
