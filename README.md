
## Step-by-Step install of Artifactory, Xray, JAS, Catalog, Curation

Instead of installing Artifactory, Xray and JAS all in one shot (in AWS EKS or in GKE ), it is recommended to :
```text
a) Create  the secrets ( for all user passwords, binarystore configuration , system.yaml etc) 
b) first install  Artifactory , login to it and set the Artifactory base url
c) install Xray and verify it successfully connects to the Artifactory instance
d) Do Xray DB Sync
e) Enable JAS
f) Enable Package Catalog + Curation.
```

The steps to do the above using the [jfrog/platform](https://github.com/jfrog/charts/tree/master/stable/jfrog-platform) chart by using a nested values.yaml from the below child charts is explained in this Readme. 
- [jfrog/artifactory](https://github.com/jfrog/charts/tree/master/stable/artifactory)
- [jfrog/xray](https://github.com/jfrog/charts/tree/master/stable/xray) for Jfrog Xray, JAS
- [catalog](https://github.com/jfrog/charts/tree/master/stable/catalog)

It also shows :
- how to use the [envsubst](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) command 
  to get the values to create the  secrets from environmental variables. 
- the step-by-step approach to improvise the values.yaml to generate the final values.yaml needed for the helm install

Note: I Initially used  [yaml-merger-py](https://github.com/Aref-Riant/yaml-merger-py) , [../../scripts/merge_yaml_with_comments.py](../../scripts/merge_yaml_with_comments.py) but these are not necessary now.
We still need the [../../scripts/nest_yaml_with_comments.py](../../scripts/nest_yaml_with_comments.py)

  
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
                    "oidc.eks.eu-west-3.amazonaws.com/id/123456AC6C4D61425521234561E34:sub": "system:serviceaccount:MY_NAMESPACE:MY_HELM_RELEASE-artifactory",
                    "oidc.eks.eu-west-3.amazonaws.com/id/123456AC6C4D61425521234561E34:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
```
Please note that the service account's name in the statement must correspond with the service account that will be 
established for the Artifactory pods. By default, this service account takes the format of {MY_NAMESPACE}:{MY_HELM_RELEASE}-artifactory in its naming.

For example in your K8s cluster if  you have:
```text
export MY_NAMESPACE=ps-jfrog-platform
export MY_HELM_RELEASE=ps-jfrog-platform-release
```

Then the service account takes the format:
`"system:serviceaccount:ps-jfrog-platform:ps-jfrog-platform-release-artifactory"`

### Application Load Balancer as Ingress gateway setup
You can refer to either of these resources for guidance:
- The documentation available at: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- Alternatively, you can also explore: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/

Main steps are highlighted below

1. Create IAM policy for the load balancer .  This step is required only if the policy doesn’t already exists.
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

Please download the  python script to merge values.yaml files with best effort to preserve comments, formatting,
and order of items from https://github.com/Aref-Riant/yaml-merger-py

Requirements:
```text
pip install ruamel.yaml
pip install mergedeep
```

Usage:
```
python yaml-merger.py file1.yaml file2.yaml > mergedfile.yaml
```
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

---

1. Download this git repo and run:
```text
cd values/For_PROD_Setup
```

2. Set the following Environmental variables based on your Deployment K8s environment where you will install the 
JFrog Platform.

**Note:** the CLOUD_PROVIDER can be gcp or aws ( JFrog Helm charts support Azure as well but this readme was created 
only based on gcp or aws  )

### Environment variables:
```text
export CLOUD_PROVIDER=gcp
export MY_NAMESPACE=ps-jfrog-platform
export MY_HELM_RELEASE=ps-jfrog-platform-release

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

export RT_VERSION=7.104.15
export JFROG_PLATFORM_CHART_VERSION=11.0.6
export XRAY_VERSION=3.111.24
```
---

### 3. Prepare the K8s environment:

**If you are starting with a clean k8s environment:**

Create the Namespace:
```
kubectl create ns  $MY_NAMESPACE
```
Optional: I used the steps in [Creating only "CloudSql proxy" and secrets for "binarystore.xml"](https://github.com/sureshvenkatesan/jf-gcp-env/tree/feature/jf_with_cloudsql?tab=readme-ov-file#creating-only-cloudsql-proxy-and-secrets-for-binarystorexml-) which also creates the Namespace via terraform.

**Or**


**If you are not starting with a clean k8s environment:**

Use below commands if you need to run the Helm release multiple times without starting from a clean Kubernetes environment. 

They are helpful for iterative testing or redeployments.
```text
helm uninstall $MY_HELM_RELEASE -n $MY_NAMESPACE

or to rollback a revision:

helm rollback $MY_HELM_RELEASE REVISION_NUMBER -n $MY_NAMESPACE
```

To get the release name of a Helm chart, you can use the following command:
```text
helm list -n  $MY_NAMESPACE

NAME                     	NAMESPACE        	REVISION	UPDATED                             	STATUS  	CHART                 	APP VERSION
ps-jfrog-platform-release	ps-jfrog-platform	3       	2023-07-10 12:33:19.393492 -0700 PDT	deployed	jfrog-platform-10.13.1	7.59.9
```

Replace <namespace> with the actual namespace where the Helm release is deployed. 

If you don't specify the --namespace flag, it will list releases across all namespaces.


Delete PVCs as needed:
```text
kubectl delete pvc artifactory-volume-$MY_HELM_RELEASE-artifactory-0 -n $MY_NAMESPACE
kubectl delete pvc data-$MY_HELM_RELEASE-rabbitmq-0 -n $MY_NAMESPACE
kubectl delete pvc data-volume-$MY_HELM_RELEASE-xray-0 -n $MY_NAMESPACE
kubectl delete pvc data-volume-$MY_HELM_RELEASE-xray-1 -n $MY_NAMESPACE
etc
```

Delete Namespace only if needed as this will delete all the secrets as well:
```text
kubectl delete ns  $MY_NAMESPACE
```
Optional: I used the steps in [Creating only "CloudSql proxy" and secrets for "binarystore.xml"](https://github.com/sureshvenkatesan/jf-gcp-env/tree/feature/jf_with_cloudsql?tab=readme-ov-file#creating-only-cloudsql-proxy-and-secrets-for-binarystorexml-) which also creates the Namespace via terraform.


---

### 4. Create the secrets

**Master and Join Keys:**
```text
kubectl delete secret rt-masterkey-secret  -n $MY_NAMESPACE
kubectl delete secret joinkey-secret   -n $MY_NAMESPACE

kubectl create secret generic rt-masterkey-secret --from-literal=master-key=${RT_MASTER_KEY} -n $MY_NAMESPACE
# if using xray:
kubectl delete secret xray-masterkey-secret  -n $MY_NAMESPACE
kubectl create secret generic xray-masterkey-secret --from-literal=master-key=${XRAY_MASTER_KEY} -n $MY_NAMESPACE
# if using catalog:
kubectl delete secret catalog-masterkey-secret  -n $MY_NAMESPACE
kubectl create secret generic catalog-masterkey-secret --from-literal=master-key=${CATALOG_MASTER_KEY} -n $MY_NAMESPACE

# Same Join key is used by Artifactory, Xay and Catalog pods:
kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $MY_NAMESPACE
```

**License:**

Create a secret for license with the dataKey as "artifactory.lic" for HA or standalone ( if you want you can name the 
dataKey as artifactory.cluster.license for HA but not necessary) :
```text
kubectl delete secret  artifactory-license  -n $MY_NAMESPACE

kubectl create secret generic artifactory-license --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE
```
Verify the license secret using:
```
kubectl get secret artifactory-license -o yaml -n $MY_NAMESPACE
or
kubectl get secret artifactory-license -o json -n $MY_NAMESPACE | jq -r '.data."artifactory.lic"' | base64 --decode

```


<!-- Note: if you create it as the following then the dataKey will be art.lic ( i.e same as the name of the file)
```text
kubectl create secret generic artifactory-license \  
--from-file=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE 
``` 
-->


---

### 5. step-by-step approach to improvise the values.yaml  we will finally use:

Ref: https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-small.yaml

File mentioned below are in [For_PROD_Setup](values/For_PROD_Setup)

#### a) Custom Configuration
Start with the 1_artifactory-small.yaml for **TEST** environment or 1_artifactory-large.yaml for **PROD** 
environment

- Created `1_artifactory-small.yaml` by copying the original [artifactory-small.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-small.yaml)
- Added the following JVM parameter to support graceful shutdown behavior:

  ```yaml
  -Dartifactory.graceful.shutdown.max.request.duration.millis=30000
  ```
This allows Artifactory to wait up to 30 seconds to complete in-flight requests during shutdown.

Note: `/values/For_PROD_Setup/tmp/` already in .gitignore

```text
python ../../scripts/nest_yaml_with_comments.py 1_artifactory-small.yaml \
 artifactory -o 1_artifactory-small-nested.yaml 

python ../../scripts/merge_yaml_with_comments.py 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml 1_artifactory-small-nested.yaml -o tmp2/1_mergedfile.yml

```
<!-- 
```
python yaml-merger.py 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml 1_artifactory-small.yaml > tmp/1_mergedfile.yaml
or
python yaml-merger.py 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml 1_artifactory-large.yaml > tmp/1_mergedfile.yaml 
```
--> 

---
#### b) Artifactory Database Credentials:
Override using the 2_artifactory_db_passwords.yaml


```text
kubectl delete secret  artifactory-database-creds  -n $MY_NAMESPACE

kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $MY_NAMESPACE
```

```
python ../../scripts/merge_yaml_with_comments.py tmp2/1_mergedfile.yml 2_artifactory_db_passwords.yaml -o tmp2/2_mergedfile.yaml

```

<!-- 
```
python yaml-merger.py tmp/1_mergedfile.yaml 2_artifactory_db_passwords.yaml > tmp/2_mergedfile.yaml 
```
-->

---

#### c) The artifactory default admin user secret:
Override using 3_artifactory_admin_user.yaml 

Review KB [ARTIFACTORY: How To Unlock A User(s) Who Is Locked Out Of Artifactory and Recover Admin Account](https://jfrog.com/help/r/artifactory-how-to-unlock-a-user-s-who-is-locked-out-of-artifactory-and-recover-admin-account)

```text
kubectl delete secret  art-creds  -n $MY_NAMESPACE

kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=Test@123' -n $MY_NAMESPACE
```

```
python ../../scripts/merge_yaml_with_comments.py tmp2/2_mergedfile.yaml 3_artifactory_admin_user.yaml -o tmp2/3_mergedfile.yaml

```
<!-- python yaml-merger.py tmp/2_mergedfile.yaml 3_artifactory_admin_user.yaml > tmp/3_mergedfile.yaml -->

---

#### d) Override the binaryStore

For AWS use [S3 Direct Upload Template (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended) :
```
kubectl apply -f 4_custom-binarystore-s3-direct-use_instance-creds.yaml -n $MY_NAMESPACE
```
or

For GCP use [google-storage-v2-direct template configuration (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-v2-direct-template-configuration-recommended) mentioned in [Google Storage Binary Provider Native Client Template](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-binary-provider-native-client-template) :

Note: I created the secrets `artifactory-gcp-creds` and `custom-binarystore`  in [Creating only "CloudSql proxy" and secrets for "binarystore.xml"](https://github.com/sureshvenkatesan/jf-gcp-env/tree/feature/jf_with_cloudsql?tab=readme-ov-file#creating-only-cloudsql-proxy-and-secrets-for-binarystorexml-)  as mentioned above , instead of the following 

```
kubectl delete secret  artifactory-gcp-creds -n $MY_NAMESPACE

kubectl create secret generic artifactory-gcp-creds --from-file=/Users/sureshv/.gcp/support-team_gco_project_ServiceAccount.json \
-n $MY_NAMESPACE

envsubst < binarystore_config/custom-binarystore-gcp.tmpl > binarystore_config/custom-binarystore.yaml

kubectl apply -f binarystore_config/custom-binarystore.yaml -n $MY_NAMESPACE
```
---

#### e) Tuning as per KB
The tuning configuration in KB [How do I tune Artifactory for heavy loads?](https://jfrog.com/help/r/how-do-i-tune-artifactory-for-heavy-loads/how-do-i-tune-artifactory-for-heavy-loads) is already taken care in the 1_artifactory-small.yaml for TEST environment or 1_artifactory-large.yaml for PROD in Step1 , and the default values in https://github.com/jfrog/charts/blob/master/stable/artifactory/values.yaml



<!-- 5.  Override the system.yaml using either 5_artifactory_system_small.yaml for TEST environment or 
    5_artifactory_system_large.yaml for PROD as per KB [How do I tune Artifactory for heavy loads?](https://jfrog.com/help/r/how-do-i-tune-artifactory-for-heavy-loads/how-do-i-tune-artifactory-for-heavy-loads)


 
```
kubectl delete secret artifactory-custom-systemyaml -n $MY_NAMESPACE
kubectl create secret generic artifactory-custom-systemyaml --from-file=system.yaml=./5_artifactory_system_small.yaml \
-n $MY_NAMESPACE
or
kubectl create secret generic artifactory-custom-systemyaml --from-file=system.yaml=./5_artifactory_system_large.yaml \
-n $MY_NAMESPACE
``` -->

#### f) Deploy Artifactory
Deploy Artifactory using helm , then check if artifactory server starts and you can login to the Artifactory UI.
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```
Note: The artifactory pod is a statefulset and the size of the PVC is sepcified in `artifactory.persistence.mountPath` i.e `/var/opt/jfrog/artifactory`  when the  ``artifactory.persistence.enabled` is `true` and defaults to 200Gi   when using the platform chart as in `artifactory.artifactory.persistence.size` ( see https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/values.yaml#L285 ). 
If you use GCP storage and set `artifactory.artifactory.persistence.customBinarystoreXmlSecret` and `artifactory.artifactory.persistence.googleStorage` the `filestore` will not be seen under `/var/opt/jfrog/artifactory/data/artifactory`  i.,e PVC size does not include the googleStorage bucket size. The googleStorage usage can only be see from "Administration > Monitoring > Storage" in the Artitfactory UI.


Similarly the Xray pod statefulset PVC size is specified in `xray.common.persisitence.size` to 200Gi which I am overriding in [values/For_PROD_Setup/6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml) to 100Gi.
But when using JAS it is recommended that this be increased to minimum of 400Gi  in one of the earlier T-shirt sizing in https://github.com/jfrog/charts/tree/master/stable/xray/sizing or "300 to 500 GB" mentioned in below references.

**Ref:**
- [JFrog Advanced Security Prerequisites](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-advanced-security-prerequisites)
- [JFrog Platform: Reference Architecture](https://jfrog.com/help/r/jfrog-platform-reference-architecture/jfrog-platform-reference-architecture)
- [Artifactory Self-Hosted Performance Benchmark Report - PostgreSQL](https://jfrog.com/help/r/artifactory-artifactory-self-hosted-performance-benchmark-report-may-2024/artifactory-self-hosted-performance-benchmark-report-postgresql)



#### g) Troubleshooting Artifactory Startup:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c artifactory -n $MY_NAMESPACE
kubectl logs  -l app=artifactory -n $MY_NAMESPACE --all-containers
kubectl logs -f -l app=artifactory -n $MY_NAMESPACE --all-containers --max-log-requests=15
kubectl delete pod ps-jfrog-platform-release-artifactory-0  -n $MY_NAMESPACE
kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $MY_NAMESPACE

watch -n 10 "kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $MY_NAMESPACE | tail -n 20"

kubectl get pod ps-jfrog-platform-release-artifactory-0 -n $MY_NAMESPACE -o jsonpath='{.spec.containers[*].name}'
Output:
router frontend metadata onemodel event jfconnect access topology observability artifactory

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory  -- cat /opt/jfrog/artifactory/var/etc/system.yaml
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory  -- cat /opt/jfrog/artifactory/var/etc/security/master.key

```
Set the base url the output you see from below in the `http://$SERVICE_HOSTNAME/ui/admin/configuration/general`:
```
export SERVICE_HOSTNAME=$(kubectl get svc --namespace ps-jfrog-platform ps-jfrog-platform-release-artifactory-nginx --template "{{ (index .status.loadBalancer.ingress 0).ip }}")
echo http://$SERVICE_HOSTNAME
```
For example I set it to: http://100.231.185.7 . I also set the Server Name to "sureshvps".


Next Upload a file to `example-repo-local`  repository and see if it is successful , by tailing the artifactory-service.log using:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c artifactory
```

If it fails check the binaryStore.xml using:
```
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- ls -al  /opt/jfrog/artifactory/var/etc/artifactory

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/artifactory/var/etc/artifactory/binarystore.xml
```

Since I used GCP I also verifioed if I have the correct GCP service account using:
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
kubectl describe pod ps-jfrog-platform-release-artifactory-0 -n $MY_NAMESPACE
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
Then redo the file uplaod test to `example-repo-local`  repository and see if it is successful .

---
### 7. Deploying Xray
#### a) Xray Database secret


```text
kubectl delete secret generic xray-database-creds -n $MY_NAMESPACE
kubectl create secret generic xray-database-creds \
--from-literal=db-user=$XRAY_DATABASE_USER \
--from-literal=db-password=$XRAY_DATABASE_PASSWORD \
--from-literal=db-url=postgres://$DB_SERVER:5432/$XRAY_DB\?sslmode=disable -n $MY_NAMESPACE
```

Verify using jq:
If "jq --version" >=1.6  where jq  @base64d filter is avaiable use :
```
kubectl get secret xray-database-creds  -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'
```
otherwise use:
```
bash decode_secret.sh <secret-to-decrypt>  <namespace>
```
#### b) Secret to override the xray system yaml
**Note:** Secret to override the xray system.yaml is needed for Xray versions below v3.118 (XRAY-109797)  to set the
share.rabbitMq.password via the `xray-custom-systemyaml`. For Xray versions >=v3.118 you an skip this step.
```
envsubst < 8_xray_system_yaml.tmpl > tmp2/8_xray_system_yaml.yaml

kubectl delete  secret xray-custom-systemyaml -n $MY_NAMESPACE
kubectl create secret generic xray-custom-systemyaml --from-file=system.yaml=tmp2/8_xray_system_yaml.yaml \
-n $MY_NAMESPACE
```
 
#### c) Secret for Rabbitmq admin password:

The rabbitmq user name as per https://github.com/jfrog/charts/blob/master/stable/xray/values.yaml#L514 is hardcoded
to "guest" .It can be set to "admin" only as value and not as secrert as per  
https://github.com/bitnami/charts/blob/main/bitnami/rabbitmq/values.yaml#L155

Also to pass the rabbitmq password as secret use the key as `rabbitmq-password` 
```
kubectl create secret generic rabbitmq-admin-creds \
--from-literal=rabbitmq-password=$MY_RABBITMQ_ADMIN_USER_PASSWORD -n $MY_NAMESPACE 
```
<!-- --from-literal=url=amqp://$MY_HELM_RELEASE-rabbitmq:5672  -->

This is used in [6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml)

#### d) Nest the xray sizing yaml file from Xray chart:
Take the  https://github.com/jfrog/charts/blob/master/stable/xray/sizing/xray-xsmall.yaml 
( or the T-shirt size yaml you want for Xray) under "xray" to use it with the jfrog/platform chart.
```
python ../../scripts/nest_yaml_with_comments.py 6_xray-xsmall.yaml \
 xray -o 6_xray-xsmall-nested.yaml 
```

<!-- ```
python yaml-merger.py tmp/3_mergedfile.yaml 6_xray_db_passwords_pod_size-values-small.yaml > tmp/6_mergedfile.yaml
or
python yaml-merger.py tmp/3_mergedfile.yaml 6_xray_db_passwords_pod_size-values-large.yaml > tmp/6_mergedfile.yaml
``` -->
#### e) Deploy Xray as part of your JPD
<!-- Override with the 6_xray_db_passwords_pod_size-values-small.yaml for TEST environment or 
   6_xray_db_passwords_pod_size-values-large.yaml for PROD -->

Here is the helm command for Xray versions below v3.118 (XRAY-109797) :

Note: Have to use "-f 8_override_xray_system_yaml_in_values.yaml"

Note: In [values/For_PROD_Setup/6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml) I have set "JF_SHARED_RABBITMQ_VHOST" to "xray_haq" in `xray.common.extraEnvVars` 
```
envsubst < 6_xray_db_passwords.tmpl > tmp2/6_xray_db_passwords.yaml

helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f tmp2/6_xray_db_passwords.yaml \
-f 8_override_xray_system_yaml_in_values.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```


Here is the helm command for Xray versions >= v3.118 (XRAY-109797 fixed) :
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```


##### Issue1 : Why does it give these warnings?
```
coalesce.go:298: warning: cannot overwrite table with non table for artifactory.postgresql.metrics.extraEnvVars (map[])
coalesce.go:237: warning: skipped value for rabbitmq.initContainers: Not a table.
```
It is coming from Postgresql and Rabbitmq charts and it does not affect the installation.

##### Issue2: How to fix the "<$MY_HELM_RELEASE>-pre-upgrade-check pre-upgrade hooks failed" error ? 
At one time I got this error but did not get this issue in next 2 attempts . SO we can ignore this issue.
After sometime when the helm command exits it may fail with below error:
```
Error: UPGRADE FAILED: pre-upgrade hooks failed: 1 error occurred:
        * job ps-jfrog-platform-release-pre-upgrade-check failed: BackoffLimitExceeded
```

If "<$MY_HELM_RELEASE>-pre-upgrade-check" job has failed with "BackoffLimitExceeded" then delete the job:

```
kubectl get job -n $MY_NAMESPACE
NAME                                          STATUS   COMPLETIONS   DURATION   AGE
ps-jfrog-platform-release-pre-upgrade-check   Failed   0/1           8m33s      8m33s
```

```
kubectl describe job ps-jfrog-platform-release-pre-upgrade-check -n $MY_NAMESPACE
Events:
  Type     Reason                Age    From            Message
  ----     ------                ----   ----            -------
  Normal   SuccessfulCreate      12m    job-controller  Created pod: ps-jfrog-platform-release-pre-upgrade-check-zbngm
  Warning  BackoffLimitExceeded  9m53s  job-controller  Job has reached the specified backoff limit
```
Delete the job and rerun the above "helm  upgrade --install" command and then after a whiel xray should start:
```
kubectl delete job ps-jfrog-platform-release-pre-upgrade-check -n $MY_NAMESPACE
```

You can tail the Artifactory's access log to see that xray connects to Access service:
```
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c access -n $MY_NAMESPACE
```
You should find the log entries similarto the following:
```
2025-04-21T05:19:42.084Z [jfac ] [INFO ] [5045b8a5b8ff60fd] [.j.a.s.s.r.JoinServiceImpl:109] [27.0.0.1-8040-exec-6] - Router join request: using external topology so skipping router NodeId and IP validation
2025-04-21T05:19:42.101Z [jfac ] [INFO ] [5045b8a5b8ff60fd] [.r.ServiceTokenProviderImpl:89] [27.0.0.1-8040-exec-6] - Cluster join: Successfully joined jfrou@01jsbckda0wv9paf2k746h0xp9 with node id ps-jfrog-platform-release-xray-0
```

#### f) Troubleshoot Xray setup:
```
kubectl  delete pod ps-jfrog-platform-release-xray-pre-upgrade-hook-wpk8l ps-jfrog-platform-release-xray-0 --namespace $MY_NAMESPACE
kubectl  delete pod  ps-jfrog-platform-release-xray-0 --namespace $MY_NAMESPACE

kubectl describe pod ps-jfrog-platform-release-xray-0 -n $MY_NAMESPACE
watch -n 15 "kubectl describe pod ps-jfrog-platform-release-xray-0 -n $MY_NAMESPACE | tail -n 20"

kubectl logs  -l app=xray -n $MY_NAMESPACE --all-containers -n $MY_NAMESPACE
kubectl logs -f -l app=xray -n $MY_NAMESPACE --all-containers --max-log-requests=8 -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $MY_NAMESPACE
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- bash
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- cat /opt/jfrog/xray/var/etc/security/master.key
kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- cat /opt/jfrog/xray/var/etc/system.yaml
##kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server  -- rm -rf  /opt/jfrog/xray/var/etc/system.yaml

kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- echo $JF_SHARED_RABBITMQ_VHOST

kubectl logs -f ps-jfrog-platform-release-xray-pre-upgrade-hook-5fqhr -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-1 -c xray-server -n $MY_NAMESPACE

kubectl logs -f ps-jfrog-platform-release-rabbitmq-0 -n $MY_NAMESPACE
kubectl exec -it ps-jfrog-platform-release-rabbitmq-0 -n $MY_NAMESPACE -- bash

kubectl delete pod ps-jfrog-platform-release-xray-0 ps-jfrog-platform-release-xray-1 \
ps-jfrog-platform-release-xray-pre-upgrade-hook-5fqhr -n $MY_NAMESPACE

```
**Verify rabbitMQ and Xray:**

SSH and verify rabbitMQ is up and functional:
```text
$kubectl logs $MY_HELM_RELEASE-rabbitmq-0 -n $MY_NAMESPACE

kubectl exec -it $MY_HELM_RELEASE-rabbitmq-0  -n $MY_NAMESPACE -- bash
find / -name rabbitmq.conf
cat /opt/bitnami/rabbitmq/etc/rabbitmq/rabbitmq.conf

rabbitmqctl status
rabbitmqctl cluster_status
rabbitmqctl list_queues
```

Note: the default admin password for rabbitMQ is password but we did override it with "$MY_RABBITMQ_ADMIN_USER_PASSWORD" as mentioned above:

Run below curl commands to check if the "$MY_RABBITMQ_ADMIN_USER_PASSWORD" works:
```
kubectl exec -it $MY_HELM_RELEASE-rabbitmq-0  -n $MY_NAMESPACE -- curl --user "admin:$MY_RABBITMQ_ADMIN_USER_PASSWORD" http://localhost:15672/api/vhosts

kubectl exec -it $MY_HELM_RELEASE-rabbitmq-0  -n $MY_NAMESPACE -- curl  --user "admin:$MY_RABBITMQ_ADMIN_USER_PASSWORD" "http://$MY_HELM_RELEASE-rabbitmq:15672/api/vhosts"
```

SSH and verify the Xray server is up and functional
```text
kubectl exec -it $MY_HELM_RELEASE-xray-0 -n $MY_NAMESPACE -c xray-server -- bash

cd /opt/jfrog/xray/var/etc
cat /opt/jfrog/xray/var/etc/system.yaml


cd /opt/jfrog/xray/var/log
cat /opt/jfrog/xray/var/log/xray-server-service.log
tail -F /opt/jfrog/xray/var/log/xray-server-service.log
```


If in  the xray pod xray-service.log you see:
```
JF_SHARED_DATABASE_URL              : postgres://cloudsql-proxy:5432/xray?sslmode=disable
JF_SHARED_RABBITMQ_VHOST            : xray
JF_SHARED_NODE_ID                   : ps-jfrog-platform-release-xray-0
JF_SHARED_NODE_IP                   : 10.1.2.22
JF_SHARED_DATABASE_USERNAME         : xray
JF_PRODUCT_DATA_INTERNAL            : /var/opt/jfrog/xray
JF_SYSTEM_YAML                      : /opt/jfrog/xray/var/etc/system.yaml
JF_PRODUCT_HOME                     : /opt/jfrog/xray
JF_SHARED_NODE_NAME                 : ps-jfrog-platform-release-xray-0
...

2025-04-18T02:21:29.895Z [jfxr ] [INFO ] [dee752f0da95b279] [mq_connector:336              ] [MainServer                      ] Connecting to RabbitMQ: amqp://ps-jfrog-platform-release-rabbitmq:5672/xray, retry=34
2025-04-18T02:21:29.900Z [jfxr ] [ERROR] [dee752f0da95b279] [mq_connector:345              ] [MainServer                      ] 

  _____       _     _     _ _   __  __  ____    _                   _                      _ _       _     _
 |  __ \     | |   | |   (_) | |  \/  |/ __ \  (_)                 | |                    (_) |     | |   | |
 | |__) |__ _| |__ | |__  _| |_| \  / | |  | |  _ ___   _ __   ___ | |_    __ ___   ____ _ _| | __ _| |__ | | ___
 |  _  // _  |  _ \|  _ \| | __| |\/| | |  | | | / __| |  _ \ / _ \| __|  / _  \ \ / / _  | | |/ _  |  _ \| |/ _ \
 | | \ \ (_| | |_) | |_) | | |_| |  | | |__| | | \__ \ | | | | (_) | |_  | (_| |\ V / (_| | | | (_| | |_) | |  __/
 |_|  \_\__ _|_ __/|_ __/|_|\__|_|  |_|\___\_\ |_|___/ |_| |_|\___/ \__|  \__ _| \_/ \__ _|_|_|\__ _|_ __/|_|\___|


2025-04-18T02:21:29.900Z [jfxr ] [ERROR] [dee752f0da95b279] [mq_connector:346              ] [MainServer                      ] Error connecting to rabbit message queue check mq settings. Error: Exception (403) Reason: "no access to this vhost"
```

In the rabbimq pod (ps-jfrog-platform-release-rabbitmq-0) you see:
```
2025-04-18 02:18:27.968508+00:00 [error] <0.931.0> Error on AMQP connection <0.931.0> (10.1.0.23:58562 -> 10.1.1.10:5672, user: 'admin', state: opening):
2025-04-18 02:18:27.968508+00:00 [error] <0.931.0> vhost xray not found
2025-04-18 02:18:27.969187+00:00 [info] <0.931.0> closing AMQP connection <0.931.0> (10.1.0.23:58562 -> 10.1.1.10:5672, vhost: 'none', user: 'admin')
```



As per [slack](https://jfrog.slack.com/archives/CD30SKMDG/p1704871916697029?thread_ts=1704783216.516669&cid=CD30SKMDG) and  XRAY-88371:
```
RabbitMQ Xray vhost:
Default "classic": '/'
Platform "classic": 'xray'
New HA QuorumQueues: 'xray_haq'
```
So how to specify that the vhost is either '/' or 'xray_haq' as only these 2 are available in the  `load_definition.json` as per below command ? :
```
kubectl get secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE -o json | jq -r '.data["load_definition.json"]' | base64 -d

```
The output is in [values/For_PROD_Setup/10_optional_load_definition.json](values/For_PROD_Setup/10_optional_load_definition.json) and it uses the password from `rabbitmq-admin-creds` specified in [values/For_PROD_Setup/6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml)

##### Issue3: What is the correct way to deploy xray so that the JF_SHARED_RABBITMQ_VHOST is either '/' or 'xray_haq' to match the `load_definition.json`  ?

**Resolution:**
That is why in [values/For_PROD_Setup/6_xray_db_passwords.yaml](values/For_PROD_Setup/6_xray_db_passwords.yaml) I have set "JF_SHARED_RABBITMQ_VHOST" to `"xray_haq"` in `xray.common.extraEnvVars` to resolve avoid using the Platform's `"classic"`` `'xray'` **vhost** in rabbitMQ.

See the new [values/For_PROD_Setup/10_optional_load_definition.json](values/For_PROD_Setup/10_optional_load_definition.json) that is used as of Apr 20, 2025.

---
#### Vhost Troubleshooting:
If you still want the vhost `xray` as was used in `Platform "classic"`  you can do the following,
but it is nit required:

1. **Check Existing Vhosts**:
   ```sh
   kubectl exec -it ps-jfrog-platform-release-rabbitmq-0 -- rabbitmqctl list_vhosts --namespace $MY_NAMESPACE
   ```

2. **Create Virtual Host**:
   ```sh
   kubectl exec -it ps-jfrog-platform-release-rabbitmq-0 -- rabbitmqctl add_vhost xray --namespace $MY_NAMESPACE
   ```

3. **Set Permissions**:
   ```sh
   kubectl exec -it ps-jfrog-platform-release-rabbitmq-0 -- rabbitmqctl set_permissions -p xray admin ".*" ".*" ".*" --namespace $MY_NAMESPACE
   ```

4. **Restart the pod ps-jfrog-platform-release-xray-0**:
 ```sh
 kubectl delete pod ps-jfrog-platform-release-xray-0 --namespace $MY_NAMESPACE
 ```

---
### 7. Deploying JAS


**Enable JAS**

If xray is up and is now integrated with Artifactory , you can perform the Xray DBSync.
After that enable JAS in the helm values.yaml - we will use [9_enable_JAS.yaml](values/For_PROD_Setup/9_enable_JAS.yaml)


Next do the helm upgrade to install / enable JAS:

Here is the helm command for Xray versions below v3.118 (XRAY-109797) :

```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f tmp2/6_xray_db_passwords.yaml \
-f 8_override_xray_system_yaml_in_values.yaml \
-f 9_enable_JAS.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--set jas.healthcheck.enabled=true \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```

Here is the helm command for Xray versions >= v3.118 (XRAY-109797 fixed) :
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
-f 9_enable_JAS.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--set jas.healthcheck.enabled=true \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```
##### Issue4: Another "pre-upgrade hooks failed" when enabling JAS:
It may fail with:
```
Error: UPGRADE FAILED: pre-upgrade hooks failed: 1 error occurred:
        * timed out waiting for the condition

kubectl get pods -n $MY_NAMESPACE
NAME                                                           READY   STATUS      RESTARTS      AGE
cloudsql-proxy-67cfcf5c75-4qb7k                                1/1     Running     1 (39m ago)   42m
ps-jfrog-platform-release-artifactory-0                        10/10   Running     0             28m
ps-jfrog-platform-release-artifactory-nginx-697c454558-8wf2p   1/1     Running     0             28m
ps-jfrog-platform-release-pre-upgrade-check-26fdg              0/1     Completed   0             10m
ps-jfrog-platform-release-rabbitmq-0                           1/1     Running     0             17m
ps-jfrog-platform-release-xray-0                               7/7     Running     2 (16m ago)   17m
ps-jfrog-platform-release-xray-pre-upgrade-hook-9xzwk          0/1     Pending     0             10m

```

To resolve the xray pod stuck in pending state I had to do the following:
```
kubectl  delete pod ps-jfrog-platform-release-xray-pre-upgrade-hook-9xzwk  ps-jfrog-platform-release-xray-0 --namespace $MY_NAMESPACE
```
Note: Usually there are no logs for these pods:
```
kubectl logs -f ps-jfrog-platform-release-pre-upgrade-check-26fdg -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-xray-pre-upgrade-hook-9xzwk -n $MY_NAMESPACE
```

Note: JAS runs as a k8s job , so you will see the pods from the job only when you "Scan for Contextual Analysis".
At that time when you run the following , it will show the pods that are running for the job.
```text
watch kubectl get pods  -n $MY_NAMESPACE
```

As per [JFrog Advanced Security Readiness Checking](https://jfrog.com/help/r/jfrog-installation-setup-documentation/jfrog-advanced-security-readiness-checking) :
Call the following URL: https://your.domain/ui/api/v1/jfconnect/entitlements and find the JFrog Advanced Security entitlements, search for ‘secrets_detection’ in the returned response.
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

Also you should see following in xray service logs:
```
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $MY_NAMESPACE | grep -i jas
```
Output:
```
2025-04-21T05:20:36.552Z [jfxr ] [INFO ] [323448ee7ba33858] [job_manager:630               ] [MainServer                      ] Scheduling JAS Health Check
2025-04-21T05:20:36.559Z [jfxr ] [INFO ] [323448ee7ba33858] [job_manager:658               ] [MainServer                      ] JAS Health Check is disabled, not setting healthCheckApiSetAndEnabled: <nil>, jasConfig.EnableHealthCheck: true
```

---

### 8. Deploying JFrog Catalog
Ref: [Install JFrog Catalog with Helm](https://jfrog.com/help/r/jfrog-installation-setup-documentation/install-jfrog-catalog-with-helm-and-openshift)
https://jfrog-int.atlassian.net/wiki/spaces/XRAYRnD/pages/885325832/Installing+Catalog+Service+on+a+Dedicated+Kubernetes+Cluster+Using+Helm+Installers

#### a) Catalog Database secret


```text
kubectl delete secret generic catalog-database-creds -n $MY_NAMESPACE
kubectl create secret generic catalog-database-creds \
--from-literal=db-user=$CATALOG_DATABASE_USER \
--from-literal=db-password=$CATALOG_DATABASE_PASSWORD \
--from-literal=db-url=postgres://$DB_SERVER:5432/$CATALOG_DB\?sslmode=disable -n $MY_NAMESPACE
```

#### b) enable Catalog in the helm values.yaml
We will use [11_enable_catalog.yaml](values/For_PROD_Setup/11_enable_catalog.yaml)


#### c) helm upgrade to install / enable Catalog:

Here is the helm command for Xray versions below v3.118 (XRAY-109797) :

```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f tmp2/6_xray_db_passwords.yaml \
-f 8_override_xray_system_yaml_in_values.yaml \
-f 9_enable_JAS.yaml \
-f 11_enable_catalog.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--set jas.healthcheck.enabled=true \
--set catalog.global.masterKeySecretName="catalog-masterkey-secret" \
--set catalog.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```
Here is the helm command for Xray versions >= v3.118 (XRAY-109797 fixed) :
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
-f 6_xray-xsmall-nested.yaml \
-f 6_xray_db_passwords.yaml \
-f 9_enable_JAS.yaml \
-f 11_enable_catalog.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.global.masterKeySecretName="rt-masterkey-secret" \
--set artifactory.global.joinKeySecretName="joinkey-secret" \
--set global.versions.xray="${XRAY_VERSION}" \
--set xray.global.masterKeySecretName="xray-masterkey-secret" \
--set xray.global.joinKeySecretName="joinkey-secret" \
--set jas.healthcheck.enabled=true \
--set catalog.global.masterKeySecretName="catalog-masterkey-secret" \
--set catalog.global.joinKeySecretName="joinkey-secret" \
--version "${JFROG_PLATFORM_CHART_VERSION}" 
```

##### Issue5: Getting "pre-upgrade hooks failed" when enabling Curation and Package Catalog:
If you see:
```
coalesce.go:298: warning: cannot overwrite table with non table for artifactory.postgresql.metrics.extraEnvVars (map[])
coalesce.go:237: warning: skipped value for rabbitmq.initContainers: Not a table.
Error: UPGRADE FAILED: pre-upgrade hooks failed: 1 error occurred:
    * timed out waiting for the condition
```
Run:
```
kubectl get pods --namespace $MY_NAMESPACE
NAME                                                           READY   STATUS      RESTARTS      AGE
cloudsql-proxy-67cfcf5c75-6lxv2                                1/1     Running     1 (32m ago)   33m
ps-jfrog-platform-release-artifactory-0                        10/10   Running     0             33m
ps-jfrog-platform-release-artifactory-nginx-697c454558-l5cmw   1/1     Running     0             24m
ps-jfrog-platform-release-pre-upgrade-check-mj92t              0/1     Completed   0             103s
ps-jfrog-platform-release-rabbitmq-0                           1/1     Running     0             33m
ps-jfrog-platform-release-xray-0                               7/7     Running     0             6m2s
ps-jfrog-platform-release-xray-pre-upgrade-hook-v4cw2          0/1     Pending     0             97s

Since there there were no logs for "kubectl logs -f ps-jfrog-platform-release-xray-pre-upgrade-hook-v4cw2 -n $MY_NAMESPACE"

kubectl describe pod ps-jfrog-platform-release-xray-pre-upgrade-hook-v4cw2
shows:
```
Events:
  Type     Reason             Age    From                Message
  ----     ------             ----   ----                -------
  Warning  FailedScheduling   3m19s  default-scheduler   0/2 nodes are available: 2 node(s) didn't satisfy existing pods anti-affinity rules. preemption: 0/2 nodes are available: 2 No preemption victims found for incoming pod.
  Warning  FailedScheduling   3m18s  default-scheduler   0/2 nodes are available: 2 node(s) didn't satisfy existing pods anti-affinity rules. preemption: 0/2 nodes are available: 2 No preemption victims found for incoming pod.
  Normal   NotTriggerScaleUp  3m19s  cluster-autoscaler  pod didn't trigger scale-up: 1 max node group size reached
```

You may have to delete either the following pod or all "ps-jfrog-platform-release*" pods :
```
kubectl delete pod ps-jfrog-platform-release-pre-upgrade-check-mj92t  ps-jfrog-platform-release-xray-pre-upgrade-hook-v4cw2  ps-jfrog-platform-release-xray-0 --namespace $MY_NAMESPACE
```
or
```
kubectl get pods --namespace $MY_NAMESPACE --no-headers | grep ^ps-jfrog-platform-release | awk '{print $1}' | xargs kubectl delete pod --namespace $MY_NAMESPACE
```
Then you should  see a catalog pod running:
```
kubectl  get pod --namespace $MY_NAMESPACE

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
kubectl logs -f ps-jfrog-platform-release-xray-0 -c xray-server -n $MY_NAMESPACE | grep -i  "jas\|curation"
```
You should see:

```
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [job_manager:630               ] [MainServer                      ] Scheduling JAS Health Check
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [task:86                       ] [MainServer                      ] curationAnalytics task is scheduled
2025-04-18T21:28:46.913Z [jfxr ] [INFO ] [ee53923db4ef22cc] [task:86                       ] [MainServer                      ] curationAuditPackagesRetention task is scheduled
```

### Catalog startup troubleshooting:
```
kubectl describe pod ps-jfrog-platform-release-catalog -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog-869975b4d7-xjgl9  -n $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-catalog-5bd7965879-qrlgl -c router -n $MY_NAMESPACE



kubectl get pod ps-jfrog-platform-release-catalog-869975b4d7-xjgl9 -n $MY_NAMESPACE -o jsonpath='{.spec.containers[*].name}' 
output : catalog router

kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c access  -n $MY_NAMESPACE

kubectl exec -it ps-jfrog-platform-release-xray-0 -c xray-server -- bash
kubectl exec -it ps-jfrog-platform-release-catalog-869975b4d7-v4d52 -c router -n $MY_NAMESPACE -- cat /opt/jfrog/catalog/var/etc/security/join.key
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


#### d) Check the Catalog health 
http://35.229.53.7/catalog/api/v1/system/app_health
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

Call the following URL: https://your.domain/ui/api/v1/jfconnect/entitlements and find the JFrog Catalog entitlements, search for ‘curation’ in the returned response.
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


<!-- 
#### Rabbitmq configuration:

Search "memoryHighWatermark" and found new setting "vm_memory_high_watermark_absolute" that is not in
https://github.com/jfrog/charts/blob/master/stable/xray/values-large.yaml
REf: "vm_memory_high_watermark_absolute" is  a construct from 
https://jfrog.slack.com/archives/CD30SKMDG/p1678277533753349 that was picked from the rabbitmq bitnami chart 
https://github.com/bitnami/charts/blob/main/bitnami/rabbitmq/values.yaml#L476

Ref to maxAvailableSchedulers and onlineSchedulers is in 
https://github.com/bitnami/charts/blob/5492c138a533177ebf1dc660ad19eb18b96f39ba/bitnami/rabbitmq/values.yaml#L210


Rabbitmq is anyway external but maintained by JFrog Platform chart :

From [#249001](https://groups.google.com/a/jfrog.com/g/support-followup/c/STPhVtUGzW4/m/nzIPInHOAAAJ)

You can pass the rabbitmq username , password , url as a secret by creating a secret as below:
```
kubectl delete secret xray-rabbitmq-creds -n $MY_NAMESPACE

kubectl create secret generic xray-rabbitmq-creds --from-literal=username=admin \
--from-literal=password=$MY_RABBITMQ_ADMIN_USER_PASSWORD \
--from-literal=url=amqp://$MY_HELM_RELEASE-rabbitmq:5672 -n $MY_NAMESPACE

kubectl get secret xray-rabbitmq-creds  -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'

```
First get the default load_definition.json  ( from your earlier deploys before you make the load_definition as secret):
```
kubectl get secret <secret-name> -n <namespace> -o json | jq -r '.data["key"]' | base64 -d
kubectl get secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE -o json | jq -r '.data["load_definition.json"]' | base64 -d

```
and then make load_definition also as a secret after changing the admin password in it:
```
kubectl delete secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE

kubectl create secret generic $MY_HELM_RELEASE-load-definition \
--from-file=load_definition.json=./10_optional_load_definition.json -n $MY_NAMESPACE

kubectl get secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'
```

**Note:** If you already deployed rabbitmq from a previous Xray install you can get the  pod yaml definition using:
```text
kubectl get pod $MY_HELM_RELEASE-rabbitmq-0 -n $MY_NAMESPACE -o yaml > ps-jfrog-platform-release-rabbitmq-0.yaml
```

We  want to override the rabbitmq admin user to admin ( instead of guest as the username) and
password (default is password) :
https://github.com/jfrog/charts/blob/b8a04c8f57f7b87d1895cd455fa4859de5db9db2/stable/xray/values.yaml#L484:

Ref: 256917 .
```text
rabbitmq:
  auth:
    username: guest
    password: password
```

The rabbitMQ admin credentials can be set using the **existingPasswordSecret** in the helm values.yaml as
mentioned in the comment in snippet below :
SOme discussion on this in https://jfrog.slack.com/archives/CD30SKMDG/p1686040418572439?thread_ts=1683027138.354849&cid=CD30SKMDG
~~~
rabbitmq:
  enabled: true
  ## Enable the flag if the feature flags in rabbitmq is enabled manually
  rabbitmqUpgradeReady: false
  replicaCount: 1
  rbac:
    create: true
  image:
    registry: releases-docker.jfrog.io
    repository: bitnami/rabbitmq
    tag: 3.11.10-debian-11-r5
  auth:
    username: guest
    password: password
    ## Alternatively, you can use a pre-existing secret with a key called rabbitmq-password by specifying existingPasswordSecret
    # existingPasswordSecret: <name-of-existing-secret>
~~~~
To do this :

a) **Create the rabbitmq-admin-creds:**
```text
kubectl delete secret rabbitmq-admin-creds -n $MY_NAMESPACE 

kubectl create secret generic rabbitmq-admin-creds \
--from-literal=rabbitmq-password=$MY_RABBITMQ_ADMIN_USER_PASSWORD -n $MY_NAMESPACE 

kubectl get secret rabbitmq-admin-creds -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'
kubectl get secret  jfrog-platform-rabbitmq -n devops-acc-us-env -o json | jq '.data | map_values(@base64d)'
```

b) Override with the 7_rabbitmq_enabled_external_values-small.yaml ( for TEST) or 
7_rabbitmq_enabled_external_values-large.yaml ( for PROD) to use the rabbitmq-admin-creds to set the rabbitmq admin 
password.

**Note:** Even in PROD currently you need to use replicaCount = 1 for the rabbitmq pod because
Rabbitmq in HA mode is not fully supported by Xray product and we have  open JIRA
[XRAY-16820](https://jfrog-int.atlassian.net/browse/XRAY-16820) . 
See https://jfrog.slack.com/archives/CD30SKMDG/p1688621345420649?thread_ts=1688614562.639429&cid=CD30SKMDG
```
python yaml-merger.py tmp/6_mergedfile.yaml 7_rabbitmq_enabled_external_values-small.yaml > tmp/7_mergedfile.yaml
or
python yaml-merger.py tmp/6_mergedfile.yaml 7_rabbitmq_enabled_external_values-large.yaml > tmp/7_mergedfile.yaml
```
---

**Now start deploying the helm release to install the JFrog Products starting with Artifactory:**

First do a  Dry run:
```text
helm  upgrade --install $MY_HELM_RELEASE \
-f tmp2/3_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--dry-run
```
or

or

```text
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--version 11.0.6 \
--dry-run
```

---

Then apply without --dry-run :

Make sure you created all the k8s secrets mentioned above . Then make the necessary changes in 3_mergedfile.yaml and 
you can Install  Artifactory HA  with say replicaCount=2 .
```text
helm  upgrade --install $MY_HELM_RELEASE \
-f tmp/3_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}"
--version 107.104.15
```
or

```text
helm  upgrade --install $MY_HELM_RELEASE \
-f 0_values-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml \
-f 1_artifactory-small-nested.yaml \
-f 2_artifactory_db_passwords.yaml \
-f 3_artifactory_admin_user.yaml  \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.masterKeySecretName="joinkey-secret" \
--set artifactory.joinKeySecretName="masterkey-secret" \
--version 11.0.6 
```

---

Check Artifactory logs to verify that it can connect to the filestore and database and can start successfully :
```text
kubectl exec -it $MY_HELM_RELEASE-artifactory-0 -n $MY_NAMESPACE -c artifactory -- bash
cd /opt/jfrog/artifactory/var/log
tail -F /opt/jfrog/artifactory/var/log/artifactory-service.log

or

kubectl exec -it $MY_HELM_RELEASE-artifactory-0 -n $MY_NAMESPACE -c artifactory -- tail -F /opt/jfrog/artifactory/var/log/artifactory-service.log
```
---

Get the nginx external IP/url using:
```
kubectl get svc $MY_HELM_RELEASE-artifactory-nginx -n $MY_NAMESPACE
```
For me it was 104.196.98.19 .

---

Next install xray . 

If you have ALB use that instead of nginx in "--set global.jfrogUrlUI" in below command
```text
helm  upgrade --install $MY_HELM_RELEASE \
-f tmp/7_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.jfrogUrlUI="http://104.196.98.19" 
```

---

If Xray is not connecting to Rabbitmq and you see   following errors in the xray logs:
```
2023-07-23 18:58:25.284035+00:00 [error] <0.28993.9> PLAIN login refused: user 'admin' - invalid credentials
```
It means setting the "xray-rabbitmq-creds" in Values.rabbitmq.external.secrets is not overriding the Rabbitmq admin 
password in the xray system.yaml though Rabbitmq is started successfully with the correct  admin credentials from secret rabbitmq-admin-creds
as shown above. 

Overriding the "-set rabbitmq.external.password" may not work because I am already using rabbitmq.external.secrets 
in the values.yaml ( for the rabbitmq and xray)
In  https://github.com/jfrog/charts/blob/4ba461c93ece4b736db84954982cf4e7ec54f8eb/stable/xray/values.yaml#L189-L193 we can use the "password: "{{ .Values.rabbitmq.external.password }}""  i.e from "-set rabbitmq.external.password" only if Values.rabbitmq.external.secrets is not used.
```
      {{- if not .Values.rabbitmq.external.secrets }}
        url: "{{ tpl .Values.rabbitmq.external.url . }}"
        username: "{{ .Values.rabbitmq.external.username }}"
        password: "{{ .Values.rabbitmq.external.password }}"
      {{- end }}
```
I posted this to  https://jfrog.slack.com/archives/CD30SKMDG/p1690306078218199 and logged INST-6705

To **workaround** this I exported the xray system.yaml  to [8_xray_system_yaml.yaml](values/For_PROD_Setup/8_xray_system_yaml.yaml).
Set the shared.rabbitMq.password to using the correct "clear_text_admin_password_for_rabbitmq" .
Then create the secret:

```
kubectl delete secret xray-custom-systemyaml -n $MY_NAMESPACE
kubectl create secret generic xray-custom-systemyaml --from-file=system.yaml=./8_xray_system_yaml.yaml \
-n $MY_NAMESPACE

```
Then use secret xray-custom-systemyaml to do the systemYamlOverride for xray: 
```
python yaml-merger.py tmp/7_mergedfile.yaml 8_override_xray_system_yaml_in_values.yaml > tmp/8_mergedfile.yaml
``` 
Next upgrade install to do the systemYamlOverride for xray . If you have ALB use that instead of nginx
in "--set global.jfrogUrlUI" in below command
```text
helm  upgrade --install $MY_HELM_RELEASE \
-f tmp/8_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.jfrogUrlUI="http://104.196.98.19" 
```


---
**Enable JAS**

If xray is up and is now integrated with Artifactory , you can perform the Xray DBSync.
After that enable JAS in the helm values.yaml:

```
python yaml-merger.py tmp/8_mergedfile.yaml 9_enable_JAS.yaml > tmp/9_mergedfile.yaml
```

Next do the helm upgrade to install / enable JAS:
```text
helm  upgrade --install $MY_HELM_RELEASE \
-f tmp/9_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
--set global.jfrogUrlUI="http://104.196.98.19" \
--dry-run
```

k get deployment
```
NAME                                          READY   UP-TO-DATE   AVAILABLE   AGE
cloudsql-proxy                                1/1     1            1           5d20h
ps-jfrog-platform-release-artifactory-nginx   1/1     1            1           38h
ps-jfrog-platform-release-catalog             1/1     1            1           37h
```

k get sts
```       
NAME                                    READY   AGE
ps-jfrog-platform-release-artifactory   1/1     38h
ps-jfrog-platform-release-rabbitmq      1/1     37h
ps-jfrog-platform-release-xray          1/2     37h
```

-->

---

### FAQs:
How to set the artifactory's artifactory.artifactory.replicaCount to 1 ?

To edit the replica count of a StatefulSet in Kubernetes there are multiple options:
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

Here's how you can modify the replica count of a StatefulSet deployed via Helm:

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

To download a specific version of a Helm chart (e.g., `107.84.14`) to a `.tgz` file for use in an air-gapped environment, you can use the `helm pull` command with the specific version. Here’s how you can do it:

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
Here’s the full set of commands you would run on a machine with internet access:

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
