#!/usr/bin/env bash

#VARS
MYIP=$(curl ipinfo.io/ip)
FOLDR="~/k8s-aws"
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"
CA_FOLDR="${FOLDR}/ca"
AWSPROF="test-k8s" # Profile in your ~/.aws config file

STACK="af-k8s"
ENTRY="hw.af-k8s.fodpanda.com"
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

provisioning() {

# Clean up the previous definitions:
cp $CFG $CFG.prev 2>/dev/null
echo > $CFG

# VPC
VPCID=$(aws --profile=${AWSPROF} ec2 create-vpc --cidr-block ${CIDR_VPC} | jq -r '.Vpc.VpcId')
echo "VPCID=\"${VPCID}\"" >> ${CFG}
# Tag it
aws --profile=${AWSPROF} ec2 create-tags --resources ${VPCID} --tags Key=Name,Value=${STACK}-vpc
# Enable DNS for the VPC
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-support '{"Value": true}'
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-hostnames '{"Value": true}'
# DHCP options
DHCP_OPTION_SET_ID=$(aws ec2 --profile=${AWSPROF} create-dhcp-options \
  --dhcp-configuration "Key=domain-name,Values=us-west-2.compute.internal" \
    "Key=domain-name-servers,Values=AmazonProvidedDNS" | jq -r '.DhcpOptions.DhcpOptionsId')
echo "DHCP_OPTION_SET_ID=\"${DHCP_OPTION_SET_ID}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${DHCP_OPTION_SET_ID} --tags Key=Name,Value=${STACK}-dhcp-opts
aws --profile=${AWSPROF} ec2 associate-dhcp-options --dhcp-options-id ${DHCP_OPTION_SET_ID} --vpc-id ${VPCID}
### CHECKED UNTIL HERE
# Subnet
SUBNET=$(aws --profile=${AWSPROF} ec2 create-subnet --vpc-id ${VPCID} --cidr-block ${CIDR_SUBNET} | jq -r '.Subnet.SubnetId')
echo "SUBNET=\"${SUBNET}\"" >> ${CFG}
# Tag it
aws --profile=${AWSPROF} ec2 create-tags --resources ${SUBNET} --tags Key=Name,Value=${STACK}-subnet

# 3x Firewall rules
### Create and config Route Tables
RTB=$(aws --profile=test-k8s ec2 create-route-table --vpc-id ${VPCID}  | jq -r '.RouteTable.RouteTableId')
echo "RTB=\"${RTB}\"" >> ${CFG}
# Tag it, associate it
aws --profile=${AWSPROF} ec2 create-tags --resources ${RTB} --tags Key=Name,Value=${STACK}-route-table
aws --profile=${AWSPROF} ec2 associate-route-table --route-table-id ${RTB} --subnet-id ${SUBNET}
# Create and config Security Groups and rules
SG=$(aws --profile=${AWSPROF} ec2 create-security-group --vpc-id ${VPCID} --group-name ${STACK}-sg --description ${STACK}-security-group | jq -r '.GroupId')
echo "SG=\"${SG}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SG} --tags Key=Name,Value=${STACK}-sg

# Open ports
# TODO: investigate if this works or is even needed
# The ELB is a dependency even before we start.
# GCloud has an IP Range for LB health checks. AWS doesnt, so we create the LB already before the firewall rule
# We need an IGW before creating the ELB
# Create and attach IGW
IGW=$(aws --profile=${AWSPROF} ec2 create-internet-gateway | jq -r '.InternetGateway.InternetGatewayId')
echo "IGW=\"${IGW}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${IGW} --tags Key=Name,Value=${STACK}-internet-gateway
aws --profile=${AWSPROF} ec2 attach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPCID}
# Tell the Route Table to use the IGW to get to the world
aws --profile=${AWSPROF} ec2 create-route --route-table-id ${RTB} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW}
# Create the main ELB for K8s
ELB_DNS=$(aws --profile=${AWSPROF} elb create-load-balancer --load-balancer-name ${STACK}-elb --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" --subnets ${SUBNET} | jq -r '.DNSName')
ELB=$(aws --profile=${AWSPROF} elb describe-load-balancers | jq -r '[ .LoadBalancerDescriptions[] | select( .DNSName | contains("'${ELB_DNS}'")) ] | .[].LoadBalancerName' )
echo "ELB=\"${ELB}\"" >> ${CFG}
echo "ELB_DNS=\"${ELB_DNS}\"" >> ${CFG}
aws --profile=${AWSPROF} elb apply-security-groups-to-load-balancer --load-balancer-name ${STACK}-elb --security-groups ${SG}
aws --profile=${AWSPROF} elb configure-health-check --load-balancer-name ${STACK}-elb --health-check Target=HTTP:8080/healthz,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

# TODO: Is this needed for the ELB?
#aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port 8080 --protocol tcp --cidr ${CIDR_SUBNET}
# Internal Communication across all protocols
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --protocol all --cidr ${CIDR_SUBNET}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --protocol all --cidr ${CIDR_CLUSTER}
# External SSH ICMP and HTTPS
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port 22 --protocol tcp --cidr 0.0.0.0/0
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port 6443 --protocol tcp --cidr 0.0.0.0/0
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port -1 --protocol icmp --cidr 0.0.0.0/0
# Public IP address
# 3x controllers
## Before we create machines we need a KEYPAIR
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
  MASTER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG} --subnet-id ${SUBNET} --private-ip-address 10.240.0.1${i} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  MASTERLIST="${MASTERLIST} ${MASTER_ID[$i]}"
  echo "MASTER_ID[$i]=\"${MASTER_ID[$i]}\"" >> ${CFG}
  aws --profile=${AWSPROF} ec2 create-tags --resources ${MASTER_ID[$i]} --tags Key=Name,Value=${STACK}-master$i
  # Get its Internal IPs
  MASTER_IP_INT[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${MASTER_ID[$i]} | jq -r '.Reservations[].Instances[].PrivateIpAddress')
  echo "MASTER_IP_INT[$i]=\"${MASTER_IP_INT[$i]}\"" >> ${CFG}
  MASTER_IP_PUB[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${MASTER_ID[$i]} | jq -r '.Reservations[].Instances[].PublicIpAddress')
  echo "MASTER_IP_PUB[$i]=\"${MASTER_IP_PUB[$i]}\"" >> ${CFG}
  MASTER_DNS_INT[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${MASTER_ID[$i]} | jq -r '.Reservations[].Instances[].PrivateDnsName')
  echo "MASTER_DNS_INT[$i]=\"${MASTER_DNS_INT[$i]}\"" >> ${CFG}
done
echo "MASTERLIST=\"${MASTERLIST}\"" >> ${CFG}
# Add the controllers to the load Balancer
aws --profile=${AWSPROF} elb register-instances-with-load-balancer --load-balancer-name ${STACK}-elb --instances ${MASTERLIST}

# 3x workers
WORKERLIST=""
for i in $(seq -w $NR_WORKERS); do
  WORKER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG} --subnet-id ${SUBNET} --private-ip-address 10.240.0.2${i} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  WORKERLIST="${WORKERLIST} ${WORKER_ID[$i]}"
  echo "WORKER_ID[$i]=\"${WORKER_ID[$i]}\"" >> ${CFG}
  aws --profile=${AWSPROF} ec2 create-tags --resources ${WORKER_ID[$i]} --tags Key=Name,Value=${STACK}-worker$i
  # Get its Internal IPs
  WORKER_IP_INT[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${WORKER_ID[$i]} | jq -r '.Reservations[].Instances[].PrivateIpAddress')
  echo "WORKER_IP_INT[$i]=\"${WORKER_IP_INT[$i]}\"" >> ${CFG}
  # Get its Public IP
  WORKER_IP_PUB[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${WORKER_ID[$i]} | jq -r '.Reservations[].Instances[].PublicIpAddress')
  echo "WORKER_IP_PUB[$i]=\"${WORKER_IP_PUB[$i]}\"" >> ${CFG}
  WORKER_DNS_INT[$i]=$(aws --profile=${AWSPROF} ec2 describe-instances --instance-id ${WORKER_ID[$i]} | jq -r '.Reservations[].Instances[].PrivateDnsName')
  echo "WORKER_DNS_INT[$i]=\"${WORKER_DNS_INT[$i]}\"" >> ${CFG}
done
echo "WORKERLIST=\"${WORKERLIST}\"" >> ${CFG}


}

hosts() {
  echo "add the following to your /etc/hosts file:"
cat aux/config.cfg | grep "MASTER_IP_P\|WORKER_IP_P" |awk -F'=' '{print $2i" " $1}' | sed -s 's/"//g' | sed -s 's/\[//g' | sed -s 's/\]//g' | sed -s 's/\_IP_PUB//g' | tr '[:upper:]' '[:lower:]'
}

testing() {
  echo TESTING!

}

provisioning
hosts
#testing
