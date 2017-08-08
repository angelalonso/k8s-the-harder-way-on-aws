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
CIDR="10.4.0.0/16"
CIDR_MASTER="10.4.1.0/24"
CIDR_WORKER="10.4.2.0/24"
#TODO: Check what this is really used for
K8S_DNS="10.32.0.1"

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

provisioning() {


# Clean up the previous definitions:
cp $CFG $CFG.prev
echo > $CFG

# Create and tag VPC
VPCID=$(aws --profile=${AWSPROF} ec2 create-vpc --cidr-block ${CIDR} | jq -r '.Vpc.VpcId')
echo "VPCID=\"${VPCID}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${VPCID} --tags Key=Name,Value=${STACK}-vpc

# Enable DNS for the VPC
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-support
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-hostnames

# Subnets for masters and workers

SUBNET_MASTER=$(aws --profile=${AWSPROF} ec2 create-subnet --vpc-id ${VPCID} --cidr-block ${CIDR_MASTER} | jq -r '.Subnet.SubnetId')
echo "SUBNET_MASTER=\"${SUBNET_MASTER}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SUBNET_MASTER} --tags Key=Name,Value=${STACK}-subnet-masters
SUBNET_WORKER=$(aws --profile=${AWSPROF} ec2 create-subnet --vpc-id ${VPCID} --cidr-block ${CIDR_WORKER} | jq -r '.Subnet.SubnetId')
echo "SUBNET_WORKER=\"${SUBNET_WORKER}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SUBNET_WORKER} --tags Key=Name,Value=${STACK}-subnet-workers

# Create and attach IGW
IGW=$(aws --profile=${AWSPROF} ec2 create-internet-gateway | jq -r '.InternetGateway.InternetGatewayId')
echo "IGW=\"${IGW}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${IGW} --tags Key=Name,Value=${STACK}-internet-gateway
aws --profile=${AWSPROF} ec2 attach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPCID}

### Create and config Route Tables
RTB=$(aws --profile=test-k8s ec2 create-route-table --vpc-id ${VPCID}  | jq -r '.RouteTable.RouteTableId')
echo "RTB=\"${RTB}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${RTB} --tags Key=Name,Value=${STACK}-route-table
aws --profile=${AWSPROF} ec2 associate-route-table --route-table-id ${RTB} --subnet-id ${SUBNET_MASTER}
aws --profile=${AWSPROF} ec2 associate-route-table --route-table-id ${RTB} --subnet-id ${SUBNET_WORKER}
aws --profile=${AWSPROF} ec2 create-route --route-table-id ${RTB} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW}

# Create and config Security Groups and rules
SG_MASTERS=$(aws --profile=${AWSPROF} ec2 create-security-group --vpc-id ${VPCID} --group-name ${STACK}-sg-masters --description ${STACK}-security-group-masters | jq -r '.GroupId')
echo "SG_MASTERS=\"${SG_MASTERS}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SG_MASTERS} --tags Key=Name,Value=${STACK}-sg-masters
SG_WORKERS=$(aws --profile=${AWSPROF} ec2 create-security-group --vpc-id ${VPCID} --group-name ${STACK}-sg-workers --description ${STACK}-security-group-workers | jq -r '.GroupId')
echo "SG_WORKERS=\"${SG_WORKERS}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SG_WORKERS} --tags Key=Name,Value=${STACK}-sg-workers

# Open ports for your own ssh and for both secgroups to communicate
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port 0-65535 --protocol tcp --source-group ${SG_WORKERS}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port ${PORT_SSH} --protocol tcp --cidr ${MYIP}/32
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_WORKERS} --port 0-65535 --protocol tcp --source-group ${SG_MASTERS}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_WORKERS} --port ${PORT_SSH} --protocol tcp --cidr ${MYIP}/32

# Open ports for etcd and etcdctl
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port ${PORT_ETCD} --protocol tcp --source-group ${SG_MASTERS}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port ${PORT_ETCDCTL} --protocol tcp --source-group ${SG_MASTERS}

# Provision the machines
if [ -f  ${SSHKEY} ]; then
  cp ${SSHKEY} ${SSHKEY}.old
  echo "PREVIOUS SSH KEY exists, saved on ${SSHKEY}.old "
else
  touch ${SSHKEY}
fi
aws --profile=${AWSPROF} ec2 create-key-pair --key-name ${STACK}-key | jq -r '.KeyMaterial' > ${SSHKEY}
sudo chmod 0600 ${SSHKEY}

for i in $(seq -w $NR_MASTERS); do
  # Provision and tag the master
  MASTER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG_MASTERS} --subnet-id ${SUBNET_MASTER} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  MASTERLIST="${MASTERLIST} ${MASTER_ID[$i]}"
  echo "MASTER_ID[$i]=\"${MASTER_ID[$i]}\"" >> ${CFG}
  aws --profile=${AWSPROF} ec2 create-tags --resources ${MASTER_ID[$i]} --tags Key=Name,Value=${STACK}-master$i
  # Get its Internal and its Public IPs
  MASTER_IP_INT[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${MASTER_ID[$i]} | jq -r '.Reservations[].Instances[].PrivateIpAddress')
  echo "MASTER_IP_INT[$i]=\"${MASTER_IP_INT[$i]}\"" >> ${CFG}
  MASTER_IP_PUB[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${MASTER_ID[$i]} | jq -r '.Reservations[].Instances[].PublicIpAddress')
  echo "MASTER_IP_PUB[$i]=\"${MASTER_IP_PUB[$i]}\"" >> ${CFG}
done
echo "MASTERLIST=\"${MASTERLIST}\"" >> ${CFG}


for i in $(seq -w $NR_WORKERS); do
  WORKER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG_WORKERS} --subnet-id ${SUBNET_WORKER} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  WORKERLIST="${WORKERLIST} ${WORKER_ID[$i]}"
  echo "WORKER_ID[$i]=\"${WORKER_ID[$i]}\"" >> ${CFG}
  aws --profile=${AWSPROF} ec2 create-tags --resources ${WORKER_ID[$i]} --tags Key=Name,Value=${STACK}-worker$i
  # Get its Public IP
  WORKER_IP_PUB[$i]=$(aws --profile=${AWSPROF} ec1 describe-instances --instance-id ${WORKER_ID[$i]} | jq -r '.Reservations[].Instances[].PublicIpAddress')
  echo "WORKER_IP_PUB[$i]=\"${WORKER_IP_PUB[$i]}\"" >> ${CFG}
done
echo "WORKERLIST=\"${WORKERLIST}\"" >> ${CFG}

# Create the main ELB for K8s
ELB_DNS=$(aws --profile=${AWSPROF} elb create-load-balancer --load-balancer-name ${STACK}-elb --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" --subnets ${SUBNET_MASTER} | jq -r '.DNSName')
echo "ELB_DNS=\"${ELB_DNS}\"" >> ${CFG}
aws --profile=${AWSPROF} elb configure-health-check --load-balancer-name ${STACK}-elb --health-check Target=HTTP:8080/healthz,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3
aws --profile=${AWSPROF} elb register-instances-with-load-balancer --load-balancer-name ${STACK}-elb --instances ${MASTERLIST}

}

ca_config() {

echo "CONFIGURING CA!"

# Setup CA and create TLS certs
# Install CFSSL
echo "Installing CFSSL"
mkdir -p ${CA_FOLDR} && cd ${CA_FOLDR}
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson

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
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# Generate client and server TLS certificates
# Create the Admin client certificate
cat > ${CA_FOLDR}/admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Cluster",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate the admin client certificate and private key:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

# Create the kube-proxy client certificate
# Create the kube-proxy client certificate signing request:
cat > ${CA_FOLDR}/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Cluster",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate the kube-proxy client certificate and private key:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

# Create the kubernetes server certificate
K8S_PUBLIC_ADDRESS=${ELB_DNS}

cat > ${CA_FOLDR}/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "${K8S_DNS}",
EOF
for i in $(seq -w $NR_MASTERS); do
  #TODO: here we should get the IP
  echo '    "'${MASTER_IP_INT[$i]}'",' >> ${CA_FOLDR}/kubernetes-csr.json
done
cat >> ${CA_FOLDR}/kubernetes-csr.json <<EOF
    "${K8S_PUBLIC_ADDRESS}",
    "127.0.0.1",
    "kubernetes.default"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Cluster",
      "ST": "Oregon"
    }
  ]
}
EOF

# Generate the Kubernetes certificate and private key:
cfssl gencert \
  -ca=${CA_FOLDR}/ca.pem \
  -ca-key=${CA_FOLDR}/ca-key.pem \
  -config=${CA_FOLDR}/ca-config.json \
  -profile=kubernetes \
  ${CA_FOLDR}/kubernetes-csr.json | cfssljson -bare kubernetes

# Distribute the TLS certificates
# TODO: check that all files are stored in the same folder(currently it is not)
for i in $(seq -w $NR_MASTERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/ca.pem ${CA_FOLDR}/ca-key.pem kubernetes-key.pem kubernetes.pem ubuntu@${MASTER_IP_PUB[$i]}:/home/ubuntu/
done

cd ${CA_FOLDR}
for i in $(seq -w $NR_WORKERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/ca.pem ${CA_FOLDR}/kube-proxy.pem ${CA_FOLDR}/kube-proxy-key.pem ubuntu@${WORKER_IP_PUB[$i]}:/home/ubuntu/
done

}


testing() {
   echo

# Setting up Authentication
#TODO: Check that kubectl is installed

# Create the TLS Bootstrap Token
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')

cat > ${CA_FOLDR}/token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

for i in $(seq -w $NR_MASTERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/token.csv ubuntu@${MASTER_IP_PUB[$i]}:/home/ubuntu/
done


}


untested() {

# Client Authentication Configs
# Create client kubeconfig files
# Create the bootstrap kubeconfig file
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${K8S_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=bootstrap.kubeconfig

kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig

kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

# Create the kube-proxy kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${K8S_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# Distribute the client kubeconfig files
for i in $(seq -w $NR_WORKERS); do
  scp -i ${SSHKEY} bootstrap.kubeconfig kube-proxy.kubeconfig ubuntu@${WORKER_IP_PUB[$i]}:/home/ubuntu/
done


# Bootstrapping a H/A etcd cluster
# TLS Certificates
for i in $(seq -w $NR_MASTERS); do
  ssh ubuntu@${MASTER_IP_PUB[$i]} "sudo mkdir -p /etc/etcd/ && sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/"
  ssh ubuntu@${MASTER_IP_PUB[$i]} "wget https://github.com/coreos/etcd/releases/download/v3.1.4/etcd-v3.1.4-linux-amd64.tar.gz"
  ssh ubuntu@${MASTER_IP_PUB[$i]} "tar -xvf etcd-v3.1.4-linux-amd64.tar.gz && sudo mv etcd-v3.1.4-linux-amd64/etcd* /usr/bin/"
  ssh ubuntu@${MASTER_IP_PUB[$i]} "sudo mkdir -p /var/lib/etcd"
done

# Set the internal IP address
# TODO: maybe do this on a script and run

cd $FOLDR
for i in $(seq -w $NR_MASTERS); do
  #TODO: Here it should have 03 or 003, not just master3
  ETCD_NAME[$i]=master$i
  # TODO: Maybe we check internal ip with curl http://169.254.169.254/latest/meta-data/local-ipv4
  cat > ${CA_FOLDR}/etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/bin/etcd \\
  --name ${ETCD_NAME[$i]} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${MASTER_IP_INT[$i]}:2380 \\
  --listen-peer-urls https://${MASTER_IP_INT[$i]}:2380 \\
  --listen-client-urls https://${MASTER_IP_INT[$i]}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls https://${MASTER_IP_INT[$i]}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
\#TODO: automate this
  --initial-cluster master01=https://10.4.1.150:2380,master02=https://10.4.1.77:2380,master03=https://10.4.1.106:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  scp -i ${SSHKEY} etcd.service ubuntu@${MASTER_IP_PUB[$i]}:/home/ubuntu
  ssh ubuntu@${MASTER_IP_PUB[$i]} "sudo mv etcd.service /etc/systemd/system/"
  ssh ubuntu@${MASTER_IP_PUB[$i]} "sudo systemctl daemon-reload; sudo systemctl enable etcd"
  ssh ubuntu@${MASTER_IP_PUB[$i]} "sudo systemctl start etcd; sudo systemctl status etcd --no-pager"
done

# Bootstrapping an H/A Kubernetes Control Plane
}
#provisioning
#ca_config
testing
