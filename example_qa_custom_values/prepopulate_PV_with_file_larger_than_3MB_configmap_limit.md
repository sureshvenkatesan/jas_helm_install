
# Prepopulate a Persistent Volume with a File for JFrog Artifactory Helm Deployment

This guide demonstrates how to prepopulate a Persistent Volume (PV) with a file from your Mac and use it in a JFrog Artifactory deployment on a Kubernetes cluster. The steps include creating a PV, copying the file from your Mac, and configuring the Artifactory Helm chart to use the PV.

## Prerequisites

- Access to a Kubernetes cluster (e.g., GKE).
- Helm installed and configured to manage the Artifactory deployment.
- `kubectl` installed and configured to interact with your cluster.
- The file to be prepopulated (`instantclient-basic-linux.x64-21.11.0.0.0dbru.zip`) available on your Mac.

## Steps

### 1. Create a Persistent Volume (PV) and Persistent Volume Claim (PVC)

First, define and apply a Persistent Volume (PV) and Persistent Volume Claim (PVC) in your Kubernetes cluster.

Create `pv.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: artifactory-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: "/mnt/data/artifactory"
```

Create `pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: artifactory-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Apply the configurations:

```bash
kubectl apply -f pv.yaml
kubectl apply -f pvc.yaml
```

### 2. Deploy a Temporary Pod to Prepopulate the PV

Create a temporary pod that mounts the PVC and runs a `busybox` container to keep it alive while you copy the file.

Note: If you are deploying in an airgap environment and want to use your own minimal docker image instead of 
`busybox` and need a `imagePullSecrets` refer to the example in
[Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#create-a-pod-that-uses-your-secret)

Create `copy-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: copy-pod
spec:
  imagePullSecrets:
  - name: regcred
  containers:
    - name: copy-container
      image: busybox
      command: [ "sleep", "3600" ] # Keep the pod running for an hour
      volumeMounts:
        - mountPath: "/mnt/data"
          name: artifactory-pv
  volumes:
    - name: artifactory-pv
      persistentVolumeClaim:
        claimName: artifactory-pvc
  restartPolicy: Never
```

Apply the configuration:

```bash
kubectl apply -f copy-pod.yaml
```
Instead I have all in a single [prepopulate_pv_with_custom_oracle_instantclient_type2_driver_zip.yaml](prepopulate_pv_with_custom_oracle_instantclient_type2_driver_zip.yaml)

```bash
kubectl apply -f prepopulate_pv_with_custom_oracle_instantclient_type2_driver_zip.yaml -n $MY_NAMESPACE
```

### 3. Copy the File from Your Mac to the Pod

Use `kubectl cp` to copy the file from your Mac to the running pod:

### Install `pv` on macOS

If `pv` is not already installed, you can install it using Homebrew:

```bash
brew install pv
```

#### Copying a File with Progress Display

Since `kubectl cp` does not natively support progress display, we can use `pv` in combination with `tar` and `kubectl exec` to achieve this.

#### Command to Display Progress

```bash
tar cf - instantclient-basic-linux.x64-21.11.0.0.0dbru.zip | pv | kubectl exec -i -n $MY_NAMESPACE copy-pod -- tar xf - -C /mnt/data/
```

#### Explanation

- **`tar cf - instantclient-basic-linux.x64-21.11.0.0.0dbru.zip`**: This command creates a tar archive from the file and writes it to stdout.
- **`pv`**: This command monitors the progress of the data stream, displaying a progress bar, the amount of data transferred, and the transfer rate.
- **`kubectl exec -i`**: This command pipes the tar data into the pod where it is extracted into the `/mnt/data/` directory.

#### Example Output

As the file is being copied, you will see output similar to the following:

```text
50.0MiB 0:00:05 [9.00MiB/s] [=========================>        ] 66% ETA 0:00:02
```

This output provides real-time feedback on the copy operation, making it easy to track the progress of large file transfers.

Or
Just use
```bash
# Copy the file to the pod
kubectl cp instantclient-basic-linux.x64-21.11.0.0.0dbru.zip copy-pod:/mnt/data/
```

Verify the file was copied successfully:

```bash
kubectl exec -it copy-pod -n $MY_NAMESPACE -- ls /mnt/data/
```

### 4. Mount the PV in Your Artifactory Deployment

Update your Artifactory Helm chart’s `values.yaml` file to mount the PV in the Artifactory pods.

Edit `values-artifactory.yaml`:

```yaml
artifactory:
  customVolumes:
    - name: artifactory-pv
      persistentVolumeClaim:
        claimName: artifactory-pvc

  customVolumeMounts:
    - name: artifactory-pv
#      mountPath: /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/
      mountPath: /tmp/zips/
      subPath: instantclient-basic-linux.x64-21.11.0.0.0dbru.zip
```

Deploy or upgrade the Helm release:

```bash
helm upgrade --install artifactory jfrog/artifactory -f values.yaml
```

### 5. Clean Up the Temporary Pod

After the file is copied and verified, delete the temporary pod:

```bash
kubectl delete pod copy-pod
```

## Conclusion

By following these steps, you can prepopulate a Persistent Volume with a file from your Mac and use it across all replicas in a JFrog Artifactory deployment. This approach ensures that the file is available to all pods without requiring manual intervention when scaling the deployment.

