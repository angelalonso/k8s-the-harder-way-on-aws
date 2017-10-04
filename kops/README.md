# K8s the practical (?) way: KOPS

Goal is create a K8s cluster with the following:

- Own key provided - This is needed at creation
- Using a domain of mine - This is needed at creation
- Private zone
- Bastion
- Scalable painlessly
- Upgradeable painlessly


## Automagically
### Create the Cluster
run ./create_kops-cluster.sh

### Delete the Cluster
run ./delete_kops-cluster.sh

## Manually

### Run the "bare minimum" cluster creation
run ./create-min_kops-cluster.sh

### Add a private zone
### Add a bastion
### Scale up worker nodes
### Scale up master nodes
### Scale down worker nodes
### Scale down master nodes
### Upgrade Kubernetes version


## Interesting related reads:
https://icicimov.github.io/blog/virtualization/Kubernetes-Cluster-in-AWS-with-Kops/
