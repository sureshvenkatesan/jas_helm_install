## For artifactory:

1.Switch to the work folder
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/jfrog_qa_custom_values/mysteps
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
```
kubectl create secret generic artifactory-database-creds \
--from-literal=db-user=$RT_DATABASE_USER \
--from-literal=db-password=$RT_DATABASE_PASSWORD \
--from-literal=db-url=jdbc:oracle:thin:@$DB_SERVER:1521:$ARTIFACTORY_DB -n $MY_NAMESPACE
```
As per  https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html  , get all new and older versions of Oracle JDBC drivers from Maven Central Repository  i.e  https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/ . For example: [ojdbc8-19.16.0.0.jar](https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/19.16.0.0/ojdbc8-19.16.0.0.jar) or [ojdbc8-19.24.0.0.jar](https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/19.24.0.0/ojdbc8-19.24.0.0.jar) i.e the latest in the 19.x series as of Aug 2024. 

d) Admin user password:
```
kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=password' -n $MY_NAMESPACE
 
```
e) If a file is below the K8s `configmap` limit of `3 MB` you can create it using:  
```
kubectl  create configmap oci_type2_zip \                         
   --from-file=instantclient-basic-linux.x64-21.11.0.0.0dbru.zip=instantclient-basic-linux.x64-21.11.0.0.0dbru.zip \
   -n $MY_NAMESPACE
```
But the   [Oracle Instant Client](https://www.oracle.com/database/technologies/instant-client/downloads.html) Type 2 driver is 75 MB so 
it will fail with:
 ```
 error: failed to create configmap: Request entity too large: limit is 3145728
 ```
 So  as mentioned in [prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md]
 (prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md) one option for Airgap environment is to create a PV and scp the 
driver zip file to that PV .
```
kubectl apply -f ../artifactory/prepopulate_pv_with_custom_oracle_instantclient_type2_driver_zip.yaml -n $MY_NAMESPACE

kubectl cp instantclient-basic-linux.x64-21.11.0.0.0dbru.zip copy-pod:/mnt/data/ -n $MY_NAMESPACE

or

tar cf - instantclient-basic-linux.x64-21.11.0.0.0dbru.zip | pv | kubectl exec -i -n $MY_NAMESPACE copy-pod -- tar xf - -C /mnt/data/
```
Note:
YOu may get  error message `exec failed: unable to start container process: exec: "tar": executable file not found in 
$PATH` which indicates that the tar command is not available in the container's environment. The oc cp (or kubectl cp) 
command typically relies on tar to perform the copy operation, and if the container does not have tar installed, the copy operation will fail.

**Ref KBs:**
- https://github.com/gitta-jfrog/kubernetes/blob/main/distribution/preStartCommandExample.yaml
- [Configure Other External Databases with Artifactory Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/use-an-external-database-with-artifactory-helm-installation)
- [Configure Artifactory to use Oracle](https://jfrog.com/help/r/jfrog-installation-setup-documentation/configure-artifactory-to-use-oracle)
- [How to resolve the oracle DB driver error with metadata service after upgrading to version 7.55.x and above in kubernetes with splitServicesToContainers](https://jfrog.com/help/r/artifactory-how-to-resolve-the-oracle-db-driver-error-with-metadata-service-after-upgrading-to-version-7-55-x-and-above-in-kubernetes-with-splitservicestocontainers)
5. 
   Pick the Artifactory sizing configuration from https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing

I will use [artifactory-large.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-large.yaml) and 
[artifactory-large-extra-config.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-large-extra-config.yaml)

Optional:  merge all of them for Artifactory:
Note: This way of merging does not work well when  `extraEnvironmentVariables` is not a root element and
when you use "artifactory.customVolumes: |" and   "artifactory.customVolumeMounts: |" so skip it.
```
python ../../scripts/merge_yaml_with_comments.py ../artifactory/values-main.yaml \
../artifactory/values-artifactory.yaml \
../artifactory/artifactory-large.yaml \
../artifactory/artifactory-large-extra-config.yaml -o artifactory_mergedfile.yaml
```


6. First do a Dry run:
```
helm upgrade --install $MY_HELM_RELEASE \
-f ../artifactory/values-main.yaml \
-f ../artifactory/values-artifactory.yaml \
-f ../artifactory/artifactory-large.yaml \
-f ../artifactory/artifactory-large-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--dry-run \
./artifactory-107.84.14.tgz
```
7. Next run without the --dry-run
```
helm upgrade --install $MY_HELM_RELEASE \
-f ../artifactory/values-main.yaml \
-f ../artifactory/values-artifactory.yaml \
-f ../artifactory/artifactory-large.yaml \
-f ../artifactory/artifactory-large-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
./artifactory-107.84.14.tgz
```

### Check the node external IP , pod status and logs

```
kubectl get pods -o wide --namespace $MY_NAMESPACE
kubectl get nodes -o wide --namespace $MY_NAMESPACE
kubectl describe pod "${MY_HELM_RELEASE}-artifactory-0" --namespace $MY_NAMESPACE
kubectl logs -f "${MY_HELM_RELEASE}-artifactory-0" --all-containers=true --max-log-requests=10 --namespace $MY_NAMESPACE
```

---
### Other use-cases:
i) Example of using `artifactory.customSidecarContainers`

**Ref**:
- Introduced in Artifactory [v7.12.15](https://github.com/jfrog/charts/blob/master/stable/artifactory/CHANGELOG.md#71215---mar-21-2019)
- [Add Custom Sidecars Containers in Helm Installations](https://jfrog.com/help/r/jfrog-installation-setup-documentation/add-custom-sidecars-containers-in-helm-installations)
- Example in [ARTIFACTORY: Troubleshoot Artifactory <> AWS S3 bucket connection/access related issues in Kubenates cluster deployed using Helm charts](https://jfrog.com/help/r/artifactory-troubleshoot-artifactory-aws-s3-bucket-connection-access-related-issues-in-kubenates-cluster-deployed-using-helm-charts/option-2)

ii) If you use S3 bucket for filestore using a `“artifactory.persistence.customBinarystoreXmlSecret”` xml as in 
[4_custom-binarystore-s3-direct-use_instance-creds.yaml](../install_artifactory_from_artifactory_chart/values/4_custom-binarystore-s3-direct-use_instance-creds.yaml)
you will still have a automatically created  PVC for `/opt/jfrog/artifactory/var` of the artifactory pod   .
The storageClass of this PVC is determined by `artifactory.storageClassName` and size is determined by `artifactory.
persistence.size` 
The cache will be part of it.     
You still control the `cache-fs` size with `maxCacheSize` in the `“artifactory.persistence.
customBinarystoreXmlSecret”` or the `artifactory.persistence.maxCacheSize` . But this `maxCacheSize` needs to be smaller than the `artifactory.persistence.size`

But if you want a dedicated PVC  just for cachefs layer then use:
```
artifactory:
    customVolumes: |
      - name: "cache-fast-storage"
        persistentVolumeClaim:
          claimName: "cache-fast-storage-pvc"
    customVolumeMounts: |
      - name: "cache-fast-storage" 
        mountPath: "/cache/dir"
```
Then create the PV and PVC as mentioned in https://jfrog.com/help/r/artifactory-how-to-apply-your-pre-made-pvc-s-for-each-artifactory-pod-in-a-helm-deployment


---

## Deploying Distribution via Helm using `jfrog/distribution` chart

1. Switch to the work folder
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/jfrog_qa_custom_values/mysteps
```

2. Set some more environment variables:
```
export DIST_VERSION=2.25.1
export JFROG_URL="https://35.185.121.172" 
export MY_DIST_HELM_RELEASE=distribution-release
```

3. Pick the Distribution sizing template from https://github.com/jfrog/charts/tree/master/stable/distribution/sizing .
I used [distrubution-medium.yaml](https://github.com/jfrog/charts/blob/master/stable/distribution/sizing/distrubution-medium.yaml)

Optional: 
```
python ../../scripts/merge_yaml_with_comments.py ../distribution/values-main.yaml \
../distribution/distrubution-medium.yaml  -o distribution_mergedfile.yaml
```

4. Verify you have the helm  chart you need:
```
helm repo update
helm search repo jfrog-chart
helm pull jfrog/distribution --version 102.25.1
```

This will download the chart as distribution-102.25.1.tgz

5. First do a Dry run:
```
helm upgrade --install $MY_DIST_HELM_RELEASE \
-f ../distribution/values-main.yaml \
-f ../distribution/distrubution-medium.yaml \
--namespace $MY_NAMESPACE \
--set distribution.joinKey="${JOIN_KEY}" \
--set distribution.jfrogUrl="{JFROG_URL}" \
--set global.versions.distribution="${DIST_VERSION}" \
--dry-run \
./distribution-102.25.1.tgz 
```

6. Next run without the --dry-run
 
---

## To fix license do the following.

Get the license hash using https://jfrog.com/help/r/jfrog-rest-apis/ha-license-information 
```
curl -u admin https://<jfrogurl>/artifactory/api/system/licenses
```

Then delete one of the duplicate license hash  :
https://jfrog.com/help/r/jfrog-rest-apis/delete-ha-cluster-license 
```
curl -u admin -XDELETE https://<jfrogurl>/artifactory/api/system/licenses?licenseHash=licenseHash1, licenseHash2…
```

The install new licenses using:
https://jfrog.com/help/r/jfrog-rest-apis/install-ha-cluster-licenses


