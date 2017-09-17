# k8s-the-harder-way-on-aws
Notes and scripts about how to create a Kubernetes cluster on AWS from scratch.

Kubernetes the hard way in AWS is based on https://github.com/kelseyhightower/kubernetes-the-hard-way.

To be more precise, is is based of the 31.08.2017 version, https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/4ca7c4504612d55d9c42c21632ca4f4a0e9b4a52

## NOTES
- I only added what is missing on K. Hightower's "K8s the hard way" for projects under AWS.
- For the rest, I'd rather point at the originals.
- Even though this thing works, it is an unfinished, unpolished work, and it will probably remain so forever.
- As other, wiser people usually add, there's no guarantee of anything: BE CAREFUL WHEN YOU RUN ANY SCRIPT OR COMMAND FROM THIS REPO.

Let's start...

## 01 - Prerequisites and Conventions
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/01-prerequisites.md

On top of that:
- You have access to an AWS account. In my case on the us-west-2 region (cheapest, currently)
- You have enough rights. In my case, that meant IAM user with admin right, and a key/secret setup on .aws/credentials
    In my case, I am calling the profile test-k8s, no wonder you'll see this often in my commands
- You have awscli setup. In my case 'pip install awscli --upgrade --user' did the trick

## 02 - Installing the Client Tools
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-client-tools.md

## 03 - Provisioning Compute Resources
Based on https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md
and https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/1.4/docs/01-infrastructure-aws.md

NOTE: I decided to undocument this, since it was quickly outdated.
Follow the script's comments on https://github.com/angelalonso/k8s-the-harder-way-on-aws/blob/master/03_computer_resources.sh instead.


## 04 - Provisioning a CA and Generating TLS Certificates
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md

## 05 - Generating Kubernetes Configuration Files for Authentication
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/05-kubernetes-configuration-files.md

## 06 - Generating the Data Encryption Config and Key
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/06-data-encryption-keys.md

## 07 - Bootstrapping the etcd Cluster
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md

## 08 - Bootstrapping the Kubernetes Control Plane
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/08-bootstrapping-kubernetes-controllers.md

## 09 - Bootstrapping the Kubernetes Worker Nodes
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/09-bootstrapping-kubernetes-workers.md

## 10 - Configuring kubectl for Remote Access
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/10-configuring-kubectl.md

## 11 - Provisioning Pod Network Routes
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/11-pod-network-routes.md

## 12 - Deploying the DNS Cluster Add-on
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/12-dns-addon.md

## 12 - Smoke Test
Follow https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/13-smoke-test.md

## 14 - Cleanup
I Actually did this from scratch.

As you can see on the script all I do is try to delete all dependencies before I delete the VPC, and if any of those does not get deleted on time, I repeat it.

Probably anyone can improve it with some checks and waits. For me, it just works most of the time (unless something went wrong already on step 3, in this case, you'll have to remove manually)

