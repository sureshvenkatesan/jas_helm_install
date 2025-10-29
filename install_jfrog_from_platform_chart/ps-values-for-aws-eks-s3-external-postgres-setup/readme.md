### 1. Create the secrets
Review  the secrets in [secrets.yaml](secrets.yaml)

Review the environment variables to use in the secrets and the values yaml in [ps-lab-setup.env](ps-lab-setup.env)

Create the environment variables to use in the secrets and the values yaml

Create the secrets in [secrets.yaml](secrets.yaml)

**Note:** You can create the S3 binarystore configuration either as as a secret or directly in the 
[ps-lab-setup-with-s3-storage.yaml](ps-lab-setup-with-s3-storage.yaml)


If you are using ALB then configure the ALB in the `artifactory.ingress` as mentioned in 
the blog https://jfrog.com/blog/install-artifactory-on-eks/ ( See "Step 3: Configure the JFrog Platform Helm Chart" ) 
```
# name of the future ALB
     alb.ingress.kubernetes.io/load-balancer-name: yann-demo-lab-eks
```

-  The steps in [Deploying_in_AWS_EKS.md](Deploying_in_AWS_EKS.md) for the **visual sequence (flowchart-style)** that shows **every step** needed to successfully install **JFrog Artifactory on EKS** using **IRSA + S3 + ALB**, with the **correct trust and permissions policies** and  where the artifactory service account naming rule fits in the flow.

The relevant helm values section similar to the blog is in
 https://github.com/sureshvenkatesan/jas_helm_install/blob/master/Deploying_in_AWS_EKS.md#-valuesyaml-artifactory-helm-config