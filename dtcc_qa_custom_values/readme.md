## For artifactory:

1.Switch to the work folder
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/dtcc_qa_custom_values/mysteps
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
Example 

d) Admin user password:
```
kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=password' -n $MY_NAMESPACE
 
```

5. 
   Pick the Artifactory sizing configuration from https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing

I will use [artifactory-large.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-large.yaml) and 
[artifactory-large-extra-config.yaml](https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing/artifactory-large-extra-config.yaml)

Optional:  merge all of them for Artifactory:
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

---

## Deploying Distribution via Helm using `jfrog/distribution` chart

1. Switch to the work folder
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/dtcc_qa_custom_values/mysteps
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
 
