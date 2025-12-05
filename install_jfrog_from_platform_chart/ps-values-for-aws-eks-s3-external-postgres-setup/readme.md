# JFrog Platform (Large) – Setup (Artifactory, Xray, Curation/Catalog, no JAS)

Please review [JFrog Platform Reference Architecture](https://jfrog.com/help/r/jfrog-platform-reference-architecture/jfrog-platform-reference-architecture) .

This repo contains two templates:

- [secrets.tmpl](secrets.tmpl) – all required Kubernetes Secrets  
- [ps-lab-setup-with-s3-storage-no-jas.tmpl](ps-lab-setup-with-s3-storage-no-jas.tmpl) – minimal custom Helm values for a large t-shirt size  deployment of **Artifactory + Xray + Curation/Catalog** (no Advanced Security/JAS)

The steps below show how to fill in the templates, render them, and deploy.

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
### 2. Using ALB

If you are using ALB then configure the ALB in the `artifactory.ingress` as mentioned in 
the blog https://jfrog.com/blog/install-artifactory-on-eks/ ( See "Step 3: Configure the JFrog Platform Helm Chart" ) 
```
# name of the future ALB
     alb.ingress.kubernetes.io/load-balancer-name: yann-demo-lab-eks
```

-  The steps in [Deploying_in_AWS_EKS.md](Deploying_in_AWS_EKS.md) for the **visual sequence (flowchart-style)** that shows **every step** needed to successfully install **JFrog Artifactory on EKS** using **IRSA + S3 + ALB**, with the **correct trust and permissions policies** and  where the artifactory service account naming rule fits in the flow.

The relevant Helm values section similar to the blog is in  
[Deploying_in_AWS_EKS.md – values.yaml Artifactory Helm Config](./Deploying_in_AWS_EKS.md#-valuesyaml-artifactory-helm-config)

Some relevant JFrog Doc links for Creds to access the S3 bucket  are in:
- [ARTIFACTORY: Connect Artifactory to S3 Bucket with IAM Role](https://jfrog.com/help/r/active/artifactory-connect-artifactory-to-s3-bucket-with-iam-role)
- [Configure Artifactory to Use S3 Storage](https://jfrog.com/help/r/jfrog-installation-setup-documentation/configure-artifactory-to-use-s3-storage)
- [ARTIFACTORY: How to Configure an AWS S3 Object Store Using an IAM Role Instead of an IAM User](https://jfrog.com/help/r/artifactory-how-to-configure-an-aws-s3-object-store-using-an-iam-role-instead-of-an-iam-user)

---

### 3. Deploying the Helm chart with custom values
Deploy the JFrog platform helm chart with your custom values in temp/secrets.yaml similar to 
[../../examples/terraform/jfrog-platform-aws-install/README.md#install-jfrog-platform](../../examples/terraform/jfrog-platform-aws-install/README.md#install-jfrog-platform):
<!--
https://github.com/jfrog/charts/blob/master/examples/terraform/jfrog-platform-aws-install/README.md#install-jfrog-platform: 
-->

```
helm repo add jfrog https://charts.jfrog.io
helm repo update
```
Find the latest JFrog Platform chart version
```
helm search repo jfrog/jfrog-platform --versions |  head -n 2
```

All Product versions in chart 11.2.0 can be got from:
```
helm show chart jfrog/jfrog-platform --version 11.2.0 \
| yq '.dependencies[] | "\(.name): \(.version)"' \
| sed -E '/^(worker|artifactory|xray|distribution|catalog):/s/^([^:]+): 10([0-9]+\..*)$/\1: \2/'

```
Output:
```
postgresql: 15.5.20
rabbitmq: 15.4.1
artifactory: 7.117.10
xray: 3.124.11
catalog: 1.23.0
distribution: 2.32.0
worker: 1.153.0
```

<!--
Use the custom T-shirt size from the JFrog Platform chart sizing recommendations in https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/

Use the `rabbitmq HA Quorum` configuration from https://github.com/jfrog/charts/blob/master/stable/xray/rabbitmq/ha-quorum.yaml
and `rabbitmq` configuration from  https://github.com/jfrog/charts/blob/master/stable/xray/sizing/xray-large.yaml
-->
Use the custom T-shirt size from the JFrog Platform chart sizing recommendations in [../../stable/jfrog-platform/sizing/](../../stable/jfrog-platform/sizing/)

Use the `rabbitmq HA Quorum` configuration from [../../stable/xray/rabbitmq/ha-quorum.yaml](../../stable/xray/rabbitmq/ha-quorum.yaml)
and `rabbitmq` configuration from  [../../stable/xray/sizing/xray-large.yaml](../../stable/xray/sizing/xray-large.yaml)
The JFrog Platform chart uses the following child charts which have :
the T-shirt sizes and the default values.yaml for the underlying applications:
<!--
| Application  | T-Shirt Sizes Link | Default `values.yaml` Link |
|---------------|--------------------|-----------------------------|
| **Artifactory** | [sizing](https://github.com/jfrog/charts/tree/master/stable/artifactory/sizing) | [values.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/values.yaml) |
| **Xray** | [sizing](https://github.com/jfrog/charts/tree/master/stable/xray/sizing) | [values.yaml](https://github.com/jfrog/charts/blob/master/stable/xray/values.yaml) |
| **Catalog** | N/A | [values.yaml](https://github.com/jfrog/charts/blob/master/stable/catalog/values.yaml) |
| **Distribution** | [sizing](https://github.com/jfrog/charts/tree/master/stable/distribution/sizing) | [values.yaml](https://github.com/jfrog/charts/blob/master/stable/distribution/values.yaml) |
-->

| Application  | T-Shirt Sizes Link | Default `values.yaml` Link |
|---------------|--------------------|-----------------------------|
| **Artifactory** | [sizing](../../stable/artifactory/sizing) | [values.yaml](../../stable/artifactory/values.yaml) |
| **Xray** | [sizing](../../stable/xray/sizing) | [values.yaml](../../stable/xray/values.yaml) |
| **Catalog** | N/A | [values.yaml](../../stable/catalog/values.yaml) |
| **Distribution** | [sizing](../../stable/distribution/sizing) | [values.yaml](../../stable/distribution/values.yaml) |


---

## Set the External JFrog Base URL in Helm

When deploying the JFrog Platform Helm chart, you can set the external UI/base URL that users will access (e.g., your ingress DNS):

```bash
helm upgrade --install jfrog jfrog/jfrog-platform \
  --version "${JFROG_PLATFORM_CHART_VERSION}"   \
  --namespace $JFROG_PLATFORM_NAMESPACE --create-namespace \
  -f ./jfrog-platform/sizing/platform-<sizing>-.yaml \
  -f temp/ps-lab-setup-with-s3-storage-no-jas.yaml \
  --set global.jfrogUrlUI="https://<YOUR-EXTERNAL-DNS>"
  --timeout 600s
```

* Replace `https://<YOUR-EXTERNAL-DNS>` with your public/base URL (e.g., `https://jfrog.example.com`).
* This value is used by UI links and may be referenced by other services for callbacks or redirects.

---

### Access Artifactory Across Namespaces in Kubernetes (via `curl`)

How to `curl` the **Artifactory** service from a different namespace using its **Fully Qualified Domain Name (FQDN)**, and how to set the external JFrog base URL during a Helm deployment?

Kubernetes creates DNS entries for Services inside the cluster.  
When accessing a Service from **another namespace**, you should use its FQDN so DNS resolves unambiguously.

#### Service FQDN Format

```

<service-name>.<namespace>.svc.cluster.local

```

For Artifactory’s REST API health check (ping):

```

curl http://<artifactory-service>.<namespace>.svc.cluster.local:8082/artifactory/api/system/ping

````

Expected response:

```
OK
```

> If you see connection errors, verify the Service name, namespace, port, and that NetworkPolicies (if any) allow traffic between namespaces.

---






