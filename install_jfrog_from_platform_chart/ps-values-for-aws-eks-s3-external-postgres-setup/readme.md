### 1. Create the secrets
- Review  the secrets in [secrets.tmpl](secrets.tmpl)

- Review the environment variables to use in the secrets and the values tmpl in [ps-lab-setup.env](ps-lab-setup.env)

- Create the environment variables .

- Use the [`envsubst`](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) command to populate secrets from environment variables in the secrets and values template files.

**Note:** You can create the S3 binarystore configuration either as as a secret or directly in the 
[ps-lab-setup-with-s3-storage-no-jas.tmpl](ps-lab-setup-with-s3-storage-no-jas.tmpl)

```
envsubst < secrets.tmpl > temp/secrets.yaml
envsubst < ps-lab-setup-with-s3-storage-no-jas.tmpl > temp/ps-lab-setup-with-s3-storage-no-jas.yaml
```

Create the secrets using temp/secrets.yaml  
```
kubectl apply -f  temp/secrets.yaml
```
---
### 2. USing ALB

If you are using ALB then configure the ALB in the `artifactory.ingress` as mentioned in 
the blog https://jfrog.com/blog/install-artifactory-on-eks/ ( See "Step 3: Configure the JFrog Platform Helm Chart" ) 
```
# name of the future ALB
     alb.ingress.kubernetes.io/load-balancer-name: yann-demo-lab-eks
```

-  The steps in [Deploying_in_AWS_EKS.md](Deploying_in_AWS_EKS.md) for the **visual sequence (flowchart-style)** that shows **every step** needed to successfully install **JFrog Artifactory on EKS** using **IRSA + S3 + ALB**, with the **correct trust and permissions policies** and  where the artifactory service account naming rule fits in the flow.

The relevant helm values section similar to the blog is in
 https://github.com/sureshvenkatesan/jas_helm_install/blob/master/Deploying_in_AWS_EKS.md#-valuesyaml-artifactory-helm-config

---

### 3. Deploying the Helm chart with custom values
Deploy the JFrog platform helm chart with your custom values in temp/secrets.yaml similar to 
https://github.com/jfrog/charts/blob/master/examples/terraform/jfrog-platform-aws-install/README.md#install-jfrog-platform:

```
helm repo add jfrog https://charts.jfrog.io
helm repo update
```
Find the latest JFrog Platform chart version
```
helm search repo jfrog/jfrog-platform --versions |  head -n 2
```

Use the custom T-shirt size from https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/

Use the `rabbitmq HA Quorum` configuration from https://github.com/jfrog/charts/blob/master/stable/xray/rabbitmq/ha-quorum.yaml
and `rabbitmq` configuration from  https://github.com/jfrog/charts/blob/master/stable/xray/sizing/xray-large.yaml

```
helm upgrade --install jfrog jfrog/jfrog-platform \
  --version "${JFROG_PLATFORM_CHART_VERSION}"   \
  --namespace $JFROG_PLATFORM_NAMESPACE --create-namespace \
  -f ./jfrog-platform/sizing/platform-<sizing>-.yaml \
  -f temp/ps-lab-setup-with-s3-storage-no-jas.yaml \
  --timeout 600s
```




