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
CLUSTER_CIDR="10.240.0.0/16"
CIDR_MASTER="10.4.1.0/24"
CIDR_WORKER="10.4.2.0/24"
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

provisioning() {

# Clean up the previous definitions:
cp $CFG $CFG.prev 2>/dev/null
echo > $CFG

# Create and tag VPC
VPCID=$(aws --profile=${AWSPROF} ec2 create-vpc --cidr-block ${CLUSTER_CIDR} | jq -r '.Vpc.VpcId')
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

# Open ports for API-server
#TODO: maybe make these ports a variable?
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port 8080 --protocol tcp --source-group ${SG_MASTERS}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG_MASTERS} --port 6443 --protocol tcp --cidr ${MYIP}/32

# Provision the machines
if [ -f  ${SSHKEY} ]; then
  mv ${SSHKEY} ${SSHKEY}.old
  echo "PREVIOUS SSH KEY exists, saved on ${SSHKEY}.old "
fi
touch ${SSHKEY}
chmod 600 ${SSHKEY}
aws --profile=${AWSPROF} ec2 create-key-pair --key-name ${STACK}-key | jq -r '.KeyMaterial' >> ${SSHKEY}

MASTERLIST=""
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


WORKERLIST=""
for i in $(seq -w $NR_WORKERS); do
  WORKER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG_WORKERS} --subnet-id ${SUBNET_WORKER} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  WORKERLIST="${WORKERLIST} ${WORKER_ID[$i]}"
  echo "WORKER_ID[$i]=\"${WORKER_ID[$i]}\"" >> ${CFG}
  aws --profile=${AWSPROF} ec2 create-tags --resources ${WORKER_ID[$i]} --tags Key=Name,Value=${STACK}-worker$i
  # Get its Public IP
  WORKER_IP_PUB[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${WORKER_ID[$i]} | jq -r '.Reservations[].Instances[].PublicIpAddress')
  echo "WORKER_IP_PUB[$i]=\"${WORKER_IP_PUB[$i]}\"" >> ${CFG}
done
echo "WORKERLIST=\"${WORKERLIST}\"" >> ${CFG}

# Create the main ELB for K8s
ELB_DNS=$(aws --profile=${AWSPROF} elb create-load-balancer --load-balancer-name ${STACK}-elb --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" --subnets ${SUBNET_MASTER} | jq -r '.DNSName')
#TODO: read ELBDNS into this command
ELB=$(aws --profile=${AWSPROF} elb describe-load-balancers | jq -r '[ .LoadBalancerDescriptions[] | select( .DNSName | contains("'${ELB_DNS}'")) ] | .[].LoadBalancerName' )
echo "ELB=\"${ELB}\"" >> ${CFG}
echo "ELB_DNS=\"${ELB_DNS}\"" >> ${CFG}
aws --profile=${AWSPROF} elb apply-security-groups-to-load-balancer --load-balancer-name ${STACK}-elb --security-groups ${SG_MASTERS} ${SG_WORKERS}
aws --profile=${AWSPROF} elb configure-health-check --load-balancer-name ${STACK}-elb --health-check Target=HTTP:8080/healthz,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3
aws --profile=${AWSPROF} elb register-instances-with-load-balancer --load-balancer-name ${STACK}-elb --instances ${MASTERLIST}

}

testing() {
  echo TESTING!

}

provisioning
#testing
