#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}


ctrl_bootstrap() {
# Provision the K8s control plane
 echo "CONFIGURING MASTERS!"

for i in $(seq -w $NR_MASTERS); do
  # Download and install binaries
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "wget -q --show-progress --https-only --timestamping \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-apiserver \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-controller-manager \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kube-scheduler \
    https://storage.googleapis.com/kubernetes-release/release/v1.7.4/bin/linux/amd64/kubectl"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/"
  # Configure API server
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mkdir -p /var/lib/kubernetes/ && \
    sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/"

  # create systemd unit files
  # ...for the apiserver
  cat > ${CA_FOLDR}/kube-apiserver.service.master$i <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${MASTER_IP_INT[$i]} \\
  --allow-privileged=true \\
  --apiserver-count=${NR_MASTERS} \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
EOF
  LINE="  --etcd-servers=https://"
  for j in $(seq -w $NR_MASTERS); do
    LINE="${LINE}${MASTER_IP_INT[$j]}:2379"
    if [ $j -lt $NR_MASTERS ]; then
      LINE="${LINE},https://"
    else
      LINE="${LINE} \\"
    fi
  done
  echo ${LINE}  >> ${CA_FOLDR}/kube-apiserver.service.master$i
  cat >> ${CA_FOLDR}/kube-apiserver.service.master$i <<EOF
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --insecure-bind-address=0.0.0.0 \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --service-account-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-ca-file=/var/lib/kubernetes/ca.pem \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # ...for the controller manager
  cat > ${CA_FOLDR}/kube-controller-manager.service.master$i <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=${CIDR_CLUSTER} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --leader-elect=true \\
  --master=http://${MASTER_IP_INT[$i]}:8080 \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/16 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # ...and for the scheduler manager
  cat > ${CA_FOLDR}/kube-scheduler.service.master$i <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://${MASTER_IP_INT[$i]}:8080 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  # copy those files to the masters and move them to the proper directory
  scp -i ${SSHKEY} ${CA_FOLDR}/kube-apiserver.service.master$i ubuntu@${MASTER_IP_PUB[$i]}:~/kube-apiserver.service
  scp -i ${SSHKEY} ${CA_FOLDR}/kube-controller-manager.service.master$i ubuntu@${MASTER_IP_PUB[$i]}:~/kube-controller-manager.service
  scp -i ${SSHKEY} ${CA_FOLDR}/kube-scheduler.service.master$i ubuntu@${MASTER_IP_PUB[$i]}:~/kube-scheduler.service
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo mv kube-apiserver.service kube-controller-manager.service kube-scheduler.service /etc/systemd/system/"

  # Start the Controller-Master services
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo systemctl daemon-reload && \
    sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler && \
    sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler"

  # NOTE: The K8S Frontend Load Balancer Part has already been done in Step 3's script instead of here
done

for i in $(seq -w $NR_MASTERS); do
  sleep 10
  echo "VERIFYING from master$i!"
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "kubectl get componentstatuses"
done

}


testing() {
  echo
}

ctrl_bootstrap
#testing
