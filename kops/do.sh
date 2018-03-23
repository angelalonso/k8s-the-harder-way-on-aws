#!/usr/bin/env bash

set -eo pipefail

DIR=$(dirname $(readlink -f $0))
HELMDIR="${DIR}/helm"


kk="kubectl --kubeconfig $HOME/.kube/config.test"


deploy() {
  helm init
  while [ $(${kk} -nkube-system get po | grep tiller | grep Running | wc -l) = 0 ]
  do 
    sleep 1; echo waiting for tiller to be up...
  done

  #https://github.com/kubernetes/helm/issues/3130
  kk create serviceaccount --namespace kube-system tiller
  kk create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  kk patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}' 

  for nspacepath in $(ls -d ${HELMDIR}/*/)
  do
    nspace=$(basename $nspacepath)
    for chartpath in $(ls -d ${nspacepath}*/)
    do
      chart=$(basename $chartpath)
      echo "adding $chart"
      helm install --name $chart $chartpath --namespace $nspace
    done
  done

  # Other
  helm install --name main-ingress stable/nginx-ingress --set rbac.create=true

}


clean() {
  for nspacepath in $(ls -d ${HELMDIR}/*/)
  do
    nspace=$(basename $nspacepath)
    for chartpath in $(ls -d ${nspacepath}*/)
    do
      chart=$(basename $chartpath)
      echo "removing $chart"
      helm delete --purge $chart
    done
  done

  # Other
  helm delete --purge nginx-ingress
}


help(){
  echo "ERROR: Wrong or unrecognized parameter received: $1"
  echo "USAGE:"
  echo "$0 [deploy|clean]"
}


main(){
case "$1" in
  deploy)
    deploy;;
  clean)
    clean;;
  *)
    help "$1";;
esac
}

main "$1"
