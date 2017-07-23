# k8s-the-harder-way-on-aws
Based on https://github.com/rmenn/kubernetes-the-hard-way-aws, which is also based on
https://github.com/kelseyhightower/kubernetes-the-hard-way but in AWS

## Prerequisites and Conventions
- You have access to an AWS account. In my case on the us-west-2 region (cheapest, really)
- You have  enough rights. In my case, that meant IAM user with admin right, and a key/secret setup on .aws/credentials
<br>  In my case, I am calling the profile test-k8s, no wonder you'll see this often in my commands
- You have awscli setup. In my case 'pip install awscli --upgrade --user' did the trick

## Cloud provisioning
Built on top of https://github.com/rmenn/kubernetes-the-hard-way-aws/blob/master/docs/01-infra.md
Based on https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/01-infrastructure-gcp.md

### Create and tag the VPC
```
aws --profile=test-k8s ec2 create-vpc --cidr-block 10.4.0.0/16
```
Take the vpc id from the output, then:
```
aws --profile=test-k8s ec2 create-tags --resources vpc-674e9b01 --tags Key=Name,Value=afonseca-k8s-vpc
```
, where vpc-674e9b01 s the vpc ID I got from the previous step and afonseca-k8s is my project name

### Enable DNS for the VPC
```
aws --profile=test-k8s ec2 modify-vpc-attribute --vpc-id vpc-674e9b01 --enable-dns-support
aws --profile=test-k8s ec2 modify-vpc-attribute --vpc-id vpc-674e9b01 --enable-dns-hostnames
```

### Create and tag subnets for masters and workers
```
aws --profile=test-k8s ec2 create-subnet --vpc-id vpc-674e9b01 --cidr-block 10.4.1.0/24
aws --profile=test-k8s ec2 create-tags --resources subnet-4ce1072a --tags Key=Name,Value=afonseca-k8s-subnet-masters
aws --profile=test-k8s ec2 create-subnet --vpc-id vpc-674e9b01 --cidr-block 10.4.2.0/24
aws --profile=test-k8s ec2 create-tags --resources subnet-e5e50383 --tags Key=Name,Value=afonseca-k8s-subnet-workers
```
, where subnet-4ce1072a and subnet-e5e50383 are the result of the previous comman on each case

### Create and attach internet gateway
```
aws --profile=test-k8s ec2 create-internet-gateway
aws --profile=test-k8s ec2 create-tags --resources igw-eba4228c --tags Key=Name,Value=afonseca-k8s-internet-gateway
aws --profile=test-k8s ec2 attach-internet-gateway --internet-gateway-id igw-eba4228c --vpc-id vpc-674e9b01
```

### Create and config Route Tables
```
aws --profile=test-k8s ec2 create-route-table --vpc-id vpc-674e9b01
aws --profile=test-k8s ec2 create-tags --resources rtb-afb0e9c9 --tags Key=Name,Value=afonseca-k8s-route-table
```
, where rtb-afb0e9c9 is the route table id we got from the previous command
```
aws --profile=test-k8s ec2 associate-route-table --route-table-id rtb-afb0e9c9 --subnet-id subnet-4ce1072a
aws --profile=test-k8s ec2 associate-route-table --route-table-id rtb-afb0e9c9 --subnet-id subnet-e5e50383
aws --profile=test-k8s ec2 create-route --route-table-id rtb-afb0e9c9 --destination-cidr-block 0.0.0.0/0 --gateway-id igw-eba4228c
```
, where igw-eba4228c is the internet gateway id you received from the related step

### Create and config Security Groups and rules
```
aws --profile=test-k8s ec2 create-security-group --vpc-id vpc-674e9b01 --group-name afonseca-k8s-sg-masters --description afonseca-k8s-security-group-masters
aws --profile=test-k8s ec2 create-security-group --vpc-id vpc-674e9b01 --group-name afonseca-k8s-sg-workers --description afonseca-k8s-security-group-workers
aws --profile=test-k8s ec2 create-tags --resources sg-727dc908 --tags Key=Name,Value=afonseca-k8s-sg-masters
aws --profile=test-k8s ec2 create-tags --resources sg-757eca0f --tags Key=Name,Value=afonseca-k8s-sg-workers

aws --profile=test-k8s ec2 authorize-security-group-ingress --group-id sg-727dc908 --port 0-65535 --protocol tcp --source-group sg-757eca0f
aws --profile=test-k8s ec2 authorize-security-group-ingress --group-id sg-727dc908 --port 22 --protocol tcp --cidr 01.02.03.04/32
aws --profile=test-k8s ec2 authorize-security-group-ingress --group-id sg-757eca0f --port 0-65535 --protocol tcp --source-group sg-727dc908
aws --profile=test-k8s ec2 authorize-security-group-ingress --group-id sg-757eca0f --port 22 --protocol tcp --cidr 01.02.03.04/32
```
, where sg-727dc908 and sg-757eca0f are the security group IDs we got from the two first commands, respectively, and 01.02.03.04 is your local IP address (http://www.whatsmyip.org/)

### Provision the machines
```
aws --profile=test-k8s ec2 create-key-pair --key-name afonseca-k8s-key
```
, and copy the contents of KeyMaterial into ~/.ssh/afonseca-k8s-key.priv

Now do the following six times, creating three masters (afonseca-k8s-master01-3) and three workers (afonseca-k8s-worker01-3):
```
aws --profile=test-k8s ec2 run-instances --image-id ami-835b4efa --instance-type t2.small --key-name afonseca-k8s-key --security-group-ids sg-727dc908 --subnet-id subnet-4ce1072a --associate-public-ip-address
aws --profile=test-k8s ec2 create-tags --resources i-0526417e4384cc4cc --tags Key=Name,Value=afonseca-k8s-master01
```
, where i-0526417e4384cc4cc is the InstanceID you get from the previous step.

## Setup CA and create TLS certs

### Install CFSSL

```
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
```

### Set up a Certificate Authority

Create a CA configuration file:
```
cat > ca-config.json <<EOF
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
```

Create a CA certificate signing request:


```
cat > ca-csr.json <<EOF
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
```

### Generate a CA certificate and private key:

```
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

```
### Generate client and server TLS certificates

#### Create the Admin client certificate

```
cat > admin-csr.json <<EOF
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
```

Generate the admin client certificate and private key:

```
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin
```

#### Create the kube-proxy client certificate

Create the kube-proxy client certificate signing request:

```
cat > kube-proxy-csr.json <<EOF
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
```

Generate the kube-proxy client certificate and private key:

```
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

#### Create the kubernetes server certificate
TBD


# Next
- Create an EIP before setting up the server certificate
- Final Steps on this chapter

# Cleanup
- Review if IGW is still needed, as well as SSL access
