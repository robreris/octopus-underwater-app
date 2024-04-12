# Octopus Underwater App Containerized Deployment in AWS EKS

This repo is a fork of the OctopusSamples ![octopus-underwater-app repository](https://github.com/OctopusSamples/octopus-underwater-app).

The steps below will walk you through creating a basic Kubernetes cluster in AWS EKS to which you can deploy the containerized application to. 

## Prerequisites

Some prerequisites you'll need to install:

![eksctl](https://eksctl.io/): The official CLI for Amazon EKS.

![helm](https://helm.sh): A popular Kubernetes package manager.

![kubectl](https://kubernetes.io/docs/tasks/tools/): The Kubernetes command line tool. 

You'll also need a set of ![AWS Access Keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html) with admin permissions, the ![AWS CLI](https://aws.amazon.com/cli/) set up to work in your terminal, and a Docker runtime, such as ![Rancher Desktop](https://docs.rancherdesktop.io/) if operating in a Windows environment.

Once you've get these prerequisites, configure a few important environment variables:

```
export AWS_PROFILE=<AWS Profile> && AWS_DEFAULT_REGION=<AWS Region>
export AWS_ACCOUNT_ID=<Your AWS Account ID>
export cluster_name=octopus-demo-app
```

## Container Creation 

For simplicity, this walkthrough will utilize AWS ECR for the image repository. 

To create the Docker image, simply run:

```
docker build -t octopus-underwater-app .
```

Then, create an AWS ECR repository and login:

```
export ECR_REPO=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
aws ecr create-repository --repository-name octopus-underwater-app
aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPO
```

Tag the image and push to the repository:
```
docker tag octopus-underwater-app:latest $ECR_REPO/octopus-underwater-app:latest
docker push $ECR_REPO/octopus-underwater-app:latest
```

## Cluster Creation and App Deployment

Now you're ready to create the cluster. The included oua-cluster.yml file contains a configuration for a basic Kubernetes cluster with two EC2 instances as worker nodes.

```
export cluster_name=octopus-demo-app
eksctl create cluster -f oua-cluster.yml 
```

We'll need to create the AWS IAM OIDC provider:
```
eksctl utils associate-iam-oidc-provider --cluster $cluster_name --region $AWS_DEFAULT_REGION --approve
```
More info on this can be found here: https://eksctl.io/usage/iamserviceaccounts/


Download the IAM policy for the ![AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/) and create it:
```
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json
```

Create the Kubernetes IAM service account using the new policy ARN:
```
export LBPolicy=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)

eksctl create iamserviceaccount  \
  --cluster=$cluster_name  \
  --namespace=kube-system  \
  --name=aws-load-balancer-controller  \
  --role-name=AmazonEKSLoadBalancerControllerRole  \
  --attach-policy-arn=$LBPolicy  \
  --approve  \
  --region $AWS_DEFAULT_REGION
```

Add the Helm repository hosting the AWS Load Balancer Controller Helm chart and update:
```
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
```

Retrieve the VPC Id from the AWS EKS cluster console under the 'Networking' tab. Install the controller via the Helm chart:
```
export K8S_VPC=$(eksctl get cluster $cluster_name -o json | jq -r '.[0].ResourcesVpcConfig.VpcId')

helm install aws-load-balancer-controller eks/aws-load-balancer-controller  \
  -n kube-system  \
  --set clusterName=$cluster_name  \
  --set serviceAccount.create=false  \
  --set serviceAccount.name=aws-load-balancer-controller  \
  --set region=$AWS_DEFAULT_REGION  \
  --set vpcId=$K8S_VPC
```

Launch the app:
```
sed -i 's/<insert ecr repo here>/$ECR_REPO\/octopus-underwater-app:latest/g' create-deployment.yml
chmod +x create-deployment.yml
./create-deployment.yml
```

Note: In case you've created your cluster with an identity distinct from the identity you use to access the AWS console and you'd like to view your cluster resources in the AWS EKS console, you'll need to add the permissions to your cluster:

```
eksctl create iamidentitymapping --cluster $cluster_name --region=$AWS_DEFAULT_REGION  \
   --arn <ARN of the role assumed by the identity used to access the console> \
   --username admin --group system:masters --no-duplicate-arns
``` 
You can find more details on this ![here](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html).

Delete the deployment, service, and ingress:
```
kubectl delete -f octopus-underwater-app-deployment.yml
```

Delete the cluster:
```
eksctl delete -f oua-cluster.yml
```
