## Step-by-Step install of Artifactory, Xray, JAS, Catalog, Curation


Rather than installing Artifactory, Xray, and JAS all at once (on AWS EKS, GKE, etc.), it is recommended to follow this sequence:

```text
a) Create the necessary secrets (for user passwords, binarystore configuration, system.yaml, etc.)
b) Install Artifactory first, log in, and configure the Artifactory base URL
c) Install Xray and verify its successful connection to Artifactory
d) Perform Xray DB Sync
e) Enable JAS
f) Enable Package Catalog and Curation
```

This README explains how to perform the above steps using the [jfrog/platform](https://github.com/jfrog/charts/tree/master/stable/jfrog-platform) chart by managing a nested `values.yaml` built from the following child charts:
- [jfrog/artifactory](https://github.com/jfrog/charts/tree/master/stable/artifactory)
- [jfrog/xray](https://github.com/jfrog/charts/tree/master/stable/xray) (for Xray and JAS)
- [catalog](https://github.com/jfrog/charts/tree/master/stable/catalog)

It also covers:
- How to use the [`envsubst`](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) command to populate secrets from environment variables
- A step-by-step method to refine the `values.yaml` file and produce the final version required for the Helm installation

  
Note: You can parse the https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/values.yaml  with  https://yaml.vercel.app/ 

---
## Deploying in AWS EKS
When using AWS EKS  please review the blog - [A Guide to Installing the JFrog Platform on Amazon EKS](https://jfrog.com/blog/install-artifactory-on-eks/)
, that outlines the  prerequisites and steps required to install and configure the JFrog Platform in Amazon EKS,
including setting up two AWS systems:
- IAM Roles for Service Accounts (IRSA) and
- Application Load Balancer (ALB).

There are some typos in that blog :
 For example , in "Step 1: Set up the IRSA" section the "Example configuration that you can apply to your OIDC 
connector" used the following which is not correct.
```text
"oidc.eks..amazonaws.com/id/:sub": "system:serviceaccount::artifactory"
```

**Here are the steps:**

1. Create an IAM role that the Artifactory's pods service account can take on, equipped with a policy that bestows upon 
them the privileges to list,  read from and write i.e the `"Action": "s3:*"` to the 'davidro-binstore' S3 bucket. 
This bucket is intended to serve as the filestore for Artifactory.

Here is an example  policy:
```text
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAllOnFilestoreBucket",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": ["arn:aws:s3:::davidro-binstore","arn:aws:s3:::davidro-binstore/*"]
        }
    ]
}
```
2. "Subsequently, configure the cluster OIDC provider as the source of IAM identity, if necessary. Detailed instructions can be found in the following documentation:

- [Enabling IAM Roles for Service Accounts on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)
- [Associating a Service Account with a Role on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

Once these steps are completed, you must establish the OIDC provider as a trusted identity for the IAM role authorized to access the filestore bucket."


The trusted identity JSON statement should be similar to this one below
```text
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::912345675:oidc-provider/oidc.eks.eu-west-3.amazonaws.com/id/123456AC6C4D61425521234561E34"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.eu-west-3.amazonaws.com/id/123456AC6C4D61425521234561E34:sub": "system:serviceaccount:JFROG_PLATFORM_NAMESPACE:JFROG_PLATFORM_NAME-artifactory",
                    "oidc.eks.eu-west-3.amazonaws.com/id/123456AC6C4D61425521234561E34:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
```
Please note that the service account's name in the statement must correspond with the service account that will be 
established for the Artifactory pods. By default, this service account takes the format of {JFROG_PLATFORM_NAMESPACE}:{JFROG_PLATFORM_NAME}-artifactory in its naming.

For example in your K8s cluster if  you have:
```text
export JFROG_PLATFORM_NAMESPACE=ps-jfrog-platform
export JFROG_PLATFORM_NAME=ps-jfrog-platform-release
```

Then the service account takes the format:
`"system:serviceaccount:ps-jfrog-platform:ps-jfrog-platform-release-artifactory"`

### Application Load Balancer as Ingress gateway setup
You can refer to either of these resources for guidance:
- The documentation available at: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- Alternatively, you can also explore: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/

Main steps are highlighted below

1. Create IAM policy for the load balancer .  This step is required only if the policy doesn't already exists.
```text
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.1/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name ALBControllerIAMPolicy \
    --policy-document file://iam-policy.json
```
2. use eksctl to create a kubernetes service account in kube-system namespace that will be able to
```text
eksctl create iamserviceaccount \
--cluster=davidroemeademocluster04C94C95-17b0370933c844e792601f7998cae6bf \
--name=alb-controller \ 
--attach-policy-arn=arn:aws:iam::925310216015:policy/ALBControllerIAMPolicy \
--override-existing-serviceaccounts \
--namespace=kube-system \
--approve
```
Please be aware that if you encounter difficulties, especially if your cluster was established using Infrastructure as Code (IAC) such as CDK, you might need to follow [this guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting_iam.html#security-iam-troubleshoot-cannot-view-nodes-or-workloads) to gain the necessary privileges for manually executing the equivalent actions of the aforementioned eksctl command within your cluster.

If you find yourself in a situation where you need to manually create the kube-system role, you can utilize the information provided in this guide: [Link](https://stackoverflow.com/questions/65934606/what-does-eksctl-create-iamserviceaccount-do-under-the-hood-on-an-eks-cluster).

Once the service account intended for use by the alb-ingress-controller pod is established and associated with an IAM role, the next step is to install the helm chart of the alb ingress controller within your EKS cluster's kube-system namespace.

```text
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts

helm install aws-load-balancer-controller \
    --set clusterName=davidroemeademocluster04C94C95-17b0370933c844e792601f7998cae6bf \
    --set serviceAccount.create=false \
    --set serviceAccount.name=alb-ingress-controller \
    --set ingress-class=alb \
    -n kube-system \
    eks/aws-load-balancer-controller

```

Once your cluster is all enabled, you can install the Jfrog platform using values.yaml that can be generated as explained in next section.

---
## Steps to specify the helm values.yaml for step-by-step install of Artifactory, Xray, JAS, Catalog, Curation

### Prerequisites:


Install `envsubst` as per https://skofgar.ch/dev/2020/08/how-to-quickly-replace-environment-variables-in-a-file/
```
brew install gettext
```
As mentioned in [JFrog Platform Helm Chart Installation Steps](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-platform-helm-chart-installation-steps):
Add the JFrog Helm Charts repository to your Helm client.

```
helm repo add jfrog https://charts.jfrog.io
helm repo update

```

#### How do I find the jfrog/platform char version that will be used ?
```
helm search repo jfrog/jfrog-platform --versions |  head -n 2
helm search repo jfrog/artifactory --versions |  head -n 2
helm search repo jfrog/xray --versions |  head -n 2
```
or

**Check the JFrog Charts GitHub Repository:**


The `CHANGELOG.md` file in the `jfrog/charts` GitHub repository typically provides details about the latest releases: https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/CHANGELOG.md.  
By reviewing this file, you can track the release history and identify the most recent version.  
As of April 24, 2025, the latest stable `JFROG_PLATFORM_CHART_VERSION` to use in your Helm upgrade command is **11.1.0**.


---

### 1. Swich to correct folder to run commands:
Download this git repo.

Next  run:
```text
cd values/For_PROD_Setup
```

### 2. Environment variables:
Set the following Environmental variables based on your Deployment K8s environment where you will install the 
JFrog Platform.

**Note:** the CLOUD_PROVIDER can be gcp or aws ( JFrog Helm charts support Azure as well but this readme was created 
only based on gcp or aws  )


```text
export CLOUD_PROVIDER=gcp
export JFROG_PLATFORM_NAMESPACE=ps-jfrog-platform
# JFROG_PLATFORM_NAME is the Helm release name
export JFROG_PLATFORM_NAME=ps-jfrog-platform-release

export RT_MASTER_KEY=$(openssl rand -hex 32)
# Save this master key to reuse it later
echo ${RT_MASTER_KEY}
# or you can hardcode it to
export RT_MASTER_KEY=02ba23e285e065d2a372b889ac3dbd51510dd0399875f95294312634f50b6960
export XRAY_MASTER_KEY=33e1a43ac92be461ef98cec5b6120f21cf69cd005011c608529ddc33e7bacb7c
export CATALOG_MASTER_KEY=e4d873b4e7d56657df61d63ba2989f468178c3f22440bd068ad5bb84cafb97ff

export JOIN_KEY=$(openssl rand -hex 32)
# Save this join key to reuse it later
echo ${JOIN_KEY}
# or you can hardcode it to
export JOIN_KEY=763d4bdf02ff4cc16d7c5cf2abeccf3f243b5557bf738ec5438fd55df0cec3cc

export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=password

export DB_SERVER=cloudsql-proxy
export BINARYSTOREXML_BUCKETNAME=sureshv-ps-artifactory-storage

export RT_DATABASE_USER=artifactory
export RT_DATABASE_PASSWORD=artifactory
export ARTIFACTORY_DB=artifactory

export MY_RABBITMQ_ADMIN_USER_PASSWORD=password1
export XRAY_DATABASE_USER=xray
export XRAY_DATABASE_PASSWORD=xray
export XRAY_DB=xray

export CATALOG_DATABASE_USER=catalog
export CATALOG_DATABASE_PASSWORD=catalog
export CATALOG_DB=catalogdb

export RT_VERSION=7.111.4
export JFROG_PLATFORM_CHART_VERSION=11.1.0
export XRAY_VERSION=3.111.25
```
---

### 3. Prepare the K8s environment:

**If you are starting with a clean k8s environment:**

Create the Namespace:
```
kubectl create ns  $JFROG_PLATFORM_NAMESPACE
```

**Or**


**If you are not starting with a clean k8s environment:**

Use below commands if you need to run the Helm release multiple times without starting from a clean Kubernetes environment. 

They are helpful for iterative testing or redeployments.
```text
helm uninstall $JFROG_PLATFORM_NAME -n $JFROG_PLATFORM_NAMESPACE

or to rollback a revision:

helm rollback $JFROG_PLATFORM_NAME REVISION_NUMBER -n $JFROG_PLATFORM_NAMESPACE
```

To get the release name of a Helm chart, you can use the following command:
```text
helm list -n  $JFROG_PLATFORM_NAMESPACE

NAME                     	NAMESPACE        	REVISION	UPDATED                             	STATUS  	CHART                 	APP VERSION
ps-jfrog-platform-release	ps-jfrog-platform	3       	2023-07-10 12:33:19.393492 -0700 PDT	deployed	jfrog-platform-10.13.1	7.59.9
```

Replace <namespace> with the actual namespace where the Helm release is deployed. 

If you don't specify the --namespace flag, it will list releases across all namespaces.


Delete PVCs as needed:
```text
kubectl delete pvc artifactory-volume-$JFROG_PLATFORM_NAME-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE
kubectl delete pvc data-$JFROG_PLATFORM_NAME-rabbitmq-0 -n $JFROG_PLATFORM_NAMESPACE
kubectl delete pvc data-volume-$JFROG_PLATFORM_NAME-xray-0 -n $JFROG_PLATFORM_NAMESPACE
kubectl delete pvc data-volume-$JFROG_PLATFORM_NAME-xray-1 -n $JFROG_PLATFORM_NAMESPACE
etc
```

Delete Namespace only if needed as this will delete all the secrets as well:
```text
kubectl delete ns  $JFROG_PLATFORM_NAMESPACE
```

**Specific to my Lab Setup:**  
I followed the steps outlined in [Creating only "CloudSQL proxy" and secrets for "binarystore.xml"](https://github.com/sureshvenkatesan/jf-gcp-env/tree/feature/jf_with_cloudsql?tab=readme-ov-file#creating-only-cloudsql-proxy-and-secrets-for-binarystorexml-), which also provisions the Namespace using Terraform.

---

### 4. Create the secrets

**Master and Join Keys:**
```text
kubectl delete secret rt-masterkey-secret  -n $JFROG_PLATFORM_NAMESPACE
kubectl delete secret joinkey-secret   -n $JFROG_PLATFORM_NAMESPACE

kubectl create secret generic rt-masterkey-secret --from-literal=master-key=${RT_MASTER_KEY} -n $JFROG_PLATFORM_NAMESPACE
# if using xray:
kubectl delete secret xray-masterkey-secret  -n $JFROG_PLATFORM_NAMESPACE
kubectl create secret generic xray-masterkey-secret --from-literal=master-key=${XRAY_MASTER_KEY} -n $JFROG_PLATFORM_NAMESPACE
# if using catalog:
kubectl delete secret catalog-masterkey-secret  -n $JFROG_PLATFORM_NAMESPACE
kubectl create secret generic catalog-masterkey-secret --from-literal=master-key=${CATALOG_MASTER_KEY} -n $JFROG_PLATFORM_NAMESPACE

# Same Join key is used by Artifactory, Xay and Catalog pods:
kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $JFROG_PLATFORM_NAMESPACE
```

**License:**

Create a secret for license with the dataKey as "artifactory.lic" for HA or standalone ( if you want you can name the 
dataKey as artifactory.cluster.license for HA but not necessary) :
```text
kubectl delete secret  artifactory-license  -n $JFROG_PLATFORM_NAMESPACE

kubectl create secret generic artifactory-license --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $JFROG_PLATFORM_NAMESPACE
```
Verify the license secret using:
```
kubectl get secret artifactory-license -o yaml -n $JFROG_PLATFORM_NAMESPACE
or
kubectl get secret artifactory-license -o json -n $JFROG_PLATFORM_NAMESPACE | jq -r '.data."artifactory.lic"' | base64 --decode

```



---

### 5. step-by-step approach to improvise the values.yaml  we will finally use:

**Note:** As of February 14, 2025, the settings from [`artifactory-small.yaml`](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-small.yaml) are already incorporated into [`platform-small.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/platform-small.yaml).




---
#### a) Artifactory Database Credentials:
Override using the [2_artifactory_db_passwords.yaml](values/For_PROD_Setup/2_artifactory_db_passwords.yaml)


```text
kubectl delete secret  artifactory-database-creds  -n $JFROG_PLATFORM_NAMESPACE

kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $JFROG_PLATFORM_NAMESPACE
```


---

#### b) The artifactory default admin user secret:
Override using [3_artifactory_admin_user.yaml](values/For_PROD_Setup/3_artifactory_admin_user.yaml)

Review KB [ARTIFACTORY: How To Unlock A User(s) Who Is Locked Out Of Artifactory and Recover Admin Account](https://jfrog.com/help/r/artifactory-how-to-unlock-a-user-s-who-is-locked-out-of-artifactory-and-recover-admin-account)

```text
kubectl delete secret  art-creds  -n $JFROG_PLATFORM_NAMESPACE

kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=Test@123' -n $JFROG_PLATFORM_NAMESPACE
```


---

#### c) Override the binaryStore

For AWS use [S3 Direct Upload Template (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended) . For example: [4_custom-binarystore-s3-direct-use_instance-creds.yaml](values/For_PROD_Setup/4_custom-binarystore-s3-direct-use_instance-creds.yaml) :
```
kubectl apply -f 4_custom-binarystore-s3-direct-use_instance-creds.yaml -n $JFROG_PLATFORM_NAMESPACE
```
or

For GCP use [google-storage-v2-direct template configuration (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-v2-direct-template-configuration-recommended) mentioned in [Google Storage Binary Provider Native Client Template](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-binary-provider-native-client-template) :

Note: In my lab I created the secrets `artifactory-gcp-creds` and `custom-binarystore`  with [Creating only "CloudSql proxy" and secrets for "binarystore.xml"](https://github.com/sureshvenkatesan/jf-gcp-env/tree/feature/jf_with_cloudsql?tab=readme-ov-file#creating-only-cloudsql-proxy-and-secrets-for-binarystorexml-) .

Please create secrets `artifactory-gcp-creds` and `custom-binarystore` as mentiond below:

```
kubectl delete secret  artifactory-gcp-creds -n $JFROG_PLATFORM_NAMESPACE

kubectl create secret generic artifactory-gcp-creds  --from-file="gcp.credentials.json=/Users/sureshv/.gcp/support-team_gco_project_ServiceAccount.json" \
-n $JFROG_PLATFORM_NAMESPACE

envsubst < binarystore_config/custom-binarystore-gcp.tmpl > binarystore_config/custom-binarystore.yaml

kubectl apply -f binarystore_config/custom-binarystore.yaml -n $JFROG_PLATFORM_NAMESPACE
```
---

#### d) Tuning as per KB

The tuning recommendations from the KB article [How do I tune Artifactory for heavy loads?](https://jfrog.com/help/r/how-do-i-tune-artifactory-for-heavy-loads/how-do-i-tune-artifactory-for-heavy-loads) are already incorporated into the [`platform-small.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/platform-small.yaml) for TEST environments and [`platform-large.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/platform-large.yaml) for PROD environments during Step 1.  
Additionally, these tunings are reflected in the default values from:
- [`jfrog-platform/values.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/values.yaml)
- [`artifactory/values.yaml`](https://github.com/jfrog/charts/blob/master/stable/artifactory/values.yaml)


#### e) Deploy Artifactory
Verify the enabled services using:
```
yq eval -o=json '.' "0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml" | jq -r 'paths(scalars) | join(".")'

yq eval -o=json '.' "0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml" | jq -r 'paths(scalars) as $p | {"\($p | join("."))": getpath($p)}' | grep -i enabled
```

Deploy Artifactory using helm , then check if artifactory server starts and you can login to the Artifactory UI.
```
helm  upgrade --install $JFROG_PLATFORM_NAME \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f platform-small.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
--namespace $JFROG_PLATFORM_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}"  
```

**Note:**  
The Artifactory pod is deployed as a StatefulSet, and the PVC size is determined by the `artifactory.persistence.mountPath` setting (i.e., `/var/opt/jfrog/artifactory`) when `artifactory.persistence.enabled` is set to `true`. By default, when using the Platform chart, the size is set to `200Gi` via the `artifactory.artifactory.persistence.size` parameter (see [values.yaml line 285](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/values.yaml#L285)).

If you configure GCP storage by setting `artifactory.artifactory.persistence.customBinarystoreXmlSecret` and `artifactory.artifactory.persistence.googleStorage`, the filestore will **not** reside under `/var/opt/jfrog/artifactory/data/artifactory`. In this case, the PVC size does **not** include the Google Cloud Storage bucket size. The Google Storage usage can only be monitored via the Artifactory UI under **Administration > Monitoring > Storage**.

Similarly, the Xray pod (also a StatefulSet) defines its PVC size through `xray.common.persistence.size`, which defaults to `200Gi`. In my setup, I override this value to `100Gi` in [`values/For_PROD_Setup/6_xray_db_passwords.yaml`](values/For_PROD_Setup/6_xray_db_passwords.yaml).  
However, when using JAS, it is recommended to increase the PVC size to at least `400Gi`, as noted in earlier T-shirt sizing recommendations from [Xray sizing](https://github.com/jfrog/charts/tree/master/stable/xray/sizing) or "300–500 GB" as mentioned in the following references:

**References:**
- [JFrog Advanced Security Prerequisites](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-advanced-security-prerequisites)
- [JFrog Platform: Reference Architecture](https://jfrog.com/help/r/jfrog-platform-reference-architecture/jfrog-platform-reference-architecture)
- [Artifactory Self-Hosted Performance Benchmark Report – PostgreSQL](https://jfrog.com/help/r/artifactory-artifactory-self-hosted-performance-benchmark-report-may-2024/artifactory-self-hosted-performance-benchmark-report-postgresql)


#### f) Troubleshooting Artifactory Startup:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c artifactory -n $JFROG_PLATFORM_NAMESPACE
kubectl logs  -l app=artifactory -n $JFROG_PLATFORM_NAMESPACE --all-containers
kubectl logs -f -l app=artifactory -n $JFROG_PLATFORM_NAMESPACE --all-containers --max-log-requests=15
kubectl delete pod ps-jfrog-platform-release-artifactory-0  -n $JFROG_PLATFORM_NAMESPACE
kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE

watch -n 10 "kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE | tail -n 20"

kubectl get pod ps-jfrog-platform-release-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE -o jsonpath='{.spec.containers[*].name}'
Output:
router frontend metadata onemodel event jfconnect access topology observability artifactory

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory  -- cat /opt/jfrog/artifactory/var/etc/system.yaml
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory  -- cat /opt/jfrog/artifactory/var/etc/security/master.key

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory   -n $JFROG_PLATFORM_NAMESPACE -- cat /tmp/gcp.credentials.json

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory   -n $JFROG_PLATFORM_NAMESPACE -- ls /opt/jfrog/artifactory/var/etc/artifactory
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory   -n $JFROG_PLATFORM_NAMESPACE -- cat /opt/jfrog/artifactory/var/etc/artifactory/gcp.credentials.json
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory   -n $JFROG_PLATFORM_NAMESPACE -- cat /opt/jfrog/artifactory/var/etc/artifactory/binarystore.xml
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory   -n $JFROG_PLATFORM_NAMESPACE -- cat /opt/jfrog/artifactory/var/etc/artifactory/artifactory.cluster.license


kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c router -- bash 
kubectl get secret artifactory-gcp-creds  -n $JFROG_PLATFORM_NAMESPACE -o json | jq '.data | map_values(@base64d)'
```
**K8s Networking:**

In my terrafrom setup of my k8s cluster (GKE in GCP) , I am using:

**GCP Networking**
```
vpc_cidr       = "10.0.0.0/16"
pods_cidr      = "10.1.0.0/16"
services_cidr  = "10.2.0.0/16"
```
Check Pod’s Host IP via Downward API (Kubernetes-native way):
```
kubectl get pod ps-jfrog-platform-release-artifactory-0  -n $JFROG_PLATFORM_NAMESPACE -o jsonpath='{.status.hostIP}'
Output: 10.0.0.20 --> This is from the vpc_cidr
```
Artifactory router container:
```
kubectl exec -it ps-jfrog-platform-release-artifactory-0   -n $JFROG_PLATFORM_NAMESPACE  -c router -- hostname -i
Output: 10.1.3.3 --> This is from the pods_cidr

kubectl exec -it ps-jfrog-platform-release-artifactory-0   -n $JFROG_PLATFORM_NAMESPACE  -c router -- cat /etc/hosts
```


---
**Optional Steps:**
- Set the Artifactory base url using the output you see from below in the `http://$SERVICE_HOSTNAME/ui/admin/configuration/general`:
```
export SERVICE_HOSTNAME=$(kubectl get svc --namespace ps-jfrog-platform ps-jfrog-platform-release-artifactory-nginx --template "{{ (index .status.loadBalancer.ingress 0).ip }}")
echo http://$SERVICE_HOSTNAME
```
For example I set it to: http://100.231.185.7 . 

- Set  the Server Name . 

For example: I set it to "sureshvps".

---
**Upload File to a Local Repository**
- Next Upload a file to `example-repo-local`  repository and see if it is successful , by tailing the artifactory-service.log using:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c artifactory
```

If it fails check the binarystore.xml using:
```
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- ls -al  /opt/jfrog/artifactory/var/etc/artifactory

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/artifactory/var/etc/artifactory/binarystore.xml
```

Since I used GCP I also verified if I have the correct GCP service account using:
```
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/artifactory/var/etc/artifactory/gcp.credentials.json

```
If invalid you can remove it using the following:
```
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- rm -rf /opt/jfrog/artifactory/var/etc/artifactory/gcp.credentials.json
```
The fix the GCP creds , delete the `ps-jfrog-platform-release-artifactory-0` pod and see if the file upload works.

Note: If a K8s cluster node of the GKE cluster is undergoing maintenance and the pod is assigned to another node and
```
kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $JFROG_PLATFORM_NAMESPACE
```
shows below error:
```
Events:
  Type     Reason              Age   From                     Message
  ----     ------              ----  ----                     -------
  Normal   Scheduled           24s   default-scheduler        Successfully assigned ps-jfrog-platform/ps-jfrog-platform-release-artifactory-0 to gke-sureshv-ps-clust-sureshv-ps-node--ea322457-w7gd
  Warning  FailedAttachVolume  24s   attachdetach-controller  Multi-Attach error for volume "pvc-23719d6c-bf0f-488b-90e8-8818dacd3364" Volume is already exclusively attached to one node and can't be attached to another
```
After 5-6 min it should get resolved and you will see:
```
Normal   SuccessfulAttachVolume  5m4s   attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-23719d6c-bf0f-488b-90e8-8818dacd3364"
```
Then redo a file upload test to `example-repo-local`  repository and see if it is successful .

---
### 6. Deploying Xray
#### a) Xray Database secret


```text
kubectl delete secret generic xray-database-creds -n $JFROG_PLATFORM_NAMESPACE
kubectl create secret generic xray-database-creds \
--from-literal=db-user=$XRAY_DATABASE_USER \
--from-literal=db-password=$XRAY_DATABASE_PASSWORD \
--from-literal=db-url=postgres://$DB_SERVER:5432/$XRAY_DB\?sslmode=disable -n $JFROG_PLATFORM_NAMESPACE
```

Verify using jq:
If "jq --version" >=1.6  where jq  @base64d filter is avaiable use :
```
kubectl get secret xray-database-creds  -n $JFROG_PLATFORM_NAMESPACE -o json | jq '.data | map_values(@base64d)'
```
otherwise use:
```
bash decode_secret.sh <secret-to-decrypt>  <namespace>
```

 
#### b) Secret for Rabbitmq admin password:

The RabbitMQ username, as defined in [Xray's `values.yaml`](https://github.com/jfrog/charts/blob/master/stable/xray/values.yaml#L514), is hardcoded to `"guest"`. It can only be changed to `"admin"` through a value setting, not through a secret, as specified in [Bitnami's `values.yaml`](https://github.com/bitnami/charts/blob/main/bitnami/rabbitmq/values.yaml#L155).  
We configure it as `"admin"` using `rabbitmq.auth.username` in [`6_xray_db_passwords.yaml`](values/For_PROD_Setup/6_xray_db_passwords.yaml).

Also configure the RabbitMQ password using a secret (with the key `rabbitmq-password`) by setting `rabbitmq.auth.existingPasswordSecret`, as demonstrated in [`6_xray_db_passwords.yaml`](values/For_PROD_Setup/6_xray_db_passwords.yaml).

```
kubectl create secret generic rabbitmq-admin-creds \
--from-literal=rabbitmq-password=$MY_RABBITMQ_ADMIN_USER_PASSWORD -n $JFROG_PLATFORM_NAMESPACE 
```


#### c) Nest the xray sizing yaml file from Xray chart:

Take the sizing file from [`xray-xsmall.yaml`](https://github.com/jfrog/charts/blob/master/stable/xray/sizing/xray-xsmall.yaml) (or whichever T-shirt size YAML you prefer for Xray) and indent its contents under the `xray:` section to use it with the `jfrog/platform` chart.  
I followed this approach because I wanted to use:
- Artifactory with the [`platform-small.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/platform-small.yaml) T-shirt size
- Xray with the [`platform-xsmall.yaml`](https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/sizing/platform-xsmall.yaml) T-shirt size

```
python ../../scripts/nest_yaml_with_comments.py 6_xray-xsmall.yaml \
 xray -o 6_xray-xsmall-nested.yaml 
```

#### d) Deploy Xray 

Note: In [values/For_PROD_Setup/6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml) I have set "JF_SHARED_RABBITMQ_VHOST" to "xray" in `xray.common.extraEnvVars` 

Here is the helm command to enable  Xray:
```
helm  upgrade --install $JFROG_PLATFORM_NAME \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f platform-small.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
--namespace $JFROG_PLATFORM_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```

You can tail the Artifactory's access log to see that Xray connects to Access service:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c access -n $JFROG_PLATFORM_NAMESPACE
```
Xray router container connects to the Artifactory's access service via the ClusterIP service `ps-jfrog-platform-release-artifactory` port 8082 as mentioned in the `global.jfrogUrl` and then the access service sends the token 
in the response via `shared.node.ip`  in the [Xray System YAML](https://jfrog.com/help/r/jfrog-installation-setup-documentation/xray-system-yaml)  which is `10.1.2.16` in below example
```
kubectl exec -it ps-jfrog-platform-release-xray-0  -n $JFROG_PLATFORM_NAMESPACE  -c router -- hostname -i
10.1.2.16 --> This is from the pods_cidr. 
```

You should find the log entries similar to the following:
```
2025-04-21T05:19:42.084Z [jfac ] [INFO ] [5045b8a5b8ff60fd] [.j.a.s.s.r.JoinServiceImpl:109] [27.0.0.1-8040-exec-6] - Router join request: using external topology so skipping router NodeId and IP validation
2025-04-21T05:19:42.101Z [jfac ] [INFO ] [5045b8a5b8ff60fd] [.r.ServiceTokenProviderImpl:89] [27.0.0.1-8040-exec-6] - Cluster join: Successfully joined jfrou@01jsbckda0wv9paf2k746h0xp9 with node id ps-jfrog-platform-release-xray-0
```



#### f) Troubleshoot Xray setup:
```
kubectl  delete pod ps-jfrog-platform-release-xray-pre-upgrade-hook-wpk8l ps-jfrog-platform-release-xray-0 --namespace $JFROG_PLATFORM_NAMESPACE
kubectl  delete pod  ps-jfrog-platform-release-xray-0 --namespace $JFROG_PLATFORM_NAMESPACE

kubectl describe pod ps-jfrog-platform-release-xray-0 -n $JFROG_PLATFORM_NAMESPACE
watch -n 15 "kubectl describe pod ps-jfrog-platform-release-xray-0 -n $JFROG_PLATFORM_NAMESPACE | tail -n 20"

kubectl logs  -l app=xray -n $JFROG_PLATFORM_NAMESPACE --all-containers -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f -l app=xray -n $JFROG_PLATFORM_NAMESPACE --all-containers --max-log-requests=8 -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $JFROG_PLATFORM_NAMESPACE
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- bash
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- cat /opt/jfrog/xray/var/etc/security/master.key
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- cat /opt/jfrog/xray/var/etc/system.yaml
##kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- rm -rf  /opt/jfrog/xray/var/etc/system.yaml

kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- echo $JF_SHARED_RABBITMQ_VHOST

kubectl logs -f ps-jfrog-platform-release-xray-pre-upgrade-hook-5fqhr -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-1 -c xray-server -n $JFROG_PLATFORM_NAMESPACE

kubectl logs -f ps-jfrog-platform-release-rabbitmq-0 -n $JFROG_PLATFORM_NAMESPACE
kubectl exec -it ps-jfrog-platform-release-rabbitmq-0 -n $JFROG_PLATFORM_NAMESPACE -- bash

kubectl delete pod ps-jfrog-platform-release-xray-0 ps-jfrog-platform-release-xray-1 \
ps-jfrog-platform-release-xray-pre-upgrade-hook-5fqhr -n $JFROG_PLATFORM_NAMESPACE

```
**Verify rabbitMQ and Xray:**

SSH and verify rabbitMQ is up and functional:
```text
$kubectl logs $JFROG_PLATFORM_NAME-rabbitmq-0 -n $JFROG_PLATFORM_NAMESPACE

kubectl exec -it $JFROG_PLATFORM_NAME-rabbitmq-0  -n $JFROG_PLATFORM_NAMESPACE -- bash
find / -name rabbitmq.conf
cat /opt/bitnami/rabbitmq/etc/rabbitmq/rabbitmq.conf

rabbitmqctl status
rabbitmqctl cluster_status
rabbitmqctl list_queues
```

Note: the default admin password for rabbitMQ is password but we did override it with "$MY_RABBITMQ_ADMIN_USER_PASSWORD" as mentioned above:

Run below curl commands to check if the "$MY_RABBITMQ_ADMIN_USER_PASSWORD" works:
```
kubectl exec -it $JFROG_PLATFORM_NAME-rabbitmq-0  -n $JFROG_PLATFORM_NAMESPACE -- curl --user "admin:$MY_RABBITMQ_ADMIN_USER_PASSWORD" http://localhost:15672/api/vhosts

kubectl exec -it $JFROG_PLATFORM_NAME-rabbitmq-0  -n $JFROG_PLATFORM_NAMESPACE -- curl  --user "admin:$MY_RABBITMQ_ADMIN_USER_PASSWORD" "http://$JFROG_PLATFORM_NAME-rabbitmq:15672/api/vhosts"
```

SSH and verify the Xray server is up and functional
```text
kubectl exec -it $JFROG_PLATFORM_NAME-xray-0 -n $JFROG_PLATFORM_NAMESPACE -c xray-server -- bash

cd /opt/jfrog/xray/var/etc
cat /opt/jfrog/xray/var/etc/system.yaml


cd /opt/jfrog/xray/var/log
cat /opt/jfrog/xray/var/log/xray-server-service.log
tail -F /opt/jfrog/xray/var/log/xray-server-service.log
```

---

### 7. Perform Xray DBSync
If xray is up and is now integrated with Artifactory , you can perform the Xray DBSync.

---
### 8. Deploying JAS

**Enable JAS**

Enable JAS  with the helm values override in  [9_enable_JAS.yaml](values/For_PROD_Setup/9_enable_JAS.yaml)

```
helm  upgrade --install $JFROG_PLATFORM_NAME \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f platform-small.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
-f 9_enable_JAS.yaml \
--namespace $JFROG_PLATFORM_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```


**Note:**  
As explained in [JFrog Advanced Security Readiness Checking](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-advanced-security-readiness-checking), since we are enabling the **Health Check Cron Job** through the following configuration in [`values/For_PROD_Setup/9_enable_JAS.yaml`](values/For_PROD_Setup/9_enable_JAS.yaml):

```yaml
xray:
  ## JAS periodic health check
  jas:
    healthcheck:
      enabled: true
```

You should see the JAS feature enabled in the platform UI under **Administration > Xray Settings**, specifically the checkbox for  
**"Enable JAS health check (takes effect only after Xray restart)"**.

**Additional Note:**  
JAS scans are executed as Kubernetes jobs. You will see pods created by these jobs **only when** you initiate a **"Scan for Contextual Analysis"**.  
At that time, you can run the following command to watch the pods related to the job:

```bash
watch kubectl get pods -n $JFROG_PLATFORM_NAMESPACE
```

As per [JFrog Advanced Security Readiness Checking](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-advanced-security-readiness-checking) :
Call the following URL: https://your.domain/ui/api/v1/jfconnect/entitlements and find the JFrog Advanced Security entitlements, search for 'secrets_detection' in the returned response.
```
export SERVICE_HOSTNAME=$(kubectl get svc --namespace ps-jfrog-platform ps-jfrog-platform-release-artifactory-nginx --template "{{ (index .status.loadBalancer.ingress 0).ip }}")
```

Generate an admin access token and then do:
```
export MYTOKEN="YOUR_ADMIN_ACCESS_TOKEN"
```

Then run
```
curl -X GET -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "Accept: */*" \
-H "Cookie: __Host-REFRESHTOKEN=*;__Host-ACCESSTOKEN=$MYTOKEN" \
"http://$SERVICE_HOSTNAME/ui/api/v1/jfconnect/entitlements" | jq '.entitlements[] | select(.name == "secrets_detection")'


or 

curl -X GET -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "Accept: */*" \
-H "Cookie: REFRESHTOKEN=*;ACCESSTOKEN=$MYTOKEN" \
"http://$SERVICE_HOSTNAME/ui/api/v1/jfconnect/entitlements" | jq '.entitlements[] | select(.name == "secrets_detection")'

```
You will get a list of entitlements:
```
{"entitlements":[{"name":"access_federation","value":1,"expiryDate":"2025-09-25T00:00:00.000Z","productExpiryDate":"2025-09-25T00:00:00.000Z","isTrial":true,"customerId":"","blockingQuantity":1,"dependentOnAction":""},
{"name":"secrets_detection","value":1,"expiryDate":"2025-09-25T00:00:00.000Z","productExpiryDate":"2025-09-25T00:00:00.000Z","isTrial":true,"customerId":"","blockingQuantity":1,"dependentOnAction":"xray_advanced_actions"}
],"enforcementOn":{"global":false,"all":false,"artifactory":false,"distribution":false,"mc":false,"insight":false,"catalog":false,"xray":true,"runtime":true,"event":false,"metadata":false,"access":true,"client":false,"client-vue3":false,"frontend":false,"analysis":false,"persist":false,"indexer":false,"policy_enforcer":false,"insight_scheduler":false,"elastic_search":false,"insight_executor":false,"insight_server2":false,"replicator":false,"jfconnect":false,"jflink":false,"router":false,"integration":false,"tracker":false,"pipelines":false,"observability":false,"worker":false,"xsc":false,"rtfs":false,"lifecycle":false,"evidence":false,"enrichment":false,"application":false,"onemodel":false,"topology":false},"isJfConnectEnabled":true}
```
In this check for 
```
{
  "name": "secrets_detection",
  "value": 1,
  "expiryDate": "2025-09-25T00:00:00.000Z",
  "productExpiryDate": "2025-09-25T00:00:00.000Z",
  "isTrial": true,
  "customerId": "",
  "blockingQuantity": 1,
  "dependentOnAction": "xray_advanced_actions"
}
```

Check JAS is enabled in xray service logs:
```
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $JFROG_PLATFORM_NAMESPACE | grep -i jas
```
Output:
```
2025-04-21T05:20:36.552Z [jfxr ] [INFO ] [323448ee7ba33858] [job_manager:630               ] [MainServer                      ] Scheduling JAS Health Check
2025-04-21T05:20:36.559Z [jfxr ] [INFO ] [323448ee7ba33858] [job_manager:658               ] [MainServer                      ] JAS Health Check is enabled ...
```

---

### 9. Deploying JFrog Catalog
Ref: [Install JFrog Catalog with Helm](https://jfrog.com/help/r/jfrog-installation-setup-documentation/install-jfrog-catalog-with-helm-and-openshift)


#### a) Catalog Database secret


```text
kubectl delete secret generic catalog-database-creds -n $JFROG_PLATFORM_NAMESPACE
kubectl create secret generic catalog-database-creds \
--from-literal=db-user=$CATALOG_DATABASE_USER \
--from-literal=db-password=$CATALOG_DATABASE_PASSWORD \
--from-literal=db-url=postgres://$DB_SERVER:5432/$CATALOG_DB\?sslmode=disable -n $JFROG_PLATFORM_NAMESPACE
```

#### b) enable Catalog in the helm values.yaml
We will use [values/For_PROD_Setup/11_enable_catalog.yaml](values/For_PROD_Setup/11_enable_catalog.yaml)


#### c) helm upgrade to install / enable Catalog:

Here is the helm command :
```
helm  upgrade --install $JFROG_PLATFORM_NAME \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f platform-small.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
-f 9_enable_JAS.yaml \
-f 11_enable_catalog.yaml \
--namespace $JFROG_PLATFORM_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```


Then you should  see a catalog pod running:
```
kubectl  get pod --namespace $JFROG_PLATFORM_NAMESPACE

NAME                                                           READY   STATUS    RESTARTS        AGE
cloudsql-proxy-67cfcf5c75-cm2wq                                1/1     Running   1 (14m ago)     16m
ps-jfrog-platform-release-artifactory-0                        10/10   Running   0               16m
ps-jfrog-platform-release-artifactory-nginx-697c454558-qlnkd   1/1     Running   1 (14m ago)     16m
ps-jfrog-platform-release-catalog-649b8fd567-hwd9v             2/2     Running   3 (7m59s ago)   14m
ps-jfrog-platform-release-rabbitmq-0                           1/1     Running   0               16m
ps-jfrog-platform-release-xray-0                               7/7     Running   0               6m1s
```

Check the xray-server-service.log :
```
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $JFROG_PLATFORM_NAMESPACE | grep -i  "jas\|curation"
```
You should see:

```
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [job_manager:630               ] [MainServer                      ] Scheduling JAS Health Check
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [task:86                       ] [MainServer                      ] curationAnalytics task is scheduled
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [task:86                       ] [MainServer                      ] curationAuditPackagesRetention task is scheduled
```

### Catalog startup troubleshooting:
```
kubectl describe pod ps-jfrog-platform-release-catalog -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog-869975b4d7-xjgl9  -n $JFROG_PLATFORM_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog-5bd7965879-qrlgl -c router -n $JFROG_PLATFORM_NAMESPACE



kubectl get pod ps-jfrog-platform-release-catalog-869975b4d7-xjgl9 -n $JFROG_PLATFORM_NAMESPACE -o jsonpath='{.spec.containers[*].name}' 
output : catalog router

kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c access  -n $JFROG_PLATFORM_NAMESPACE

kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- bash
kubectl exec -it ps-jfrog-platform-release-catalog-869975b4d7-v4d52 -c router -n $JFROG_PLATFORM_NAMESPACE -- cat /opt/jfrog/catalog/var/etc/security/join.key
```


```
kubectl exec -it ps-jfrog-platform-release-catalog-869975b4d7-xjgl9 -c catalog  -- cat /opt/jfrog/catalog/var/etc/system.yaml
```
Output:

```
catalog:
    central:
        url: https://jfscatalogcentral.jfrog.io
    logging:
        application:
            level: debug
    mode: singleTenant
configVersion: 1
shared:
    database:
        driver: pgx
        type: postgresql
    logging:
        application:
            enabled: true
            level: info
``` 
#### d) Render the "Package Catalog" menu in UI
Access the "Package Catalog" menu in the UI directly by navigating to http://<jfrogUrl>:<port>/ui/catalog/packages/overview, without needing to use an incognito browser window.


#### e) Check the Catalog health 

Catalog app_health API - 

GET <base-url>/catalog/api/v1/system/app_health

```
export SERVICE_HOSTNAME=$(kubectl get svc --namespace ps-jfrog-platform ps-jfrog-platform-release-artifactory-nginx --template "{{ (index .status.loadBalancer.ingress 0).ip }}")
```

When I access "http://$SERVICE_HOSTNAME/xray/ui/curation/internal/health" why do I get "Catalog is not accessible!" ?
Output:
```
{"JFConnect":"OK","Entitlements":"OK","Catalog":"Catalog is not accessible!","RTJFConnectEnablement":"OK"}
```

Call the following URL: https://your.domain/ui/api/v1/jfconnect/entitlements and find the JFrog Catalog entitlements, search for 'curation' in the returned response.
```
curl -X GET -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "Accept: */*" \
-H "Cookie: __Host-REFRESHTOKEN=*;__Host-ACCESSTOKEN=$MYTOKEN" \
"http://$SERVICE_HOSTNAME/ui/api/v1/jfconnect/entitlements" | jq '.entitlements[] | select(.name == "curation")'


or 

curl -X GET -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "Accept: */*" \
-H "Cookie: REFRESHTOKEN=*;ACCESSTOKEN=$MYTOKEN" \
"http://$SERVICE_HOSTNAME/ui/api/v1/jfconnect/entitlements" | jq '.entitlements[] | select(.name == "curation")'
```
Output:
```
{
  "name": "curation",
  "value": 1,
  "expiryDate": "2025-09-25T00:00:00.000Z",
  "productExpiryDate": "2025-09-25T00:00:00.000Z",
  "isTrial": true,
  "customerId": "",
  "blockingQuantity": 1,
  "dependentOnAction": ""
}
```

#### Ref Links:
- https://github.com/ps-jfrog/jfrog-helm-values
- https://charts.jfrog.io/
- [Helm Charts for Advanced Users](https://jfrog.com/help/r/jfrog-installation-setup-documentation/helm-charts-for-advanced-users)

---


### FAQs:
How to set the artifactory's artifactory.artifactory.replicaCount to 1 ?

To edit the replicaCount of a StatefulSet in Kubernetes there are multiple options:
**Option1:** 
You can directly  update its manifest file and then apply the 
changes using `kubectl apply`.

Here's how you can do it:

1. Get the current StatefulSet manifest:

   Run the following command to get the YAML representation of the StatefulSet:

   ```sh
   kubectl get statefulset jfrog-platform-artifactory -o yaml > statefulset.yaml
   ```

2. Edit the manifest:

   Open the `statefulset.yaml` file in a text editor of your choice. Find the `spec.replicas` field in the YAML and change the value from `3` to `1`. It should look something like this:

   ```yaml
   apiVersion: apps/v1
   kind: StatefulSet
   metadata:
     name: jfrog-platform-artifactory
   spec:
     replicas: 1
     # ... other fields ...
   ```

3. Apply the changes:

   Apply the edited manifest back to the cluster using `kubectl apply`:

   ```sh
   kubectl apply -f statefulset.yaml
   ```

This will update the StatefulSet with the new replica count. The StatefulSet controller will handle the scaling process, ensuring that the desired state matches the updated manifest.

Option2:
Yes, you can definitely reduce the replicas of a StatefulSet managed by Helm. Helm is a package manager for Kubernetes that allows you to define, install, and manage applications as Helm charts.

Here's how you can modify the replicaCount of a StatefulSet deployed via Helm:

1. **Get Values from Existing Release (Optional)**:

   If you want to change a value in a Helm chart, it's often good practice to copy the relevant values from the release. Run the following command to get the values used in your existing release:

   ```sh
   helm get values <release-name> > my-values.yaml
   ```

   Replace `<release-name>` with the name of your Helm release. This will create a `my-values.yaml` file with the values that were used during the deployment.

2. **Edit the Values File**:

   Open the `my-values.yaml` file in a text editor. Look for the section related to the StatefulSet you want to modify. There should be a field like `replicaCount`, or a field specifying the replica count for that StatefulSet. Change the value from `3` to `1`.

   ```yaml
   statefulset:
     replicaCount: 1
     # ... other values ...
   ```

3. **Update the Release**:

   Run the following command to upgrade the Helm release with the modified values:

   ```sh
   helm upgrade <release-name> <chart-name> -f my-values.yaml
   ```

   Replace `<release-name>` with the name of your Helm release and `<chart-name>` with the name of the Helm chart. The `-f my-values.yaml` flag tells Helm to use the modified values from the file.

   For example:

   ```sh
   helm upgrade my-release my-chart -f my-values.yaml
   ```

Helm will then perform an upgrade on the existing release, applying the changes you specified in the values file. This will update the StatefulSet's replica count as per your modification.

---
### How to change the logback.xml in an artifactory pod ?
1. First reduce the replica of the artifactory statefulset to 1 as mentioned in previous FAQ.
2. backup the /opt/jfrog/artifactory/var/etc/artifactory/logback.xml within the pod itself.
3. Then copy the logback.xml to  the host VM:
kubectl cp my-namespace/my-pod:/app/data/file.txt ~/Downloads/
Example:
kubectl cp jfrog-platform-artifactory-0:/opt/jfrog/artifactory/var/etc/artifactory/logback.xml ~/test/logback.xml
3. Make the necessary logback.xml  debug changes.
4. Copy back the modified logback.xml back to the pod
kubectl cp ~/test/logback.xml jfrog-platform-artifactory-0:/opt/jfrog/artifactory/var/etc/artifactory/logback.xml 

---

### How to export the helm chart for a specific Artifactory version ?

To download a specific version of a Helm chart (e.g., `107.84.14`) to a `.tgz` file for use in an air-gapped environment, you can use the `helm pull` command with the specific version. Here's how you can do it:

1. **Add the JFrog Helm Repository**:
   - Ensure you have added the JFrog Helm repository:
     ```bash
     helm repo add jfrog https://charts.jfrog.io
     ```

2. **Update the Helm Repository**:
   - Update the repository to get the latest information:
     ```bash
     helm repo update
     ```

3. **Download the Specific Version of the Helm Chart**:
   - Use the `helm pull` command to download the specific chart version. For example, to download version `107.84.14` of the `artifactory` chart:
     ```bash
     helm pull jfrog/jfrog-platform --version 107.84.14
     helm pull jfrog/artifactory --version 107.84.14
     ```
This will create a `artifactory-107.84.14.tgz` file in the current folder.
4. **Transfer the `.tgz` File to the Air-Gapped Environment**:
   - The `helm pull` command will create a `.tgz` file for the Helm chart. Transfer this file to your air-gapped environment using a USB drive or other suitable methods.

5. **Install the Helm Chart in the Air-Gapped Environment**:
   - Copy the `.tgz` file to a location accessible by your air-gapped environment.
   - Run the following command to install the Helm chart from the file:
     ```bash
     helm install <release-name> <path-to-chart-file>.tgz
     ```
   - Replace `<release-name>` with a name for your Helm release and `<path-to-chart-file>` with the path to the `.tgz` file.

### Example Commands
Here's the full set of commands you would run on a machine with internet access:

```bash
helm repo add jfrog https://charts.jfrog.io
helm repo update
helm pull jfrog/artifactory --version 107.84.14
```

This will produce a file named `artifactory-107.84.14.tgz`.

### Transferring and Installing in Air-Gapped Environment

1. **Transfer the `artifactory-107.84.14.tgz` File**:
   - Copy the `artifactory-107.84.14.tgz` file to a USB drive or other transfer medium.

2. **On the Air-Gapped Machine**:
   ```bash
   helm install my-artifactory ./artifactory-107.84.14.tgz
   ```

By following these steps, you should be able to download and install the specified version of the Helm chart in your air-gapped environment. 
