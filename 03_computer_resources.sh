#!/usr/bin/env bash

#VARS
# Needed ones
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"
# create from scratch
mkdir -p ${FOLDR}

echo "This will delete the previous config file"
echo "Are you sure?"
echo " - Y/y -> Delete the references to a previous stack"
echo " - N/n -> Update the references instead and reuse them"
read -r -p "Do you want to overwrite? [y/N] (default is yes)" response
response=${response,,}    # tolower
if [[ "$response" =~ ^(no|n)$ ]]
then
  OVERWRITE=false
  # Load vars we saved in config
  . ${CFG} 2>/dev/null
else
  OVERWRITE=true
  cp $CFG $CFG.prev 2>/dev/null
  echo > $CFG
fi

# Start defining and adding vars to the config file
MYIP=$(curl ipinfo.io/ip)
echo "MYIP=\"${MYIP}\"" >> ${CFG}
echo "FOLDR=\"${FOLDR}\"" >> ${CFG}
CA_FOLDR="${FOLDR}/ca"
echo "CA_FOLDR=\"${CA_FOLDR}\"" >> ${CFG}
echo "AWSPROF=\"test-k8s\"" >> ${CFG}
STACK="af-k8s"
echo "STACK=\"${STACK}\"" >> ${CFG}
echo "ENTRY=\"hw.af-k8s.fodpanda.com\"" >> ${CFG}
SSHKEY="$HOME/.ssh/${STACK}-key.priv"
echo "SSHKEY=\"${SSHKEY}\"" >> ${CFG}
echo "CIDR_VPC=\"10.240.0.0/16\"" >> ${CFG}
echo "CIDR_SUBNET=\"10.240.0.0/24\"" >> ${CFG}
echo "CIDR_CLUSTER=\"10.200.0.0/16\"" >> ${CFG}
K8S_DNS="10.32.0.10"
echo "K8S_DNS=\"${K8S_DNS}\"" >> ${CFG}
echo "PORT_SSH=\"22\"" >> ${CFG}
echo "PORT_ETCD=\"2379\"" >> ${CFG}
echo "PORT_ETCDCTL=\"2380\"" >> ${CFG}
echo "AMI=\"ami-835b4efa\"" >> ${CFG}
echo "INSTANCE_TYPE=\"t2.micro\"" >> ${CFG}
# This variable stores the Route53 zone ID where I created the CNAME for my ELB. Create your own, update this.
echo "R53_ZONE=\"Z22J8RVEAKU7B7\"" >> ${CFG}
echo "R53_ELBFILE=\"elb_route53.json\"" >> ${CFG}
# Amount of master nodes you want, max tested to work is 7
echo "NR_MASTERS=3" >> ${CFG}
# Amount of worker nodes you want, max tested to work is 7
echo "NR_WORKERS=3" >> ${CFG}
# TODO: solve the "08: value too great for base" error to get more than 7 of the two above

. ${CFG}

provisioning() {

# Create VPC, get its ID
VPCID=$(aws --profile=${AWSPROF} ec2 create-vpc --cidr-block ${CIDR_VPC} | jq -r '.Vpc.VpcId')
echo "VPCID=\"${VPCID}\"" >> ${CFG}
# Tag it
aws --profile=${AWSPROF} ec2 create-tags --resources ${VPCID} --tags Key=Name,Value=${STACK}-vpc
# Enable DNS for the VPC
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-support '{"Value": true}'
aws --profile=${AWSPROF} ec2 modify-vpc-attribute --vpc-id ${VPCID} --enable-dns-hostnames '{"Value": true}'

# DHCP options, as seen on https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/1.4/docs/01-infrastructure-aws.md
DHCP_OPTION_SET_ID=$(aws ec2 --profile=${AWSPROF} create-dhcp-options \
  --dhcp-configuration "Key=domain-name,Values=us-west-2.compute.internal" \
    "Key=domain-name-servers,Values=AmazonProvidedDNS" | jq -r '.DhcpOptions.DhcpOptionsId')
echo "DHCP_OPTION_SET_ID=\"${DHCP_OPTION_SET_ID}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${DHCP_OPTION_SET_ID} --tags Key=Name,Value=${STACK}-dhcp-opts
aws --profile=${AWSPROF} ec2 associate-dhcp-options --dhcp-options-id ${DHCP_OPTION_SET_ID} --vpc-id ${VPCID}

# Subnet
SUBNET=$(aws --profile=${AWSPROF} ec2 create-subnet --vpc-id ${VPCID} --cidr-block ${CIDR_SUBNET} | jq -r '.Subnet.SubnetId')
echo "SUBNET=\"${SUBNET}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SUBNET} --tags Key=Name,Value=${STACK}-subnet

# Internet Gateway
IGW=$(aws --profile=${AWSPROF} ec2 create-internet-gateway | jq -r '.InternetGateway.InternetGatewayId')
echo "IGW=\"${IGW}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${IGW} --tags Key=Name,Value=${STACK}-internet-gateway
aws --profile=${AWSPROF} ec2 attach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPCID}

### Create and config Route Tables
RTB=$(aws --profile=test-k8s ec2 create-route-table --vpc-id ${VPCID}  | jq -r '.RouteTable.RouteTableId')
echo "RTB=\"${RTB}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${RTB} --tags Key=Name,Value=${STACK}-route-table
aws --profile=${AWSPROF} ec2 associate-route-table --route-table-id ${RTB} --subnet-id ${SUBNET}
# Tell the Route Table to use the IGW to get to the world
aws --profile=${AWSPROF} ec2 create-route --route-table-id ${RTB} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW}

# Firewall rules
# Create and config Security Groups and rules
SG=$(aws --profile=${AWSPROF} ec2 create-security-group --vpc-id ${VPCID} --group-name ${STACK}-sg --description ${STACK}-security-group | jq -r '.GroupId')
echo "SG=\"${SG}\"" >> ${CFG}
aws --profile=${AWSPROF} ec2 create-tags --resources ${SG} --tags Key=Name,Value=${STACK}-sg

# Internal Communication across all protocols
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --protocol all --port 0-65535 --cidr ${CIDR_VPC}
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --protocol all
# External SSH ICMP and HTTPS
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port 22 --protocol tcp --cidr 0.0.0.0/0
aws --profile=${AWSPROF} ec2 authorize-security-group-ingress --group-id ${SG} --port 6443 --protocol tcp --cidr 0.0.0.0/0

# The ELB is a dependency even before we start.
# Create the main ELB for K8s
ELB_DNS=$(aws --profile=${AWSPROF} elb create-load-balancer --load-balancer-name ${STACK}-elb --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" --subnets ${SUBNET} --security-groups ${SG} | jq -r '.DNSName')
ELB=$(aws --profile=${AWSPROF} elb describe-load-balancers | jq -r '[ .LoadBalancerDescriptions[] | select( .DNSName | contains("'${ELB_DNS}'")) ] | .[].LoadBalancerName' )
echo "ELB=\"${ELB}\"" >> ${CFG}
echo "ELB_DNS=\"${ELB_DNS}\"" >> ${CFG}

# change the DNS we use to access the ELB
# NOTE: hw.af-k8s.fodpanda.com is a CNAME within Route 53: Create your own and change this
  cat > ${R53_ELBFILE} <<EOF
{ "Comment": "", "Changes": [{"Action": "UPSERT",
"ResourceRecordSet": {"Name": "hw.af-k8s.fodpanda.com.","Type": "CNAME","TTL": 60,
"ResourceRecords": [{"Value":
EOF
echo "\"${ELB_DNS}\"" >> ${R53_ELBFILE}
echo "}]}}]}" >> ${R53_ELBFILE}

aws --profile=${AWSPROF} route53 change-resource-record-sets --hosted-zone-id ${R53_ZONE} --change-batch file://${R53_ELBFILE}
aws --profile=${AWSPROF} elb configure-health-check --load-balancer-name ${STACK}-elb --health-check Target=HTTP:8080/healthz,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

## Before we create machines we need a KEYPAIR
if [ -f  ${SSHKEY} ]; then
  mv ${SSHKEY} ${SSHKEY}.old
  echo "PREVIOUS SSH KEY exists, saved on ${SSHKEY}.old "
fi
touch ${SSHKEY}
chmod 600 ${SSHKEY}
aws --profile=${AWSPROF} ec2 create-key-pair --key-name ${STACK}-key | jq -r '.KeyMaterial' >> ${SSHKEY}

# 3x masters
MASTERLIST=""
for i in $(seq -w $NR_MASTERS); do
  # Provision and tag the master
  MASTER_ID[$i]=$(aws --profile=${AWSPROF} ec2 run-instances --image-id ${AMI} --instance-type ${INSTANCE_TYPE} --key-name ${STACK}-key --security-group-ids ${SG} --subnet-id ${SUBNET} --private-ip-address 10.240.0.1${i} --associate-public-ip-address | jq -r '.Instances[].InstanceId')
  # As seen on https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/1.4/docs/01-infrastructure-aws.md
  aws --profile=${AWSPROF} ec2 modify-instance-attribute --instance-id ${MASTER_ID[$i]} --no-source-dest-check
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
  # As seen on https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/1.4/docs/01-infrastructure-aws.md
  aws --profile=${AWSPROF} ec2 modify-instance-attribute --instance-id ${WORKER_ID[$i]} --no-source-dest-check
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

correct_config() {
  cat $CFG | sort | uniq > $CFG.aux
  mv $CFG.aux $CFG
}

hosts() {
  # This is somehow needed in AWS: make sure all hosts know how to find each other by the name in their configs, meaning IP, but also AWS DNS and the name we give them on this config (e.g.: worker2)
  echo "add the following to your /etc/hosts file:"
  cat aux/config.cfg | grep "MASTER_IP_P\|WORKER_IP_P" |awk -F'=' '{print $2i" " $1}' | sed -s 's/"//g' | sed -s 's/\[//g' | sed -s 's/\]//g' | sed -s 's/\_IP_PUB//g' | tr '[:upper:]' '[:lower:]'
# create the file
echo > ${CA_FOLDR}/etchosts
for i in $(seq -w $NR_MASTERS); do
  # I know, 10.240.xx should not be hardcoded!
  echo "10.240.0.1$i ip-10-240-0-1$i master$i" >> ${CA_FOLDR}/etchosts
done
for i in $(seq -w $NR_WORKERS); do
  echo "10.240.0.2$i ip-10-240-0-2$i worker$i" >> ${CA_FOLDR}/etchosts
done
# Distribute it

for i in $(seq -w $NR_MASTERS); do
  scp -o StrictHostKeyChecking=no -i ${SSHKEY} ${CA_FOLDR}/etchosts ubuntu@${MASTER_IP_PUB[$i]}:~/etchosts
  ssh -i ${SSHKEY} ubuntu@${MASTER_IP_PUB[$i]} "sudo tee -a /etc/hosts < etchosts"
done

for i in $(seq -w $NR_WORKERS); do
  scp -o StrictHostKeyChecking=no -i ${SSHKEY} ${CA_FOLDR}/etchosts ubuntu@${WORKER_IP_PUB[$i]}:~/etchosts
  ssh -i ${SSHKEY} ubuntu@${WORKER_IP_PUB[$i]} "sudo tee -a /etc/hosts < etchosts"
done
}


provisioning
if ! $OVERWRITE ; then
  correct_config
fi
hosts
