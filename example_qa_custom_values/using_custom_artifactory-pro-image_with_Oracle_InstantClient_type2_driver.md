# Oracle Instant Client Setup with Custom artifactory-pro image

The Oracle Instant Client Type2 driver ([instantclient-basic-linux.x64-21.11.0.0.0dbru.zip](https://download.oracle.com/otn_software/linux/instantclient/2111000/instantclient-basic-linux.x64-21.11.0.0.0dbru.zip)) is licensed under the 
GPL, and we are not permitted to distribute it (with the exception of the PostgreSQL driver). Therefore JFrog cannot  
build a custom Artifactory Docker image that includes this driver .

### Proposed Solution

We suggest that you create a custom  `releases-docker.jfrog.io/jfrog/artifactory-pro image`  that includes the Oracle 
Instant Client `instantclient-basic-linux.x64-21.11.0.0.0dbru.zip`. 

## Steps to Implement the Solution

### 1. Build a Custom `releases-docker.jfrog.io/jfrog/artifactory-pro` image`


#### Dockerfile

```Dockerfile
FROM releases-docker.jfrog.io/jfrog/artifactory-pro:7.84.14
USER root
RUN mkdir -p /opt/oracle/
COPY instantclient-basic-linux.x64-21.11.0.0.0dbru.zip /opt/oracle/
RUN mkdir -p /opt/oracle/instantclient && cd /opt/oracle/instantclient && \
    unzip -j ../instantclient-basic-linux.x64-21.11.0.0.0dbru.zip && \
    cp /opt/jfrog/artifactory/app/artifactory/libaio/* ./ && \
    chown -R artifactory:artifactory /opt/oracle/instantclient
USER artifactory
ENV LD_LIBRARY_PATH="/opt/oracle/instantclient"
```
**Note:** used "/opt/oracle/instantclient" instead of "/opt/oracle/instantclient_21_11" in case you want to upgrade 
the driver in future

### 2. Steps to Build the Docker Image

1. **Create a directory** and place both the `instantclient-basic-linux.x64-21.11.0.0.0dbru.zip` file and the `Dockerfile` inside it.

2. **Build the Docker image**:

```bash
docker build -t sv-artifactory-pro:v7.84.14 .
```

3. **Tag the Docker image** for your container registry:

```bash
docker tag sv-artifactory-pro:v7.84.14 psazuse.jfrog.io/<your-repo>/sv-artifactory-pro:v7.84.14
```

4. **Push the Docker image** to your container registry:

```bash
docker push psazuse.jfrog.io/<your-repo>/sv-artifactory-pro:v7.84.14
```

Replace `your-repo` with the appropriate repository you're using.

### 3. Use the Custom Image 

Once the image is built and pushed to the container registry, you will modify the `values-artifactory.yaml` to use this custom Docker image 

#### Modify `values-artifactory.yaml`

1. Use the custom image  as below:
```artifactory:
  name: artifactory
  image:
    registry: psazuse.jfrog.io
    repository: sv-test-docker/sv-artifactory-pro
    tag: v7.84.14
  preStartCommand: "mkdir -p /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/; cp /opt/oracle/instantclient/ojdbc8.jar /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/"
  extraEnvironmentVariables:
    - name: LD_LIBRARY_PATH
      value: /opt/oracle/instantclient:/opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib
```
See  in [artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml](artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml)

**Note:** The `preStartCommand` and `extraEnvironmentVariables` are required.

Also if you are pulling the `artifactory-pro` image from a  docker registry for example `psazuse.jfrog.io` that is different from the 
`global.imageRegistry` then set that value to an empty string as shown  in [../install_artifactory_from_artifactory_chart/values/values-main.yaml#L23](../install_artifactory_from_artifactory_chart/values/values-main.yaml#L23) and [artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml#L94-L97](artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml#L94-L97) which actually uses Oracle database for persistence.

Note: In my test lab in GCP since I used postgres database for artifactory persistence I tested the oracle driver mounting  using [../install_artifactory_from_artifactory_chart/values/values-artifactory-gcp-gstorage-postgres-w-oci-type2driver-in-rt
-image.yaml#L88-L90](../install_artifactory_from_artifactory_chart/values/values-artifactory-gcp-gstorage-postgres-w-oci-type2driver-in-rt-image.yaml#L88-L90)



### 4. Deploy or Upgrade the Helm Chart

After modifying the `values-artifactory.yaml`, you can deploy or upgrade your Helm chart with the following command:

a) First do a Dry run:
```
helm upgrade --install $MY_HELM_RELEASE \
-f ../artifactory/values-main.yaml \
-f ../artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml \
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
-f ../artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml \
-f ../artifactory/artifactory-large.yaml \
-f ../artifactory/artifactory-large-extra-config.yaml \
--namespace $MY_NAMESPACE \
--set global.versions.artifactory="${RT_VERSION}" \
./artifactory-107.84.14.tgz
```

### Conclusion

This approach allows us to include the Oracle Instant Client in  a customized `releases-docker.jfrog.io/jfrog/artifactory-pro:7.84.14` image without needed the customInitContainers.
