Ref:
- [How to add loggers in logback.xml dynamically for Helm installation](https://jfrog-int.atlassian.net/wiki/spaces/~5ceda092de7db40fbf15d552/pages/1339690789/How+to+add+loggers+in+logback.xml+dynamically+for+Helm+installation)

## Example: Enabling Logger in Artifactory Container

To enable logger `<logger name="org.artifactory.addon.mirror.internal" level="debug"/>` in the artifactory container:

```bash
kubectl exec -it jfrog-artifactory-0 -c artifactory -n jfrog-platform -- sed -i 's#^</configuration>#<logger name="org.artifactory.addon.mirror.internal" level="debug"/></configuration>#' /opt/jfrog/artifactory/var/etc/artifactory/logback.xml
```

## Enabling Loggers in jfconfig Container

Task: Enable DEBUG logs for the following packages in jfconfig's logback file in the jfconfig container of pod `jfrog-artifactory-0` in namespace `sureshv`:

```xml
<logger name="org.springframework" level="DEBUG"/>
<logger name="com.jfrog.jfconfig" level="DEBUG"/>
<logger name="org.jfrog.jfconfig" level="DEBUG"/>
```

**Note:** The jfconfig container uses `/opt/jfrog/artifactory/var/etc/jfconfig/logback.xml` as the main configuration file, which includes `/opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml` for custom loggers. The recommended approach is to add custom loggers to `logback-include.xml`.

## Using the Management Script (Recommended)

A script is provided to simplify enabling and disabling loggers with automatic verification. The script `manage_jfconfig_loggers.sh` handles both operations.

### Script Usage

**Enable loggers:**
```bash
./manage_jfconfig_loggers.sh enable <pod-name> <namespace> [container-name]
```

**Disable loggers:**
```bash
./manage_jfconfig_loggers.sh disable <pod-name> <namespace> [container-name]
```

**Examples:**
```bash
# Enable loggers in jfrog-artifactory-0 pod in sureshv namespace (default container: jfconfig)
./manage_jfconfig_loggers.sh enable jfrog-artifactory-0 sureshv

# Enable loggers with explicit container name
./manage_jfconfig_loggers.sh enable jfrog-artifactory-0 sureshv jfconfig

# Disable loggers
./manage_jfconfig_loggers.sh disable jfrog-artifactory-0 sureshv
```

The script will:
1. Verify the pod and container exist
2. Enable or disable the three debug loggers
3. Automatically verify the operation was successful
4. Display the current content of `logback-include.xml`
5. Show which loggers are present or missing

**Script location:** `install_jfrog_from_platform_chart/ps-values-for-aws-eks-s3-external-postgres-setup/manage_jfconfig_loggers/manage_jfconfig_loggers.sh`

### Viewing Container Logs

After enabling the debug loggers, you can tail the container logs to see the DEBUG output in real-time:

```bash
kubectl logs -f <pod-name> -c <container-name> -n <namespace>
```

**Example:**
```bash
kubectl logs -f jfrog-artifactory-0 -c jfconfig -n sureshv
```

This will follow the logs and display DEBUG level messages from the enabled loggers (`org.springframework`, `com.jfrog.jfconfig`, `org.jfrog.jfconfig`).

### Manual Steps (Alternative Method)

If you prefer to manage loggers manually, follow the steps below:

### Step 1: Verify Pod and Container

First, verify the pod exists and check the current logback files:

```bash
kubectl get pods -n sureshv

# Check the main logback.xml file
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- cat /opt/jfrog/artifactory/var/etc/jfconfig/logback.xml

# Check the logback-include.xml file (where custom loggers should be added)
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- cat /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

### Step 2: Enable the Loggers

Add the three loggers to the `logback-include.xml` file. This file is included by the main `logback.xml` and is the recommended place for custom loggers:

```bash
# Add all three loggers to logback-include.xml (replaces the comment line)
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i 's#<!--  Add custom loggers here -->#<logger name="org.springframework" level="DEBUG"/>\n<logger name="com.jfrog.jfconfig" level="DEBUG"/>\n<logger name="org.jfrog.jfconfig" level="DEBUG"/>#' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

Alternatively, you can add them one at a time:

```bash
# Add org.springframework logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i 's#<!--  Add custom loggers here -->#<logger name="org.springframework" level="DEBUG"/>\n<!--  Add custom loggers here -->#' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml

# Add com.jfrog.jfconfig logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i 's#<!--  Add custom loggers here -->#<logger name="com.jfrog.jfconfig" level="DEBUG"/>\n<!--  Add custom loggers here -->#' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml

# Add org.jfrog.jfconfig logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i 's#<!--  Add custom loggers here -->#<logger name="org.jfrog.jfconfig" level="DEBUG"/>\n<!--  Add custom loggers here -->#' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

**Note:** The `logback-include.xml` file is included by the main `logback.xml` file (see line 850 in logback.xml: `<include file="/opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml"/>`), so adding loggers here is the cleanest approach.

### Step 3: Verify Loggers Are Enabled

Verify that the loggers have been added by checking the `logback-include.xml` file:

```bash
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- cat /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

You should see output similar to:

```xml
<included>
<!--  Add custom loggers here -->
<logger name="org.springframework" level="DEBUG"/>
<logger name="com.jfrog.jfconfig" level="DEBUG"/>
<logger name="org.jfrog.jfconfig" level="DEBUG"/>
</included>
```

Or if you used the single command approach:

```xml
<included>
<logger name="org.springframework" level="DEBUG"/>
<logger name="com.jfrog.jfconfig" level="DEBUG"/>
<logger name="org.jfrog.jfconfig" level="DEBUG"/>
</included>
```

### Viewing Container Logs

After enabling the debug loggers, you can tail the container logs to see the DEBUG output in real-time:

```bash
kubectl logs -f jfrog-artifactory-0 -c jfconfig -n sureshv
```

This will follow the logs and display DEBUG level messages from the enabled loggers (`org.springframework`, `com.jfrog.jfconfig`, `org.jfrog.jfconfig`).

### Step 4: Removing Debug Loggers

When you're ready to remove these extra debug loggers, you can remove them from `logback-include.xml`:

```bash
# Remove org.springframework logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i '/<logger name="org.springframework" level="DEBUG"\/>/d' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml

# Remove com.jfrog.jfconfig logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i '/<logger name="com.jfrog.jfconfig" level="DEBUG"\/>/d' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml

# Remove org.jfrog.jfconfig logger
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i '/<logger name="org.jfrog.jfconfig" level="DEBUG"\/>/d' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

Or remove all three at once:

```bash
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- sed -i '/<logger name="org.springframework" level="DEBUG"\/>/d; /<logger name="com.jfrog.jfconfig" level="DEBUG"\/>/d; /<logger name="org.jfrog.jfconfig" level="DEBUG"\/>/d' /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

After removal, verify the loggers are gone:

```bash
kubectl exec -it jfrog-artifactory-0 -c jfconfig -n sureshv -- cat /opt/jfrog/artifactory/var/etc/jfconfig/logback-include.xml
```

The file should return to its original state:

```xml
<included>
<!--  Add custom loggers here -->
</included>
```




