#!/usr/bin/env bash

#VARS
MYIP=$(curl ipinfo.io/ip)
FOLDR="~/k8s-aws"
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"
CA_FOLDR="${FOLDR}/ca"
AWSPROF="test-k8s" # Profile in your ~/.aws config file

STACK="af-k8s"
SSHKEY="$HOME/.ssh/$STACK-key.priv"
CIDR_VPC="10.240.0.0/16"
CIDR_SUBNET="10.240.0.0/24"
CIDR_CLUSTER="10.200.0.0/16"
#TODO: Check what this is really used for
K8S_DNS="10.32.0.10"

PORT_SSH="22"
# TODO: are these correct?
PORT_ETCD="2379"
PORT_ETCDCTL="2380"

AMI="ami-835b4efa"
INSTANCE_TYPE="t2.small"

NR_MASTERS=3
NR_WORKERS=3

mkdir -p ${FOLDR}

. ${CFG}

ca_config() {

echo "CONFIGURING CA!"

# Setup CA and create TLS certs
# Install CFSSL
# NOTE: move here from official step 02
echo "Installing CFSSL"
mkdir -p ${CA_FOLDR} && cd ${CA_FOLDR}
wget -q --show-progress --https-only --timestamping \
  https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 \
  https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64

chmod +x cfssl_linux-amd64 cfssljson_linux-amd64

sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson

echo "Testing CFSSL"
cfssl version


# Set up a Certificate Authority
# Create a CA configuration file:
cat > ${CA_FOLDR}/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

# Create a CA certificate signing request:
cat > ${CA_FOLDR}/ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate a CA certificate and private key:
cfssl gencert -initca  ${CA_FOLDR}/ca-csr.json | cfssljson -bare ca

# Generate client and server TLS certificates
# Create the Admin client certificate
cat > ${CA_FOLDR}/admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate the admin client certificate and private key:
cfssl gencert \
  -ca=${CA_FOLDR}/ca.pem \
  -ca-key=${CA_FOLDR}/ca-key.pem \
  -config=${CA_FOLDR}/ca-config.json \
  -profile=kubernetes \
  ${CA_FOLDR}/admin-csr.json | cfssljson -bare admin

# Kubelet Client certificates
for i in $(seq -w $NR_WORKERS); do
cat > worker${i}-csr.json <<EOF
{
  "CN": "system:node:worker${i}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=${CA_FOLDR}/ca.pem \
  -ca-key=${CA_FOLDR}/ca-key.pem \
  -config=${CA_FOLDR}/ca-config.json \
  -hostname=worker${i},${WORKER_IP_PUB[$i]},${WORKER_IP_INT[$i]} \
  -profile=kubernetes \
  ${CA_FOLDR}/worker${i}-csr.json | cfssljson -bare worker${i}

done

# Kube-proxy Client certificate
# Create the kube-proxy client certificate signing request:
cat > ${CA_FOLDR}/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate the kube-proxy client certificate and private key:
cfssl gencert \
  -ca=${CA_FOLDR}/ca.pem \
  -ca-key=${CA_FOLDR}/ca-key.pem \
  -config=${CA_FOLDR}/ca-config.json \
  -profile=kubernetes \
  ${CA_FOLDR}/kube-proxy-csr.json | cfssljson -bare kube-proxy

# Kubernetes API server certificate
# Create the kubernetes server certificate
K8S_PUBLIC_ADDRESS=${ELB_DNS}
cat > ${CA_FOLDR}/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF
MASTER_IP_INT_LIST=""
for i in $(seq -w $NR_MASTERS); do
  #TODO: here we should get the IP
  MASTER_IP_INT_LIST=$(echo "$MASTER_IP_INT_LIST${MASTER_IP_INT[$i]},")
done
cfssl gencert \
  -ca=${CA_FOLDR}/ca.pem \
  -ca-key=${CA_FOLDR}/ca-key.pem \
  -config=${CA_FOLDR}/ca-config.json \
  -hostname=10.32.0.1,${MASTER_IP_INT_LIST},${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  ${CA_FOLDR}/kubernetes-csr.json | cfssljson -bare kubernetes

#Distribute client and server Certificates


for i in $(seq -w $NR_WORKERS); do
  # -o StrictHostKeyChecking=no is convenient when it's the first time you use the host, see also below, for the masters.
  scp -o StrictHostKeyChecking=no -i ${SSHKEY} ${CA_FOLDR}/ca.pem ${CA_FOLDR}/worker${i}-key.pem ${CA_FOLDR}/worker${i}.pem ubuntu@${WORKER_IP_PUB[$i]}:~/
done

for i in $(seq -w $NR_MASTERS); do
  scp -o StrictHostKeyChecking=no -i ${SSHKEY} ${CA_FOLDR}/ca.pem ${CA_FOLDR}/ca-key.pem ${CA_FOLDR}/kubernetes-key.pem ${CA_FOLDR}/kubernetes.pem ubuntu@${MASTER_IP_PUB[$i]}:~/
done

}

testing() {
  echo
}

ca_config
#testing
