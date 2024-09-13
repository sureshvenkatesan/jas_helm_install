## Deploying Artifactory using Helm and `jfrog/artifactory` chart

- Fill in your own `imagePullSecrets` and `imageRegistry` in values/values-main.yaml
-  Pass your own ca.crt for artifactory if needed for ssl configuration. 

See prerequisite for ca.crt. [here](https://jfrog.com/help/r/jfrog-installation-setup-documentation/prerequisites-for-custom-tls-certificate) 
```
kubectl create secret tls my-cacert --cert=ca.crt --key=ca.private.key -n <namespace> 
```

1. Switch to  the folder with your values.yaml files
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/install_artifactory_from_artifactory_chart/mysteps
```

2. Set the Following Environment variables:
```
export MY_NAMESPACE=jfrog-ns
export MY_HELM_RELEASE=artifactory-release

export MASTER_KEY=$(openssl rand -hex 32)
# Save this master key to reuse it later
echo ${MASTER_KEY}
# or you can hardcode it to
export MASTER_KEY=c64231fe4324121f5de6a5834f35195bba0d857695f80c974c788cfdb4e70f09

export JOIN_KEY=$(openssl rand -hex 32)
# Save this join key to reuse it later
echo ${JOIN_KEY}
# or you can hardcode it to
export JOIN_KEY=6dec6691f86d9e3de3cc4645f7a7eb33c3adc31071ec0d6567ad2069295c5397

export RT_VERSION=7.84.14

export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=password

export DB_SERVER=10.1.1.1


export RT_DATABASE_USER=artifactory
export RT_DATABASE_PASSWORD=password
export ARTIFACTORY_DB=sureshv-helm-ha-db

export BINARYSTOREXML_BUCKETNAME=sureshv-ps-us-east-1
```

3. Prepare a clean K8s environment:
```
helm uninstall $MY_HELM_RELEASE -n $MY_NAMESPACE
kubectl delete ns  $MY_NAMESPACE
kubectl create ns  $MY_NAMESPACE
```

4. Create the secrets:

a) Master and Join Keys:
```
kubectl create secret generic masterkey-secret --from-literal=master-key=${MASTER_KEY} -n $MY_NAMESPACE
kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $MY_NAMESPACE
```
b) License:
- [Add Licenses Using Secrets](https://jfrog.com/help/r/jfrog-installation-setup-documentation/add-licenses-using-secrets)
```
kubectl create secret generic artifactory-license --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE

```
c) Database
[Use an External Database with Artifactory Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/use-an-external-database-with-artifactory-helm-installation)

If using Postgres external database
```
kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $MY_NAMESPACE
```
If using Oracle database check the subsection on :
`Configure Artifactory Helm Installation with an External Oracle Database`
Example db-url=jdbc:oracle:thin:@exampledb.amazonaws.com:1521:ORCL

d) Admin user password:
```
kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=password' -n $MY_NAMESPACE
 
```

e) Secret to Override the binaryStore:

**For AWS binaryStore:**
- [S3 Direct Upload Template (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended)  :
```
kubectl apply -f ../values/4_custom-binarystore-s3-direct-use_instance-creds.yaml -n $MY_NAMESPACE
```
**For  awsS3V3 connection details.**
For IAM roles see [here](https://jfrog.com/help/r/artifactory-how-to-configure-an-aws-s3-object-store-using-an-iam-role-instead-of-an-iam-user)

We recommend using the [S3 Direct Upload Template (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended)

or

**For GCP binaryStore:**

- [Google Cloud Storage Authentication Mechanism](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-cloud-storage-authentication-mechanism)
- [Advanced Storage Options](https://jfrog.com/help/r/jfrog-installation-setup-documentation/advanced-storage-options) > "Google Storage"
- [Google Storage Binary Provider Native Client Template](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-binary-provider-native-client-template)
- [google-storage-v2-direct template configuration (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-storage-v2-direct-template-configuration-recommended)


Note: IMPORTANT: The GCP service Account for Storage must be called `"gcp.credentials.json"` because this is used later as the secret key!
```
kubectl create secret generic artifactory-gcp-creds --from-file=./gcp.credentials.json -n $MY_NAMESPACE
```
**For GCP Storage:**
```
envsubst < ../../scripts/custom-binarystore-gcp.tmpl > custom-binarystore.yaml

kubectl apply -f custom-binarystore.yaml -n $MY_NAMESPACE
```

f) Create a configmap for the  [Oracle Instant Client](https://www.oracle.com/database/technologies/instant-client/downloads.html) Type 2 driver
```
curl https://download.oracle.com/otn_software/linux/instantclient/2111000/instantclient-basic-linux.x64-21.11.0.0.0dbru.zip -o instantclient-basic-linux.x64-21.11.0.0.0dbru.zip

kubectl create configmap oci_type2_zip \
  --from-file=instantclient-basic-linux.x64-21.11.0.0.0dbru.zip=instantclient-basic-linux.x64-21.11.0.0.0dbru.zip \
  -n $MY_NAMESPACE
 ```
 It failed with:
 ```
 error: failed to create configmap: Request entity too large: limit is 3145728
 ```
So  as mentioned in [prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md](../jfrog_qa_custom_values/prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md)
I ran:
```
kubectl apply -f ../values/prepopulate_pv_with_custom_oracle_instantclient_type2_driver_zip.yaml -n $MY_NAMESPACE

kubectl cp instantclient-basic-linux.x64-21.11.0.0.0dbru.zip copy-pod:/mnt/data/ -n $MY_NAMESPACE

or

tar cf - instantclient-basic-linux.x64-21.11.0.0.0dbru.zip | pv | kubectl exec -i -n $MY_NAMESPACE copy-pod -- tar xf - -C /mnt/data/
```



5. Generate the final `3_mergedfile.yaml` :
   Pick the Artifactory sizing configuration from https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing

I will use [artifactory-small.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-small.yaml) and 
[artifactory-small-extra-config.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-small-extra-config.yaml)

Next merge all of them for Artifactory :
For GCP ( with GCP storage) and Postgress External DB:
```
python ../../scripts/merge_yaml_with_comments.py ../values/values-main.yaml \
../values/values-artifactory-gcp-gstorage-postgres.yaml \
/Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
/Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml -o 3_mergedfile.yaml
```
For S3 storage  and Oracle External DB:
```
python ../../scripts/merge_yaml_with_comments.py ../values/values-main.yaml \
../values/values-artifactory-s3storage-oracle.yaml \
/Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
/Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml -o 3_mergedfile.yaml
```

6. Verify you have the helm  chart you need:
```
helm repo update
helm search repo jfrog-chart
helm pull jfrog/artifactory --version 107.84.14
```
This will download the chart as artifactory-107.84.14.tgz

7. First do a Dry run:
```
helm upgrade --install $MY_HELM_RELEASE \
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--dry-run \
./artifactory-107.84.14.tgz

or

helm upgrade --install $MY_HELM_RELEASE \
-f ../values/values-main.yaml \
-f ../values/values-artifactory-gcp-gstorage-postgres.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--dry-run \
./artifactory-107.84.14.tgz

or

helm upgrade --install $MY_HELM_RELEASE \
-f ../values/values-main.yaml \
-f ../values/values-artifactory-gcp-gstorage-postgres-w-oci-type2driver-in-rt-image.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.imageRegistry="psazuse.jfrog.io"
--dry-run \
./artifactory-107.84.14.tgz


```
8. Next run without the --dry-run
 
```
helm upgrade --install $MY_HELM_RELEASE \
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
./artifactory-107.84.14.tgz 

or

helm upgrade --install $MY_HELM_RELEASE \
-f ../values/values-main.yaml \
-f ../values/values-artifactory-gcp-gstorage-postgres.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
./artifactory-107.84.14.tgz

or

helm upgrade --install $MY_HELM_RELEASE \
-f ../values/values-main.yaml \
-f ../values/values-artifactory-gcp-gstorage-postgres-w-oci-type2driver-in-rt-image.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small.yaml \
-f /Users/sureshv/myCode/github-jfrog/charts/stable/artifactory/sizing/artifactory-small-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--set artifactory.imageRegistry="psazuse.jfrog.io" \
./artifactory-107.84.14.tgz
```

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- bash

---
### Check the node external IP , pod status and logs

```
kubectl get pods -o wide --namespace $MY_NAMESPACE
kubectl get nodes -o wide --namespace $MY_NAMESPACE
kubectl describe pod "${MY_HELM_RELEASE}-artifactory-0" --namespace $MY_NAMESPACE
kubectl logs -f "${MY_HELM_RELEASE}-artifactory-0" --all-containers=true --max-log-requests=10 --namespace $MY_NAMESPACE
```
---
### To uninstall and redeploy everything from the beginning:
```
helm uninstall $MY_HELM_RELEASE -n $MY_NAMESPACE

helm uninstall $MY_DIST_HELM_RELEASE -n $MY_NAMESPACE

kubectl delete ns  $MY_NAMESPACE
kubectl create ns  $MY_NAMESPACE
kubectl  delete pvc --all -n $MY_NAMESPACE

kubectl create secret generic masterkey-secret --from-literal=master-key=${MASTER_KEY} -n $MY_NAMESPACE
kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $MY_NAMESPACE
kubectl create secret generic artifactory-license --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE

kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $MY_NAMESPACE

kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=Test@123' -n $MY_NAMESPACE

kubectl create secret generic artifactory-gcp-creds --from-file=./gcp.credentials.json -n $MY_NAMESPACE

kubectl apply -f custom-binarystore.yaml -n $MY_NAMESPACE
```
---