All the keys under "`artifactory.`" in 
https://github.com/jfrog/charts/blob/master/stable/artifactory/values.yaml in the `jfrog/artifactory` chart 
are in the "`artifactory.artifactory.`" when using the `jfrog/jfrog-platform` chart

For example: `artifactory.replicaCount`  will be referenced as ,`artifactory.artifactory.replicaCount`

To identify these parse the  https://github.com/jfrog/charts/blob/master/stable/artifactory/values.yaml
with "`artifactory.`" in https://yaml.vercel.app/

In additon to that some of the "`artifactory.artifactory.`" keys can be identified using "`artifactory.artifactory`"
in the https://github.com/jfrog/charts/blob/master/stable/jfrog-platform/values.yaml ( parse with https://yaml.vercel.app/)
For example:
```
{
  "unifiedSecretInstallation": true,
  "unifiedSecretPrependReleaseName": true,
  "replicaCount": 1,
  "migration": {
    "enabled": false
  },
  "persistence": {
    "size": "200Gi"
  }
}
```
---
## Deploying Artifactory via Helm using jfrog/jfrog-platform chart
Note: 
- All products include Distribution will be in the same namespace.
-  It is not recommended to use different databases for different charts. The JFrog platform chart is designed to work with a single database only. To install an external PostgreSQL database, you can use the Bitnami PostgreSQL chart. Then, deploy Artifactory and Distribution using their respective charts instead of the JFrog platform chart.

To clarify, the JFrog Platform chart supports one of two options:
1. All JFrog products work with the bundled PostgreSQL (`postgresql.enabled: true`), or
2. All products work with external databases (each product can be connected to a different external database).

The combination of using an external database for Artifactory and the embedded PostgreSQL for Distribution is not supported and will not be supported in the future.
- The `artifactory.artifactory.replicator` and  `artifactory.artifactory.integration`has been removed from the Helm chart since March or April 2024.

So replicator is not used for Distribution.

- From chart version 107.84.x, `setSecurityContext` has been renamed to `podSecurityContext`

- you can leave `jfrogURL` without configuration. The platform chart should be able to connect between the products. 
It is used for internal communication, and it is not the related to the custom base url.
- Fill in your own `imagePullSecrets` and `imageRegistry` in values/values-main.yaml
-  Pass your own ca.crt for artifactory if needed for ssl configuration. 

See prerequisite for ca.crt. [here](https://jfrog.com/help/r/jfrog-installation-setup-documentation/prerequisites-for-custom-tls-certificate) 
and [Establish TLS and Add Certificates in Helm Installation](https://jfrog.com/help/r/jfrog-installation-setup-documentation/establish-tls-and-add-certificates-in-helm-installation)
```
kubectl create secret tls my-cacert --cert=ca.crt --key=ca.private.key -n <namespace> 
```

- [Mounting Certificates Across All Products](https://jfrog.com/help/r/jfrog-platform-getting-started-with-the-jfrog-platform-helm-chart/mounting-certificates-across-all-products)
using `global.customCertificates`
---

### Here are the Steps to depoy Artifactory  using `jfrog/jfrog-platform` chart

1. Switch to  the folder with your values.yaml files
```
cd mySteps
```

2. Set the Following Environment variables:
```
export MY_NAMESPACE=ps-jfrog-platform
export MY_HELM_RELEASE=ps-jfrog-platform-release

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

export DB_SERVER=


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

d) Admin user password:
```
kubectl create secret generic art-creds --from-literal=bootstrap.creds='admin@*=password' -n $MY_NAMESPACE
 
```
e) Secret for GCP 
- [Google Cloud Storage Authentication Mechanism](https://jfrog.com/help/r/jfrog-installation-setup-documentation/google-cloud-storage-authentication-mechanism)
- [Advanced Storage Options](https://jfrog.com/help/r/jfrog-installation-setup-documentation/advanced-storage-options) > "Google Storage"

Note: IMPORTANT: The file must be called `"gcp.credentials.json"` because this is used later as the secret key!
```
kubectl create secret generic artifactory-gcp-creds --from-file=./gcp.credentials.json -n $MY_NAMESPACE
```
**For GCP Storage:**
```
envsubst < ./custom-binarystore-gcp.tmpl > custom-binarystore.yaml

kubectl apply -f custom-binarystore.yaml -n $MY_NAMESPACE
```

**For  awsS3V3 connection details.**
 For IAM roles see [here](https://jfrog.com/help/r/artifactory-how-to-configure-an-aws-s3-object-store-using-an-iam-role-instead-of-an-iam-user)

We recommend using the [S3 Direct Upload Template (Recommended)](https://jfrog.com/help/r/jfrog-installation-setup-documentation/s3-direct-upload-template-recommended)

5. Generate the final `3_mergedfile.yaml` :
Pick the Artifactory sizing configuration from https://github.com/jfrog/charts/blob/master/stable/artifactory/sizing

I will use artifactory-small.yaml and artifactory-small-extra-config.yaml and nest it under "artifactory:"
```
python ../nest_yaml_with_comments.py artifactory-small.yaml \
 artifactory -o nested-artifactory.yaml 

python ../nest_yaml_with_comments.py artifactory-small-extra-config.yaml \
 artifactory -o nested-artifactory-extra-config.yaml 
```
Pick the https://github.com/jfrog/charts/blob/master/stable/distribution/sizing/distribution-medium.yaml and  
nest it under "distribution:"

```
python ../nest_yaml_with_comments.py /Users/sureshv/myCode/github-jfrog/charts/stable/distribution/sizing/distribution-medium.yaml \
 distribution -o nested-distrubution.yaml
```

Next merge all of them for Artifactory and Distribution:
```
python ../merge_yaml_with_comments.py ../values/values-main.yaml \
../values/values-artifactory.yaml \
 nested-artifactory.yaml nested-artifactory-extra-config.yaml nested-distrubution.yaml -o 3_mergedfile_1.yaml
```

6. Verify you have the helm  chart you need:
```
helm repo update
helm search repo jfrog-chart
```

helm pull jfrog/artifactory --version 10.0.0

7. First do a Dry run:
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set global.versions.artifactory="${RT_VERSION}" \
--dry-run
```

8. Deploy Artifactory without --dry-run :
```
helm  upgrade --install $MY_HELM_RELEASE \
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform  \
--set global.versions.artifactory="${RT_VERSION}"
```
**Note:**
`"splitServicesToContainers"` should be true unless there is no other option. We are going to deprecate this flag in the future. The best practice is to run the services as separated containers.

---
### Troubleshooting:
If using GCP for the Postgres Database Server :
Do steps from 
- [Connect using the Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/connect-auth-proxy)

- https://github.com/GoogleCloudPlatform/cloud-sql-proxy

I did following from my macbook:
```
gcloud auth login

curl -o cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.darwin.amd64
./cloud_sql_proxy -instances=support-prod-157422:us-east1:samk-db-1=tcp:5432

```
Connect to your DB from psql client at  127.0.0.1:5432 from your mac
 
---
To check connection from the namespace in the K8s cluster to the external Postgres:

```
export DB_SERVER=35.196.8.206
export RT_DATABASE_USER=artifactory
export RT_DATABASE_PASSWORD=password
export ARTIFACTORY_DB=sureshv-helm-ha-db

kubectl run postgres-client --rm --tty -i --restart='Never' --namespace $MY_NAMESPACE \
--image postgres --env="PGPASSWORD=$RT_DATABASE_PASSWORD" \
--command -- psql --host $DB_SERVER -U $RT_DATABASE_USER -d $ARTIFACTORY_DB -c "SELECT version();"

kubectl exec -it postgres-client --namespace $MY_NAMESPACE -- bash
PGPASSWORD="your_password" psql -h <POSTGRES_HOST> -p 5432 -U <POSTGRES_USER> -d <POSTGRES_DB> -W
PGPASSWORD="your_password" psql -h 35.196.8.206 -p 5432 -U artifactory -d sureshv-helm-ha-db -W
```
Or
#### Deploy an Alpine Pod
Step 1: Deploy a Pod with Alpine
```
kubectl run alpine --image=alpine --restart=Never --namespace=$MY_NAMESPACE -- sleep 3600

```
.
Step 2: Access the Pod

    ```sh
    kubectl exec -it alpine --namespace=$MY_NAMESPACE -- sh
    ```

3. Install PostgreSQL client inside the BusyBox pod:

    ```sh

    apk add --no-cache postgresql-client
    ```

4. Connect to PostgreSQL database:

    ```sh
    psql -h <POSTGRES_HOST> -U <POSTGRES_USER> -d <POSTGRES_DB> -W
    ```

5. Verify the connection by running an SQL command:

    ```sql
    SELECT version();
    ```

This approach ensures that you can interact with your PostgreSQL database from within a Kubernetes cluster using a minimal BusyBox pod.

---

Check the deployment using kubectl:
```
kubectl get pods -o wide --namespace $MY_NAMESPACE
kubectl get nodes -o wide --namespace $MY_NAMESPACE

kubectl get pods -w --namespace ps-jfrog-platform
kubectl get svc --namespace ps-jfrog-platform -w ps-jfrog-platform-release-artifactory-nginx
$ export SERVICE_HOSTNAME=$(kubectl get svc --namespace ps-jfrog-platform ps-jfrog-platform-release-artifactory-nginx --template "{{ range (index .status.loadBalancer.ingress 0) }}{{ . }}{{ end }}")
$ echo http://$SERVICE_HOSTNAME/

- Method 2: Port Forwarding

  $ kubectl port-forward --namespace ps-jfrog-platform svc/ps-jfrog-platform-release-artifactory-nginx 8080:8080 &
  $ echo http://localhost:8080/

kubectl logs ps-jfrog-platform-release-artifactory-0 --namespace ps-jfrog-platform -c <container-name>
Defaulted container "router" out of: router, frontend, metadata, event, access, observability, artifactory, delete-db-properties (init), access-bootstrap-creds (init), copy-system-configurations (init)

kubectl get pods <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[*].name}{"\t"}{.status.containerStatuses[*].state}{"\n"}'
kubectl get pods ps-jfrog-platform-release-artifactory-0  --namespace ps-jfrog-platform  -o jsonpath='{.status.containerStatuses[*].name}{"\t"}{.status.containerStatuses[*].state}{"\n"}'


kubectl logs ps-jfrog-platform-release-artifactory-0  --namespace ps-jfrog-platform -c artifactory

kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform
kubectl logs -f ps-jfrog-platform-release-artifactory-0 -c access --namespace ps-jfrog-platform
kubectl logs -f ps-jfrog-platform-release-artifactory-0 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform
kubectl logs -f ps-jfrog-platform-release-artifactory-0 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform | grep -i jfac

kubectl logs -f ps-jfrog-platform-release-artifactory-nginx-596cfb8b4-s6cj9 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/artifactory/var/etc/security/master.key
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/router/var/etc/security/join.key
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- "ls -al /opt/jfrog/artifactory/var/etc/artifactory"
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- cat /opt/jfrog/artifactory/var/etc/artifactory/gcp.credentials.json

kubectl describe pod ps-jfrog-platform-release-artifactory-0 | grep CrashLoopBackOff -B 20

kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c artifactory --namespace ps-jfrog-platform -- sh
kubectl exec -it ps-jfrog-platform-release-artifactory-0 -c access --namespace ps-jfrog-platform -- sh

Could you please run the below command on the Artifactory pod again and share the output with me?
curl http://localhost:8082/router/api/v1/system/health
curl http://localhost:8046/router/api/v1/system/readiness

kubectl get secret masterkey-secret -o json -n $MY_NAMESPACE | jq -r '.data."artifactory.lic"' | base64 --decode

bash ./decode-secret.sh $MY_NAMESPACE masterkey-secret master-key

```

---
To start over by deleting everything do the following:

```
helm uninstall $MY_HELM_RELEASE -n $MY_NAMESPACE
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

helm  upgrade --install $MY_HELM_RELEASE \
-f 3_mergedfile_1.yaml \
--namespace $MY_NAMESPACE jfrog/jfrog-platform 


kubectl get nodes -o wide --namespace $MY_NAMESPACE
kubectl get svc --namespace $MY_NAMESPACE
kubectl logs -f ps-jfrog-platform-release-artifactory-0 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform
kubectl logs -f ps-jfrog-platform-release-distribution-0 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform

kubectl describe pod ps-jfrog-platform-release-distribution-0 --namespace ps-jfrog-platform
```

List all StatefulSets in the $MY_NAMESPACE namespace:
```
kubectl get statefulsets -n $MY_NAMESPACE
```
View the YAML definition of the  StatefulSet:
```
kubectl get statefulset ps-jfrog-platform-release-artifactory -n $MY_NAMESPACE -o yaml  > statefulset.ps-jfrog-platform-release-artifactory.yaml

kubectl describe statefulset ps-jfrog-platform-release-distribution -n $MY_NAMESPACE

kubectl get statefulset  ps-jfrog-platform-release-distribution -n $MY_NAMESPACE -o yaml > statefulset.ps-jfrog-platform-release-distribution.yaml
```
List the Pods managed by the artifactory StatefulSet:
```
kubectl get pods -l app=artifactory -n $MY_NAMESPACE

NAME                                                           READY   STATUS    RESTARTS      AGE
ps-jfrog-platform-release-artifactory-0                        0/7     Running   0             103s
ps-jfrog-platform-release-artifactory-nginx-746c545c57-t2t9f   0/1     Running   1 (68s ago)   103s
```
List the Pods managed by the distribution StatefulSet:
```
kubectl get pods -l app=distribution -n $MY_NAMESPACE
```
---

