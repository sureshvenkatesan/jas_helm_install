## Deploying Distribution via Helm using `jfrog/distribution` chart

1. Switch to  the folder with your values.yaml files
```
cd /Users/sureshv/myCode/github-sv/jas_helm_install/install_distribution_from_distribution_chart/mysteps
```

2. Set some more environment variables:
```
export DIST_VERSION=2.25.1
export JFROG_URL="https://35.185.121.172" 
export MY_DIST_HELM_RELEASE=distribution-release
```

3. Pick the Distribution sizing template from https://github.com/jfrog/charts/tree/master/stable/distribution/sizing .
I used [distrubution-medium.yaml](https://github.com/jfrog/charts/blob/master/stable/distribution/sizing/distrubution-medium.yaml)

```
python ../../scripts/merge_yaml_with_comments.py ../values/values-main.yaml \
/Users/sureshv/myCode/github-jfrog/charts/stable/distribution/sizing/distrubution-medium.yaml  -o 3_mergedfile.yaml
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
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE \
--set distribution.joinKey="${JOIN_KEY}" \
--set distribution.jfrogUrl="{JFROG_URL}" \
--set global.versions.distribution="${DIST_VERSION}" \
--dry-run \
./distribution-102.25.1.tgz 
```

6. Next run without the --dry-run
 
```
helm upgrade --install $MY_DIST_HELM_RELEASE \
-f 3_mergedfile.yaml \
--namespace $MY_NAMESPACE \
--set distribution.joinKey="${JOIN_KEY}" \
--set distribution.jfrogUrl="${JFROG_URL}" \
--set global.versions.distribution="${DIST_VERSION}" \
./distribution-102.25.1.tgz  
```
---
### Check the node external IP , pod status and logs
```
kubectl logs -f ps-distribution-release-0 --all-containers=true --max-log-requests=10 --namespace ps-jfrog-platform
kubectl describe pod ps-distribution-release-0 --namespace $MY_NAMESPACE
kubectl get pods -o wide --namespace $MY_NAMESPACE
kubectl get nodes -o wide --namespace $MY_NAMESPACE
```
---
### Troubleshooting:
During Distribution startup if it cannot connect to the $JFROG_URL/access because of cert verify issue:

```
2024-07-31T03:56:46.446Z [jfrou] [INFO ] [30b08b4b4ccb3f94] [join_executor.go:174          ] [main                ] [] - Cluster join: Retry 100: Access Service ping failed, will retry. Error: do secure: Get "https://35.185.121.172/access/api/v1/system/ping": tls: failed to verify certificate: x509: cannot validate certificate for 35.185.121.172 because it doesn't contain any IP SANs
```

Upon reviewing your certificate, we noticed it was defined with a hostname. When we pinged the hostname, it pointed to a different IP address.

To resolve this issue, you will need to obtain the correct certificate and verify that the domain name specified in the certificate resolves correctly.

---
