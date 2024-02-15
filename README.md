# Octopus Underwater App

This app is a simple web application that displays relevant resources for users that have completed their first deployment. It contains an underwater scene and links to blog posts

To create an EKS cluster and deploy:

* First, set up creds:
```
export AWS_PROFILE=<AWS Profile> && AWS_DEFAULT_REGION=<AWS Region>
```

* Create the cluster:
```
export cluster_name=octopus-demo-app
eksctl create cluster --name $cluster_name --version 1.28 --region $AWS_DEFAULT_REGION --nodegroup-name linux-nodes --node-type m4.large --nodes 2
```

* Create the IAM OIDC identity provider
```
eksctl utils associate-iam-oidc-provider --cluster $cluster_name --region us-east-1 --approve
```

* Download the IAM policy for the AWS Load Balancer controller and create it:
```
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json
```

* Create the Kubernetes IAM service account using the new policy ARN:
```
eksctl create iamserviceaccount  \
  --cluster=$cluster_name  \
  --namespace=kube-system  \
  --name=aws-load-balancer-controller  \
  --role-name=AmazonEKSLoadBalancerControllerRole  \
  --attach-policy-arn=<new policy ARN>  \
  --approve  \
  --region $AWS_DEFAULT_REGION
```

* Add the Helm repo hosting the AWS Load Balancer controller Helm chart and update
```
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
```

* Retrieve the VPC Id from the AWS EKS cluster console under the 'Networking' tab. Install the controller via the Helm chart:
```
helm install aws-load-balancer-controller eks/aws-load-balancer-controller  \
  -n kube-system  \
  --set clusterName=$cluster_name  \
  --set serviceAccount.create=false  \
  --set serviceAccount.name=aws-load-balancer-controller  \
  --set region=$AWS_DEFAULT_REGION  \
  --set vpcId=<VPC ID>
```

* Launch the app:
```
chmod +x create-deployment.yml
./create-deployment.yml
```

* Delete the deployment, service, and ingress:
```
kubectl delete -f octopus-underwater-app-deployment.yml
```
