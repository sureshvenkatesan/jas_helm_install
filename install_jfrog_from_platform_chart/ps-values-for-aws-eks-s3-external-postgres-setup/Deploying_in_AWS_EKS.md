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

When deploying artifactory via the JFrog platform chart , the service account's name  for the Artifactory pods takes the format of `{JFROG_PLATFORM_NAMESPACE}:{JFROG_PLATFORM_NAME}-artifactory` .

For example in your K8s cluster if  you have:
```text
export JFROG_PLATFORM_NAMESPACE=ps-jfrog-platform
export JFROG_PLATFORM_NAME=ps-jfrog-platform-release
```

Then the service account takes the format:
`"system:serviceaccount:ps-jfrog-platform:ps-jfrog-platform-release-artifactory"`

---

Below is the **visual sequence (flowchart-style)** that shows **every step** needed to successfully install **JFrog Artifactory on EKS** using **IRSA + S3 + ALB**, with the **correct trust and permissions policies** and  where the artifactory service account naming rule fits in the flow.

Detailed instructions on IRSA can be found in the following documentation:

- [Enabling IAM Roles for Service Accounts on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)
- [Associating a Service Account with a Role on Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

Detailed instructions on Application Load Balancer as Ingress gateway setup can be found in the following documentation:
- https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- or https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/ ( mentioned in the blog - [A Guide to Installing the JFrog Platform on Amazon EKS](https://jfrog.com/blog/install-artifactory-on-eks/))

Please be aware that if you encounter difficulties, especially if your cluster was established using Infrastructure as Code (IAC) such as CDK, you might need to follow [this guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting_iam.html#security-iam-troubleshoot-cannot-view-nodes-or-workloads) to gain the necessary privileges for manually executing the equivalent actions of the aforementioned eksctl command within your cluster.

If you find yourself in a situation where you need to manually create the kube-system role, you can utilize the information provided in this guide: [Link](https://stackoverflow.com/questions/65934606/what-does-eksctl-create-iamserviceaccount-do-under-the-hood-on-an-eks-cluster).

As per the blog - [A Guide to Installing the JFrog Platform on Amazon EKS](https://jfrog.com/blog/install-artifactory-on-eks/)) for the ALB steps it refers to
[AWS Load Balancer instructions here](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/) -> 
[Install AWS Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html) which has a note on CRDs:

✅ **If this is the very first time** you’re installing ALBC in the cluster,
then Helm will **install CRDs automatically** (because it behaves as `helm install`).

❌ **If you already had it installed before** (so this is an upgrade run),
then Helm behaves as `helm upgrade` and **will not reinstall CRDs** 

To be safe and version-pinned:

1. **Always pre-apply the CRDs** explicitly before running Helm—especially if you’re using `--install`.

    ```bash
    kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=<TAG>"
    ```
For example, for v2.6.2:
   ```bash
   kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=v2.6.2"
   ```
2. Then run your `helm upgrade --install` as normal.

That way, regardless of whether it’s the first install or an upgrade,
your CRDs are always at the correct version.


## 🧭 Complete Visual Sequence (with JFrog service account naming)

```
START
 │
 │
 ├── ① Prepare your AWS & EKS environment
 │       - EKS cluster running
 │       - kubectl + helm + aws CLI configured
 │       - eksctl installed
 │
 ├── ② Enable OIDC provider (IRSA)
 │       eksctl utils associate-iam-oidc-provider \
 │         --cluster <CLUSTER_NAME> --region <REGION> --approve
 │
 ├── ③ Determine JFrog service account name
 │       # By default:
 │       # {JFROG_PLATFORM_NAMESPACE}:{JFROG_PLATFORM_NAME}-artifactory
 │
 │       export JFROG_PLATFORM_NAMESPACE=ps-jfrog-platform
 │       export JFROG_PLATFORM_NAME=ps-jfrog-platform-release
 │
 │       ⇒ service account name:
 │          system:serviceaccount:ps-jfrog-platform:ps-jfrog-platform-release-artifactory
 │
 │       (This value must match exactly in your trust policy Condition)
 │
 ├── ④ Create IAM role for Artifactory
 │       ├── trust.json  ← who can assume (use service account above)
 │       └── s3-permissions.json  ← what actions allowed
 │
 │       aws iam create-role \
 │         --role-name ArtifactoryS3Role \
 │         --assume-role-policy-document file://trust.json
 │
 │       aws iam put-role-policy \
 │         --role-name ArtifactoryS3Role \
 │         --policy-name ArtifactoryS3Access \
 │         --policy-document file://s3-permissions.json
 │
 ├── ⑤ Create Kubernetes namespace & license secret
 │       kubectl create namespace ps-jfrog-platform
 │       kubectl -n ps-jfrog-platform create secret generic artifactory-license \
 │         --from-file==artifactory.lic=/Users/sureshv/Documents/Test_Scripts/helm_upgrade/licenses/art.lic
 │
 ├── ⑥ Prepare Helm values.yaml (IRSA + S3 filestore)
 │       - Use the correct serviceAccount name (matches above)
 │       - Annotate with IAM role ARN
 │
 │       artifactory:
 │         serviceAccount:
 │           create: true
 │           name: ps-jfrog-platform-release-artifactory
 │           annotations:
 │             eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/ArtifactoryS3Role
 │         artifactory:
 │           persistence:
 │             type: s3-storage-v3-direct
 │             awsS3V3:
 │               bucketName: davidro-binstore
 │               endpoint: s3.<REGION>.amazonaws.com
 │               region: eu-west-3
 │               path: artifactory/filestore
 │               maxConnections: 50
 │               # in order to not specify identity and credential fields
 │               useInstanceCredentials: true
 │               testConnection: true
 │
 ├── ⑥a Configure ALB via Ingress in values.yaml 
 │
 ├── ⑦ Create IAM + IRSA for AWS Load Balancer Controller
 │       curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.2/docs/install/iam_policy.json
 │       aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy \
 │         --policy-document file://iam_policy.json
 │
 │       eksctl create iamserviceaccount \
 │         --cluster <CLUSTER_NAME> \
 │         --namespace kube-system \
 │         --name aws-load-balancer-controller \
 │         --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
 │         --override-existing-serviceaccounts --approve
 │
 ├── ⑧ Install the AWS Load Balancer Controller via Helm
 │       helm repo add eks https://aws.github.io/eks-charts
 │       helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
 │         -n kube-system \
 │         --set clusterName=<CLUSTER_NAME> \
 │         --set serviceAccount.create=false \
 │         --set serviceAccount.name=aws-load-balancer-controller \
 │         --set region=<REGION> \
 │         --set vpcId=<VPC_ID>
 │
 ├── ⑨ Add JFrog Helm repo
 │       helm repo add jfrog https://charts.jfrog.io
 │       helm repo update
 │   
 │ 
 │ 
 ├── ⑩ Install JFrog Platform (uses the ingress to create ALB - See "Step 3: Configure the JFrog Platform Helm Chart" in blog 
 │       https://jfrog.com/blog/install-artifactory-on-eks/
 │ 
 │       helm upgrade --install jfrog-platform jfrog/jfrog-platform \
 │         -n ps-jfrog-platform -f values.yaml
 │
 ├── ⑪ Verify Deployment
 │       kubectl get pods -n ps-jfrog-platform
 │       kubectl get ingress -n ps-jfrog-platform
 │
 ├── ⑫ Route 53 DNS → ALB DNS
 │       - Copy ALB address from Ingress
 │       - Create CNAME record pointing your domain to it
 │
 └── DONE ✅
```

---

## 🧩 Key Files

### 🔹 `trust.json` (for `aws iam create-role`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<ISSUER_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<REGION>.amazonaws.com/id/<ISSUER_ID>:aud": "sts.amazonaws.com",
          "oidc.eks.<REGION>.amazonaws.com/id/<ISSUER_ID>:sub": "system:serviceaccount:{JFROG_PLATFORM_NAMESPACE}:{JFROG_PLATFORM_NAME}-artifactory"
        }
      }
    }
  ]
}
```

---

### 🔹 `s3-permissions.json` (for `aws iam put-role-policy`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketLevel",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::davidro-binstore"
    },
    {
      "Sid": "ObjectLevel",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::davidro-binstore/*"
    }
  ]
}
```

or

In a Dev Jfrog deployment you can Create an IAM role that the Artifactory's pods service account can take on, equipped with a policy that bestows upon them the privileges to list, read from and write i.e the "Action": "s3:*" to the 'davidro-binstore' S3 bucket. This bucket is intended to serve as the filestore for Artifactory.

```
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

---

### 🔹 `values.yaml` (Artifactory Helm config)

```yaml
global:
  jfrogUrl: '{{ include "jfrog-platform.jfrogUrl" . }}'
  jfrogUrlUI: "https://artifactory.example.com"

artifactory:
  serviceAccount:
    create: true
    # name: {JFROG_PLATFORM_NAMESPACE}:{JFROG_PLATFORM_NAME}-artifactory
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/ArtifactoryS3Role
    automountServiceAccountToken: true

  artifactory:
    license:
      secret: artifactory-license
      dataKey: artifactory.lic
    persistence:
      type: s3-storage-v3-direct
      awsS3V3:
        bucketName: davidro-binstore
        endpoint: s3.eu-west-3.amazonaws.com
        region: eu-west-3
        useInstanceCredentials: true
        testConnection: true

  ingress:
    enabled: true
    routerPath: /
    artifactoryPath: /artifactory/
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-2016-08
      # name of the future ALB
      alb.ingress.kubernetes.io/load-balancer-name: yann-demo-lab-eks
      # consume the TLS certificates in AWS Cert Manager
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:<AWS_REGION>:<AWS_ACCOUNT_ID>:certificate/<CERT_ID>
```

---

