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

