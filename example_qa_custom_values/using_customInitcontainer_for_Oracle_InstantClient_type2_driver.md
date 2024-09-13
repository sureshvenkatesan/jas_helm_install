# Oracle Instant Client Setup with InitContainer in Artifactory Pod

The Oracle Instant Client Type2 driver ([instantclient-basic-linux.x64-21.11.0.0.0dbru.zip](https://download.oracle.com/otn_software/linux/instantclient/2111000/instantclient-basic-linux.x64-21.11.0.0.0dbru.zip)) is licensed under the 
GPL, and we are not permitted to distribute it (with the exception of the PostgreSQL driver).  Therefore JFrog cannot  
build a custom Artifactory Docker image that includes this driver .

### Proposed Solution

We suggest creating a custom Docker image (based on either **BusyBox** or **artlab.ocp4.appdev.jfrog.org/ubi9/ubi-minimal:9.4.949**) that includes the Oracle Instant Client `instantclient-basic-linux.x64-21.11.0.0.0dbru.zip`. This image will be used in an `initContainer` to copy the file into the Artifactory pod's directory before the main container process starts.

## Steps to Implement the Solution

### 1. Build a Custom BusyBox Image or UBI Minimal Image

We will create a Docker image based on **BusyBox** or **UBI Minimal** that includes the Oracle Instant Client zip file.

#### Dockerfile for Custom BusyBox Image

```Dockerfile
# Use BusyBox as the base image
FROM busybox:1.31

# Copy the instantclient zip file into the image
COPY instantclient-basic-linux.x64-21.11.0.0.0dbru.zip /tmp/zips/

# Define the default command
CMD ["sh"]
```

#### Dockerfile for Custom UBI Minimal Image

```Dockerfile
# Use UBI Minimal as the base image
FROM artlab.ocp4.appdev.jfrog.org/ubi9/ubi-minimal:9.4.949

# Copy the instantclient zip file into the image
COPY instantclient-basic-linux.x64-21.11.0.0.0dbru.zip /tmp/zips/

# Define the default command
CMD ["sh"]
```

### 2. Steps to Build the Docker Image

1. **Create a directory** and place both the `instantclient-basic-linux.x64-21.11.0.0.0dbru.zip` file and the `Dockerfile` inside it.

2. **Build the Docker image**:

    ```bash
    docker build -t custom-ubi-minimal:instantclient .
    ```

3. **Tag the Docker image** for your container registry:

    ```bash
    docker tag custom-ubi-minimal:instantclient your-repo/custom-ubi-minimal:instantclient21.11.0.0.0
    ```

4. **Push the Docker image** to your container registry:

    ```bash
    docker push your-repo/custom-ubi-minimal:instantclient21.11.0.0.0
    ```

   Replace `your-repo` with the appropriate repository you're using.

### 3. Use the Custom Image in the InitContainer

Once the image is built and pushed to the container registry, you will modify the `values-artifactory.yaml` to use this custom Docker image in an `initContainer`. The `initContainer` will copy the `instantclient-basic-linux.x64-21.11.0.0.0dbru.zip` file into the Artifactory pod’s directory before the main Artifactory process starts.

#### Modify `values-artifactory.yaml`

1. Use the custom image in the initContainer:
See `artifactory.customInitContainers` in [artifactory/values-artifactory_w_customInitContainer_for_oci_type2.yaml](artifactory/values-artifactory_w_customInitContainer_for_oci_type2.yaml)

  

2. Add appropriate volume mounts if needed. For more details on configuring custom InitContainers, refer to :
- [JFrog 
   Helm chart documentation](https://github.com/gitta-jfrog/kubernetes/blob/main/artifactory-ha/customInitContainerExample.yaml) 
- [How to configure customInitContainers in JFrog Helm charts?](https://jfrog.com/help/r/how-to-configure-custominitcontainers-in-jfrog-helm-charts-using-custom-values-yaml-file/how-to-configure-custominitcontainers-in-jfrog-helm-charts)
- 

### 4. Deploy or Upgrade the Helm Chart

After modifying the `values-artifactory.yaml`, you can deploy or upgrade your Helm chart with the following command:

a) First do a Dry run:
```
helm upgrade --install $MY_HELM_RELEASE \
-f ../artifactory/values-main.yaml \
-f ../artifactory/values-artifactory_w_customInitContainer_for_oci_type2.yaml \
-f ../artifactory/artifactory-large.yaml \
-f ../artifactory/artifactory-large-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
--dry-run \
./artifactory-107.84.14.tgz
```
b). Next run without the --dry-run
```
helm upgrade --install $MY_HELM_RELEASE \
-f ../artifactory/values-main.yaml \
-f ../artifactory/values-artifactory_w_customInitContainer_for_oci_type2.yaml \
-f ../artifactory/artifactory-large.yaml \
-f ../artifactory/artifactory-large-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
./artifactory-107.84.14.tgz
```

### Conclusion

This approach allows us to include the Oracle Instant Client in a custom Docker image, using an `initContainer` to copy the driver into the Artifactory pod without violating licensing constraints. By separating the custom Oracle Instant Client image from the Artifactory image, we can comply with distribution limitations while automating the deployment process.
``` 
