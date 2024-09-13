
Instead of installing Artifactory, Xray and JAS all in one shot (in AWS EKS or in GKE ), it is recommended to :
```text
a) Create  the secrets ( for all user passwords, binarystore configuration , system.yaml etc) 
b) first install  Artifactory , login to it and set the Artifactory base url
c) install Xray and verify it successfully connects to the Artifactory instance
d) Do Xray DB Sync
e) Then enable JAS
```

The steps to do the above are explained in this Readme. 

It also shows :
- how to use the [envsubst](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) command 
  to get the values to create the  secrets from environmental variables. 
- the step-by-step approach to improvise the values.yaml using the [yaml-merger-py](https://github.com/Aref-Riant/yaml-merger-py) 
  to generate the final values.yaml needed for the helm install.
---
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
Here are the steps:
1.

Create an IAM role that the Artifactory's pods service account can take on, equipped with a policy that bestows upon 
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

## Application Load Balancer as Ingress gateway setup
You can refer to either of these resources for guidance:
- The documentation available at: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- Alternatively, you can also explore: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/

Main steps are highlighted below

1 - Create IAM policy for the load balancer .  This step is required only if the policy doesn’t already exists.
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

Once your cluster is all enabled, you can install the JPD platform using values.yaml that can be generated as explained in next section.

---
## Steps to generate the helm values.yaml for the JPD installation

Please download the  python script to merge values.yaml files with best effort to preserve comments, formatting,
and order of items from https://github.com/Aref-Riant/yaml-merger-py

Requirements:
```text
pip install ruamel.yaml
pip install mergedeep
```

usage:
```
python yaml-merger.py file1.yaml file2.yaml > mergedfile.yaml
```
---
After you download this git repo do:
```text
cd values/For_PROD_Setup
```

---

Set the following Environmental variables based on your Deployment K8s environment where you will install the 
JFrog Platform.

**Note:** the CLOUD_PROVIDER can be gcp or aws ( JFrog Helm charts support Azure as well but this readme was created 
only based on gcp or aws  )

**Environment variables:**
```text
export CLOUD_PROVIDER=gcp
export MY_NAMESPACE=ps-jfrog-platform
export MY_HELM_RELEASE=ps-jfrog-platform-release

export MASTER_KEY=$(openssl rand -hex 32)
# Save this master key to reuse it later
echo ${MASTER_KEY}
# or you can hardcode it to
export MASTER_KEY=02ba23e285e065d2a372b889ac3dbd51510dd0399875f95294312634f50b6960

export JOIN_KEY=$(openssl rand -hex 32)
# Save this join key to reuse it later
echo ${JOIN_KEY}
# or you can hardcode it to
export JOIN_KEY=763d4bdf02ff4cc16d7c5cf2abeccf3f243b5557bf738ec5438fd55df0cec3cc

export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=password

export DB_SERVER=100.185.45.104


export RT_DATABASE_USER=artifactory
export RT_DATABASE_PASSWORD=password
export ARTIFACTORY_DB=sivas-helm-ha-db

export MY_RABBITMQ_ADMIN_USER_PASSWORD=password
export XRAY_DATABASE_USER=xray
export XRAY_DATABASE_PASSWORD=password
export XRAY_DB=xray
```
---

**Prepare the K8s environment:**

**Note:** These commands will be useful if you want to iterate run the helm release multiple times i.e  you are not 
starting with a clean k8s environment
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
etc
```

Delete Namespace only if needed as this will delete all the secrets as well:
```text
kubectl delete ns  $MY_NAMESPACE
```

---

**Otherwise, if you are starting with a clean k8s environment:**

Create the Namespace:
```
kubectl create ns  $MY_NAMESPACE
```

---
**Create the secrets**

**Master and Join Keys:**
```text
kubectl delete secret generic masterkey-secret  -n $MY_NAMESPACE
kubectl delete secret generic joinkey-secret   -n $MY_NAMESPACE

kubectl create secret generic masterkey-secret --from-literal=master-key=${MASTER_KEY} -n $MY_NAMESPACE
kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $MY_NAMESPACE
```

**License:**

Create a secret for license with the dataKey as "artifactory.lic" for HA or standalone ( if you want you can name the 
dataKey as artifactory.cluster.license for HA but not necessary) :
```text
kubectl delete secret  artifactory-license  -n $MY_NAMESPACE

kubectl create secret generic artifactory-license --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE

kubectl get secret artifactory-license -o yaml -n $MY_NAMESPACE

kubectl get secret artifactory-license -o json -n $MY_NAMESPACE | jq -r '.data."artifactory.lic"' | base64 --decode

```


Note: if you create it as the following then the dataKey will be art.lic ( i.e same as the name of the file)
```text
kubectl create secret generic artifactory-license \  
--from-file=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE
```



---

**Below steps outline the above mentioned step-by-step approach to improvise the values.yaml  you will finally use:**

Ref: https://github.com/jfrog/charts/blob/master/stable/artifactory/values-large.yaml

File mentioned below are in [For_PROD_Setup](values/For_PROD_Setup)

1. Start with the 1_artifactory-values-small.yaml for TEST environment or 1_artifactory-values-large.yaml for PROD 
   environment

```text
python yaml-merger.py 0_values-dynata-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml 1_artifactory-values-small.yaml > tmp/1_mergedfile.yaml
or
python yaml-merger.py 0_values-dynata-artifactory-xray-platform_prod_$CLOUD_PROVIDER.yaml 1_artifactory-values-large.yaml > tmp/1_mergedfile.yaml
```

---

2. Override using the 2_artifactory_db_passwords.yaml

**Artifactory Database Credentials:**
```text
kubectl delete secret  artifactory-database-creds  -n $MY_NAMESPACE

kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $MY_NAMESPACE
```

```
python yaml-merger.py tmp/1_mergedfile.yaml 2_artifactory_db_passwords.yaml > tmp/2_mergedfile.yaml
```
---

3. Override using 3_artifactory_admin_user.yaml 

**The artifactory default admin user secret:**

Review KB

https://jfrog.com/help/r/artifactory-how-to-unlock-a-user-s-who-is-locked-out-of-artifactory-and-recover-admin-account/non-admin-user-recovery

```text
kubectl delete secret  art-creds  -n $MY_NAMESPACE

kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=Test@123' -n $MY_NAMESPACE
```

```
python yaml-merger.py tmp/2_mergedfile.yaml 3_artifactory_admin_user.yaml > tmp/3_mergedfile.yaml
```
---

4. Override the binaryStore

For AWS https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended :
```
kubectl apply -f 4_custom-binarystore-s3-direct-use_instance-creds.yaml -n $MY_NAMESPACE
```
or

For GCP ( google-storage-v2-direct template configuration from https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-binary-provider-native-client-template ):

```
kubectl delete secret  artifactory-gcp-creds -n $MY_NAMESPACE

kubectl create secret generic artifactory-gcp-creds --from-file=/Users/sureshv/.gcp/gcp.credentials.json \
-n $MY_NAMESPACE

envsubst < binarystore_config/custom-binarystore-gcp.tmpl > binarystore_config/custom-binarystore.yaml

kubectl apply -f binarystore_config/custom-binarystore.yaml -n $MY_NAMESPACE
```
---

5.  Override the system.yaml using either 5_artifactory_system_small.yaml for TEST environment or 
    5_artifactory_system_large.yaml for PROD

See  https://jfrog.com/help/r/how-do-i-tune-artifactory-for-heavy-loads/how-do-i-tune-artifactory-for-heavy-loads
 
```
kubectl delete secret artifactory-custom-systemyaml -n $MY_NAMESPACE
kubectl create secret generic artifactory-custom-systemyaml --from-file=system.yaml=./5_artifactory_system_small.yaml \
-n $MY_NAMESPACE
or
kubectl create secret generic artifactory-custom-systemyaml --from-file=system.yaml=./5_artifactory_system_large.yaml \
-n $MY_NAMESPACE
```
---

6. Override with the 6_xray_db_passwords_pod_size-values-small.yaml for TEST environment or 
   6_xray_db_passwords_pod_size-values-large.yaml for PROD

```text
kubectl delete secret generic xray-database-creds -n $MY_NAMESPACE
kubectl create secret generic xray-database-creds \
--from-literal=db-user=$XRAY_DATABASE_USER \
--from-literal=db-password=$XRAY_DATABASE_PASSWORD \
--from-literal=db-url=postgres://$DB_SERVER:5432/$XRAY_DB\?sslmode=disable -n $MY_NAMESPACE

If "jq --version" >=1.6  where jq  @base64d filter is avaiable use :

kubectl get secret xray-database-creds  -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'

otherwise use:
bash decode_secret.sh <secret-to-decrypt>  <namespace>
```

```
python yaml-merger.py tmp/3_mergedfile.yaml 6_xray_db_passwords_pod_size-values-small.yaml > tmp/6_mergedfile.yaml
or
python yaml-merger.py tmp/3_mergedfile.yaml 6_xray_db_passwords_pod_size-values-large.yaml > tmp/6_mergedfile.yaml
```

7. **Rabbitmq configuration:**

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
First get the default load_definition.json  ( from your earlier deploys before you maje the load_definition as secret):
```
kubectl get secrets | grep load-definition -n $MY_NAMESPACE
kubectl get secret <secret-name> -n <namespace> -o json | jq -r '.data["key"]' | base64 --decode
kubectl get secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE -o json | jq -r '.data["load_definition.json"]' 
| base64 --decode

```
and then make load_definition also as a secret after changing the admin password in it:
```
kubectl delete secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE

kubectl create secret generic $MY_HELM_RELEASE-load-definition \
--from-file=load_definition.json=./10_optional_load_definition.json -n $MY_NAMESPACE

kubectl get secret $MY_HELM_RELEASE-load-definition -n $MY_NAMESPACE -o json | jq '.data | map_values(@base64d)'
```

**Note:** If you already deployed rabbitmq from a previous Xray install you can get the  pod yal definition using:
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
-f tmp/3_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set gaUpgradeReady=true \
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
--set gaUpgradeReady=true
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

**Verify:**

SSH and verify rabbitMQ is up and functional:
```text
$kubectl logs $MY_HELM_RELEASE-rabbitmq-0 -n $MY_NAMESPACE

kubectl exec -it $MY_HELM_RELEASE-rabbitmq-0  -n $MY_NAMESPACE -- bash
find / -name rabbitmq.conf
cat /opt/bitnami/rabbitmq/etc/rabbitmq/rabbitmq.conf

rabbitmqctl status
rabbitmqctl cluster_status
rabbitmqctl list_queues

SSH to the rabbitmq pod and run below curl command:
Note: the default admin password for rabbitMQ is password but we did override it to Test@123 as mentioned above:

curl --user admin:Test@123 http://localhost:15672/api/vhosts
curl --user admin:Test@123 "http://jfrog-platform-rabbitmq:15672"
```

SSH and verify the Xray server is up and functional
```text
kubectl exec -it $MY_HELM_RELEASE-xray-0 -n $MY_NAMESPACE -c xray-server -- bash
Example:
kubectl exec -it $MY_HELM_RELEASE-xray-0 -n $MY_NAMESPACE -c xray-server -- bash

cd /opt/jfrog/xray/var/etc
cat /opt/jfrog/xray/var/etc/system.yaml


cd /opt/jfrog/xray/var/log
cat /opt/jfrog/xray/var/log/xray-server-service.log
tail -F /opt/jfrog/xray/var/log/xray-server-service.log
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

---

Note: JAS runs as a k8s job , so you will see the pods from the job only when you "Scan for Contextual Analysis".
At that time when you run the following , it will show the pods that are running for the job.
```text
watch kubectl get pods  -n $MY_NAMESPACE
```


----
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
