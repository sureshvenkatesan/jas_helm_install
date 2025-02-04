
# Artifactory Setup Guide

## Steps to Set Up Artifactory

### **Mandatory Steps**

1. **Switch to the work folder**:
   ```bash
   cd /Users/sureshv/myCode/github-sv/jas_helm_install/jfrog_qa_custom_values/mysteps
   ```

2. **Set Environment Variables**:
   ```bash
   export MY_NAMESPACE=jfrog-ns
   export MY_HELM_RELEASE=artifactory-release

   export MASTER_KEY=$(openssl rand -hex 32)
   echo ${MASTER_KEY} # Save for future reuse


   export JOIN_KEY=$(openssl rand -hex 32)
   echo ${JOIN_KEY} # Save for future reuse


   export RT_VERSION=7.84.14 # Replace with the Artifactory version you want to deploy
   export ADMIN_USERNAME=admin
   export ADMIN_PASSWORD=password
   export DB_SERVER=10.1.1.1
   export RT_DATABASE_USER=artifactory
   export RT_DATABASE_PASSWORD=password
   export ARTIFACTORY_DB=sureshv-helm-ha-db
   ```

3. **Prepare a clean K8s environment**:
   ```bash
   helm uninstall $MY_HELM_RELEASE -n $MY_NAMESPACE
   kubectl delete ns $MY_NAMESPACE
   kubectl create ns $MY_NAMESPACE
   ```

4. **Create Required Secrets**:

   a) Master and Join Keys:
   ```bash
   kubectl create secret generic masterkey-secret --from-literal=master-key=${MASTER_KEY} -n $MY_NAMESPACE
   kubectl create secret generic joinkey-secret --from-literal=join-key=${JOIN_KEY} -n $MY_NAMESPACE
   ```
   b) License:

   - [Add Licenses Using Secrets](https://jfrog.com/help/r/jfrog-installation-setup-documentation/add-licenses-using-secrets)
   ```bash
   kubectl create secret generic artifactory-license --from-file=artifactory.lic=/path/to/art.lic -n $MY_NAMESPACE
   ```
    For example:
    ```bash
    kubectl create secret generic artifactory-license \
    --from-file=artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic -n $MY_NAMESPACE
    ```
   c) Database:

   [Use an External Database with Artifactory Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/use-an-external-database-with-artifactory-helm-installation)

   **Using Postgres external database**:

   ```bash
   kubectl create secret generic artifactory-database-creds \
     --from-literal=db-user=$RT_DATABASE_USER \
     --from-literal=db-password=$RT_DATABASE_PASSWORD \
     --from-literal=db-url=jdbc:postgresql://$DB_SERVER:5432/$ARTIFACTORY_DB -n $MY_NAMESPACE
   ```
   
   **Using Oracle Database**:

   If you want to use an external Oracle Database , we need the [Oracle Instant Client Type 2 driver](https://www.oracle.com/database/technologies/instant-client/downloads.html) which is 75 MB.
   
   To mount the "Oracle Instant Client Type 2 driver" we experimented different options :
   - cannot  use configmap as a K8s configmap has 3 MB limit
   - “[Oracle Instant Client Setup with InitContainer in Artifactory Pod](using_customInitcontainer_for_Oracle_InstantClient_type2_driver.md#oracle-instant-client-setup-with-initcontainer-in-artifactory-pod)”  
   - Use Persistent Volume (PV) for files larger than 3 MB  [prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md](prepopulate_PV_with_file_larger_than_3MB_configmap_limit.md)

   Finally we used steps in [Oracle Instant Client Setup with Custom artifactory-pro image](using_custom_artifactory-pro-image_with_Oracle_InstantClient_type2_driver.md) which uses [artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml](artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml)

   Refer subsection `Configure Artifactory Helm Installation with an External Oracle Database` in [Use an External Database with Artifactory Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/use-an-external-database-with-artifactory-helm-installation) 

   ```bash
   kubectl create secret generic artifactory-database-creds \
     --from-literal=db-user=$RT_DATABASE_USER \
     --from-literal=db-password=$RT_DATABASE_PASSWORD \
     --from-literal=db-url=jdbc:oracle:thin:@$DB_SERVER:1521:$ARTIFACTORY_DB -n $MY_NAMESPACE
   ```


   d) Admin User Password:
   ```bash
   kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=password' -n $MY_NAMESPACE
   ```

5. **Run Helm Commands**:

Pick the Artifactory sizing configuration from https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing

I will use [artifactory-large.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-large.yaml)

**Note:**
To download the Helm chart from the JFrog repository in an air-gapped environment, follow these steps:

a) On the Online Machine:
  ```bash
   helm repo add jfrog https://charts.jfrog.io
   helm repo update
   helm pull jfrog/artifactory --version 107.84.14
   ```

b) Transfer the `artifactory-107.84.14.tgz` File :
   - Copy the `artifactory-107.84.14.tgz` file to a USB drive or other transfer medium to make it available on the machine in air-gap which has access to the K8s cluster.

c) 
   - **Dry Run**:
     ```bash
     helm upgrade --install $MY_HELM_RELEASE \
       -f ../artifactory/values-main.yaml \
       -f ../artifactory/values-artifactory.yaml \
       -f ../artifactory/artifactory-large.yaml \
       --namespace $MY_NAMESPACE \
       --set global.versions.artifactory="${RT_VERSION}" \
       --dry-run \
       ./artifactory-107.84.14.tgz
     ```
   - **Deploy**:
     ```bash
     helm upgrade --install $MY_HELM_RELEASE \
       -f ../artifactory/values-main.yaml \
       -f ../artifactory/values-artifactory.yaml \
       -f ../artifactory/artifactory-large.yaml \
       --namespace $MY_NAMESPACE \
       --set global.versions.artifactory="${RT_VERSION}" \
       ./artifactory-107.84.14.tgz
     ```

   **Note:** All the Java Options in `artifactory.javaOpts.other: >` in `artifactory-large.yaml` are applied as is 
   to the `shared.extraJavaOpts` in the final artifactory pod's system.yaml 
   as specified  https://github.com/jfrog/charts/blob/master/stable/artifactory/files/system.yaml#L51 i.e
   ```
     {{- if .other }}
       {{ .other }}
     {{- end }}
   ```
   `>` treats the multi-line string as a single line, folding line breaks into spaces.
   So the following :
   ```
   artifactory:
     javaOpts:
       other: >
         -XX:InitialRAMPercentage=40
         -XX:MaxRAMPercentage=65
         -Dartifactory.async.corePoolSize=80
         ...
   ```
   becomes:
   ```
   shared:
     extraJavaOpts: >
       -server  -Xss256k ....
       -XX:InitialRAMPercentage=40 -XX:MaxRAMPercentage=65 -Dartifactory.async.corePoolSize=80
       ...
   ```

6. **Verify Deployment**:
   ```bash
   kubectl get pods -o wide --namespace $MY_NAMESPACE
   kubectl describe pod "${MY_HELM_RELEASE}-artifactory-0" --namespace $MY_NAMESPACE
   kubectl logs -f "${MY_HELM_RELEASE}-artifactory-0" --all-containers=true --max-log-requests=10 --namespace $MY_NAMESPACE
   kubectl get nodes -o wide --namespace $MY_NAMESPACE
   ```

---

### **Experimental Steps**

1. **Set Hardcoded Keys**:
   Replace dynamic keys with hardcoded values (not recommended for production):
   ```bash
   export MASTER_KEY=c64231fe4324121f5de6a5834f35195bba0d857695f80c974c788cfdb4e70f09
   export JOIN_KEY=6dec6691f86d9e3de3cc4645f7a7eb33c3adc31071ec0d6567ad2069295c5397
   ```

2. **Merging Configuration Files**:
   ```bash
   python ../../scripts/merge_yaml_with_comments.py ../artifactory/values-main.yaml \
   ../artifactory/values-artifactory.yaml \
   ../artifactory/artifactory-large.yaml \
   ../artifactory/artifactory-large-extra-config.yaml -o artifactory_mergedfile.yaml
   ```
**Note:** This way of merging does not work well when  `extraEnvironmentVariables` is not a root element and
when you use "artifactory.customVolumes: |" and   "artifactory.customVolumeMounts: |" so skip it.

---

### **References**

- https://github.com/gitta-jfrog/kubernetes/blob/main/distribution/preStartCommandExample.yaml

- [Configure Other External Databases with Artifactory Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/use-an-external-database-with-artifactory-helm-installation)

- [Configure Artifactory to use Oracle](https://jfrog.com/help/r/jfrog-installation-setup-documentation/configure-artifactory-to-use-oracle)

- [How to resolve the oracle DB driver error with metadata service after upgrading to version 7.55.x and above in kubernetes with splitServicesToContainers](https://jfrog.com/help/r/artifactory-how-to-resolve-the-oracle-db-driver-error-with-metadata-service-after-upgrading-to-version-7-55-x-and-above-in-kubernetes-with-splitservicestocontainers)

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
The storageClass of this PVC is determined by `artifactory.storageClassName` and 
size is determined by `artifactory.persistence.size` 
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

**Note:** See more detail steps and troubelshooting  in [distribution/test_deploy_distribution_to_jf-gcp-env.md](distribution/test_deploy_distribution_to_jf-gcp-env.md)

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
I used [distribution-medium.yaml](https://github.com/jfrog/charts/blob/master/stable/distribution/sizing/distribution-medium.yaml)

Optional: 
```
python ../../scripts/merge_yaml_with_comments.py ../distribution/values-main.yaml \
../distribution/distribution-medium.yaml  -o distribution_mergedfile.yaml
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
-f ../distribution/distribution-medium.yaml \
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


