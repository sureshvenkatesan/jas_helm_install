# Oracle Instant Client Setup with Custom artifactory-pro image

Please review [Java 11 Licensing: What You’re Really Asking](https://jfrog.com/blog/java-11-licensing-what-youre-really-asking/).

## Oracle Instant Client Requirement

The **Oracle Instant Client** is a mandatory requirement because the **JFrog metadata service** does not use a JDBC driver since it is a **Go application**, not Java. Therefore, to support the connection between **Artifactory and the database**, you must install both:

- **Thin Client (Type 4)**
- **OCI Client (Type 2)**

## Oracle Instant Client Licensing and Distribution

The **Oracle Instant Client Type 2 driver**  
([instantclient-basic-linux.x64-21.11.0.0.0dbru.zip](https://download.oracle.com/otn_software/linux/instantclient/2111000/instantclient-basic-linux.x64-21.11.0.0.0dbru.zip) and later versions)  
is licensed under the **GPL**, and **JFrog is not authorized to distribute it**—except for the PostgreSQL driver.  

Consequently, **JFrog cannot include this driver** in a custom Artifactory Docker image.

## Download the Correct Oracle Instant Client Driver

Please use the appropriate **Oracle Instant Client Type 2 driver** from:  
➡️ [Oracle Instant Client Downloads for Linux x86-64 (64-bit)](https://www.oracle.com/database/technologies/instant-client/linux-x86-64-downloads.html)

This package contains:
- **Thin Client (Type 4) JDBC driver**
- **OCI (Type 2) client**

Ensure that the version you choose is compatible with the **JRE version** mentioned in:  
➡️ [Java Requirements for JFrog Products](https://jfrog.com/help/r/jfrog-installation-setup-documentation/java-requirements-for-jfrog-products)

as recommended by Oracle in:  
➡️ [Oracle Database JDBC Driver and Companion Jars Downloads](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html).

## JFrog Artifactory Embedded OpenJDK Version

As per the [Embedded OpenJDK Version](https://jfrog.com/help/r/jfrog-release-information/embedded-openjdk-version), the OpenJDK versions used in **Artifactory** are:

| Artifactory Version | Embedded OpenJDK Version |
|----------------------|-------------------------|
| 7.46.3 - 7.98.14    | OpenJDK 17              |
| 7.104.5 and later   | OpenJDK 21 (`21.0.5 LTS` released on 2024-10-15) |

## JDBC Driver Certification

According to [Oracle Database JDBC Driver and Companion Jars Downloads](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html),  
the **ojdbc17.jar** is **certified for both JDK 17 and JDK 21**.

## Configuring Artifactory with Oracle in a Helm Deployment

For configuring **Artifactory with an external Oracle database** in a **Helm deployment**, refer to:

- [ARTIFACTORY: How to configure Artifactory with an external database when using Artifactory Helm Installation](https://jfrog.com/help/r/artifactory-how-to-configure-artifactory-with-an-external-database-when-using-artifactory-helm-installation)
- [Oracle for Artifactory](https://jfrog.com/help/r/jfrog-installation-setup-documentation/oracle-for-artifactory)
- [Configure Artifactory to use Oracle](https://jfrog.com/help/r/jfrog-installation-setup-documentation/configure-artifactory-to-use-oracle)

You can use the **Oracle Instant Client Type 2 driver**  
([instantclient-basic-linux.x64-23.7.0.25.01.zip](https://download.oracle.com/otn_software/linux/instantclient/2370000/instantclient-basic-linux.x64-23.7.0.25.01.zip)),  
which includes the **Thin Client (Type 4) JDBC driver (`ojdbc17.jar`)**.

---



### Proposed Solution

We suggest that you create a custom  `releases-docker.jfrog.io/jfrog/artifactory-pro image`  that includes the Oracle 
Instant Client `instantclient-basic-linux.x64-23.7.0.25.01.zip`. 

## Steps to Implement the Solution

### 1. Build a Custom `releases-docker.jfrog.io/jfrog/artifactory-pro` image`


#### Dockerfile

```Dockerfile
FROM releases-docker.jfrog.io/jfrog/artifactory-pro:7.84.14
USER root
RUN mkdir -p /opt/oracle/
COPY instantclient-basic-linux.x64-23.7.0.25.01.zip /opt/oracle/
RUN mkdir -p /opt/oracle/instantclient && cd /opt/oracle/instantclient && \
    unzip -j ../instantclient-basic-linux.x64-23.7.0.25.01.zip && \
    cp /opt/jfrog/artifactory/app/artifactory/libaio/* ./ && \
    chown -R artifactory:artifactory /opt/oracle/instantclient
USER artifactory
ENV LD_LIBRARY_PATH="/opt/oracle/instantclient"
```
**Note:** used "/opt/oracle/instantclient" instead of "/opt/oracle/instantclient_23_7" in case you want to upgrade 
the driver in future

### 2. Steps to Build the Docker Image

1. **Create a directory** and place both the `instantclient-basic-linux.x64-23.7.0.25.01.zip` file and the `Dockerfile` inside it.

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
  preStartCommand: "mkdir -p /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/; rm -f /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/ojdbc8.jar; cp /opt/oracle/instantclient/ojdbc17.jar /opt/jfrog/artifactory/var/bootstrap/artifactory/tomcat/lib/"
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
**Note:** the steps to set the environmental variables is in the main [readme.md](readme.md)

After modifying the [artifactory/values-artifactory.yaml](artifactory/values-artifactory.yaml) to [artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml](artifactory/values-artifactory_w_oci_type2_in_artifactory-pro_image.yml) , you can deploy or upgrade your Helm chart with the following command:

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
