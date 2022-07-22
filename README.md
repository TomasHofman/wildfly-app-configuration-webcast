# Wildfly OpenShift Image Configuration Example

This repository demonstrates how to deploy the Wildfly application server, containing a simple Jakarta EE application,
on OpenShift. This demo concentrates on how to configure a Wildfly instance on OpenShift with a **Wildfly CLI
script** (rather than via environment variables), to show how leveraging CLI scripts has been simplified with the
release of [Wildfly 26](https://www.wildfly.org/news/2021/12/16/WildFly26-Final-Released/) and the new 
[Wildfly S2I v2 workflow](https://www.wildfly.org/news/2021/10/29/wildfly-s2i-v2-overview/).

This demo uses following technologies:

* [Wildfly 26](https://www.wildfly.org/news/2021/12/16/WildFly26-Final-Released/) (or later versions),
* [Wildfly Maven Plugin 3.x](https://github.com/wildfly/wildfly-maven-plugin/),
* [Wildfly S2I (Source to Image) v2](https://github.com/wildfly/wildfly-s2i/) container images,
* [wildfly Helm Charts 2.x](https://docs.wildfly.org/wildfly-charts/).

<!--
For comparison, the [pre-wildfly-26](tree/pre-wildfly-26) branch of this repository shows how the same result could be
achieved with earlier versions of Wildfly. Notably, a use of a Wildfly CLI script for the configuration of the Wildfly
instance, as opposed to configuration via environment variables, is much easier with the new workflow.
-->

## Prerequisites

Following is assumed:

* You have access to an OpenShift cluster. If you don't have access to a cluster, you can get a
temporary cluster for free on
the [Developer Sandbox for Red Hat OpenShift page](https://developers.redhat.com/developer-sandbox/get-started).
* The `oc` command is installed on your system (see [this article](https://developers.redhat.com/openshift/command-line-tools) on how to install it).
* The `helm` command is installed on your system (see [this article](https://helm.sh/docs/intro/install/) on how to install it).

## Example Application

The sample application in this repository contains a static [HTML page](src/main/webapp/index.html) and a 
[JAX-RS endpoint](src/main/java/org/wildfly/demo/config/HelloEndpoint.java). This will be important to
determine which Galleon layers to include to provision the Wildfly server, as can be seen further on.

## Configuring the Wildfly Maven Plugin

As opose to the old Wildfly S2I workflow, the provisioning of the Wildfly server instance is now part of the Maven build
process. To provision a server instance, the pom.xml contains following section with configuration of the
[Wildfly Maven Plugin](https://github.com/wildfly/wildfly-maven-plugin/):

```xml
<plugin>
    <groupId>org.wildfly.plugins</groupId>
    <artifactId>wildfly-maven-plugin</artifactId>
    <version>3.0.0.Final</version>
    <configuration>
        <feature-packs>
            <feature-pack>
                <location>org.wildfly:wildfly-galleon-pack:${version.wildfly}</location>
            </feature-pack>
        </feature-packs>
        <!-- List of layers to build the application server from: -->
        <layers>
            <!-- The jaxrs-server layer provides JAX-RS API implementation -->
            <layer>jaxrs-server</layer>
            <!-- The microprofile-health layer provides microprofile health endpoints at
                 [server address]:9990/api/live and [server address]:9990/api/ready -->
            <layer>microprofile-health</layer>
        </layers>
        <galleon-options>
            <jboss-fork-embedded>true</jboss-fork-embedded>
        </galleon-options>
        <runtime-name>ROOT.war</runtime-name>
    </configuration>
    <executions>
        <execution>
            <goals>
                <goal>package</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

The configuration contains two important sections that determine which extensions are going to be included in the
provisioned server instance:

1. a list of feature packs (the `<feature-packs>` element),
2. and a list of layers (the `<layers>` element).

Exapliner: A feature pack (aka a Galleon pack) is a package of functionalities (called layers) that can be used to
provision a Wildfly instance. These packs are packaged as Maven artifacts, and the provisioning tool downloads them from
a Maven repository. Which particular layers from given packs should be actually included in the provisioned instance can
be further limited in the `<layers>` element. If the element is not present, all layers from configured feature packs
will be included. Limiting the number of layers will produce a smaller Wildfly instance, in terms of disk space and 
memory footprint.

## Building the Application and Provisioning the Server

In this demo, the Wildfly Maven Plugin execution is part of the "openshift" Maven profile. That way, running 
`mvn clean package` will only build the application WAR, but it won't provision a server instance.

In order to provision a Wildfly server instance with the application WAR deployed in it, it is needed to activate the
"openshift" profile:

```shell
$ mvn clean package -Popenshift
```

The provisioned server will be created in the `target/server/` directory. You can run this server by executing following 
command:

```shell
$ ./target/server/bin/standalone.sh
```

To verify that the application is correctly deployed, you visit <http://localhost:8080/> in your browser. You should see
a simple "Hello" page with a link to the JAX-RS endpoint.

Note that the "openshift" Maven profile is also automatically activated in the Wildfly S2I workflow, which expects a
server instance to be provisioned by the Maven build.

## Preparing a CLI Configuration Script

With real life applications, it is usually necessary to configure the application server in a specific way for an
application to work. Common aspects that may require configuration are connections to database servers or messaging brokers,
integration with SSO servers, etc. The Wildfly S2I container images offer two ways how to perform configuration:

* via environment variables,
* via a Wildfly CLI script.

This section concentrates on the CLI script configuration. Advantages of using a CLI script are that:

1. more complex configurations can be achieved, compared to configuration via environment variables,
2. for people who are already used to working with Wildfly CLI, it may be more straightforward to define configuration
in this way.

For demonstrational purposes, a simple CLI script was created
in [openshift/wildfly-config.cli](blob/main/openshift/wildfly-config.cli) which reconfigures Wildfly logging subsystem
to log DEBUG messages from our application to standard output:

```
/subsystem=logging/logger=org.wildfly.demo.config:add(level=DEBUG)
/subsystem=logging/console-handler=CONSOLE:write-attribute(name=level, value=DEBUG)
```

## Create an OpenShift ConfigMap with the CLI Script

We need the CLI script to be available to the application containers. We don't want to make it part of the container
image however, because we assume that the file would contain environment specific configuration, i.e. the CLI script for
an imaginary staging environment would be a little different from the script for the production environment.

The best way to achieve that is to create an OpenShift ConfigMap containing the script.

Firstly, log in to your cluster with the `oc` CLI tool:

```shell
$ oc login --token=[token string] --server=[cluster url]
```

(You can copy the login command in the OpenShift Web Console user menu.)

Then, create the ConfigMap:

```shell
$ oc create configmap wildfly-config --from-file openshift/wildfly-config.cli 
configmap/wildfly-config created
```

This ConfigMap would later be mounted to the application container filesystem, from where it can be read by the Wildfly
launcher script.

## Prepare a Helm Values File

The values file is sort of configuration file for a Helm Chart. Values from this file are taken and substituted into
templates defined by given Helm Chart. The structure of the YAML file is dictated by the particular Helm Chart that is
being used. For the Wildfly Helm Chart case, you can check the README file in the 
[Wildfly Helm Chart GitHub repository](https://github.com/wildfly/wildfly-charts/blob/main/charts/wildfly/README.md) for
help.

In our case, the file was prepared at [openshift/helm.yaml](blob/main/openshift/helm.yaml) and the content is as
follows, some comments are added here for clarity:

```yaml
build:
  # application source GIT repository
  uri: https://github.com/TomasHofman/wildfly-openshift-configuration-example.git
  # and the repository branch
  ref: main
  enabled: true
   # mode can be either s2i or bootable-jar
  mode: s2i
  output:
    # how the resulting container should be stored
    kind: ImageStreamTag
  s2i:
    # container image for building the application from source and provisioning the server, there is also a jdk17 variant
    builderImage: 'quay.io/wildfly/wildfly-s2i-jdk11'
    # runtime container image where the app will run, there is also a jdk17 variant
    runtimeImage: 'quay.io/wildfly/wildfly-runtime-jdk11'
    version: latest
deploy:
  enabled: true
  env:
    # env variable for the runtime container, that says what CLI configuration scripts should be run during container startup,
    # check the volume related values bellow regarding the path
    - name: CLI_LAUNCH_SCRIPT
      value: /etc/wildfly/wildfly-config.cli
  # this says that we want to take a ConfigMap and use it as a filesystem volume
  volumes:
    - name: wildfly-config
      configMap:
        name: wildfly-config
  # and this says where the volume should be mounted in the filesystem
  volumeMounts:
    - name: wildfly-config
      mountPath: /etc/wildfly
  # we want to have a route created and it should be TLS encrypted
  route:
    enabled: true
    tls:
      enabled: true
      termination: edge
      insecureEdgeTerminationPolicy: Redirect
  # it's a good practice to define liveness & readiness probes, these endpoints are automatically available thanks to
  # the "microprofile-health" galleon layer we added into the provisioning config in the Wildfly Maven Plugin
  livenessProbe:
    httpGet:
      path: /health/live
      port: admin
  readinessProbe:
    httpGet:
      path: /health/ready
      port: admin
  startupProbe:
    failureThreshold: 36
    httpGet:
      path: /health/live
      port: admin
    initialDelaySeconds: 5
    periodSeconds: 5
  # and finally, how many pods we want to have running
  replicas: 1
```

## Deploying on OpenShift

We are going to use Wildfly Helm Chart to deploy our app on the OpenShift cluster.

1. Add the Wildfly Helm Charts repository to your Helm installation:
   ```shell
   $ helm repo add wildfly http://docs.wildfly.org/wildfly-charts/
   ```
   
   You can check that the "wildfly" chart is searchable:
   ```shell
   $ helm search repo wildfly
   wildfly/wildfly                     	2.0.1        	           	Build and Deploy WildFly applications on OpenShift
   [...]
   ```
   The version of the chart should be 2.0.0 or higher.

2. Let `helm` create all the OpenShift resources necessary to build and deploy the application:
   ```shell
   $ helm install example-wildfly-app -f openshift/helm.yaml wildfly/wildfly
   ```
   This command should result in creation of multiple OpenShift resources. You can list them with the following `oc`
   command:
   ```shell
   $ oc get all --selector app.kubernetes.io/instance=example-wildfly-app
   NAME                               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
   service/example-wildfly-app        ClusterIP   172.30.46.37   <none>        8080/TCP   2h
   service/example-wildfly-app-ping   ClusterIP   None           <none>        8888/TCP   28h

   NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/example-wildfly-app   1/1     1            1           2h

   NAME                                                                 TYPE     FROM         LATEST
   buildconfig.build.openshift.io/example-wildfly-app                   Docker   Dockerfile   2
   buildconfig.build.openshift.io/example-wildfly-app-build-artifacts   Source   Git@main     1

   NAME                                                                 IMAGE REPOSITORY                                                                                                                   TAGS     UPDATED
   imagestream.image.openshift.io/example-wildfly-app                   default-route-openshift-image-registry.apps.sandbox-m2.ll9k.p1.openshiftapps.com/thofman-dev/example-wildfly-app                   latest   2 hours ago
   imagestream.image.openshift.io/example-wildfly-app-build-artifacts   default-route-openshift-image-registry.apps.sandbox-m2.ll9k.p1.openshiftapps.com/thofman-dev/example-wildfly-app-build-artifacts   latest   2 hours ago

   NAME                                           HOST/PORT                                                              PATH   SERVICES              PORT    TERMINATION     WILDCARD
   route.route.openshift.io/example-wildfly-app   wildfly-v2-app-thofman-dev.apps.sandbox-m2.ll9k.p1.openshiftapps.com          example-wildfly-app   <all>   edge/Redirect   None
   ```
   
3. You can now watch the application being built and deployed. You can do that either in the OpenShift Web Console, or 
   via the `oc` command in the terminal.

   To watch the builds:
   ```shell
   $ oc get build -w
   NAME                                    TYPE     FROM          STATUS     STARTED         DURATION
   example-wildfly-app-build-artifacts-1   Source   Git@8f914f9   Running    2 minutes ago   
   example-wildfly-app-build-artifacts-1   Source   Git@8f914f9   Complete   2 minutes ago   2m23s
   example-wildfly-app-1                   Docker   Dockerfile    Pending                    
   example-wildfly-app-1                   Docker   Dockerfile    Running    33 seconds ago   
   example-wildfly-app-1                   Docker   Dockerfile    Complete   About a minute ago   1m10s
   ```
   
   When both builds get completed, you can watch the deployment readiness to progress:
   ```shell
   oc get deployment wildfly-v2-app -w
   NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
   example-wildfly-app   0/0     0            0           2h
   example-wildfly-app   0/1     1            0           2h
   example-wildfly-app   1/1     1            1           2h
   ```
   When the AVAILABLE column becomes 1, the application should be ready to recieve requests.

4. Try to access the application. To learn the application URL, inspect the "route" resource:
   ```shell
   $ oc get route
   NAME                  HOST/PORT                                                                   PATH   SERVICES              PORT    TERMINATION     WILDCARD
   example-wildfly-app   example-wildfly-app-thofman-dev.apps.sandbox-m2.ll9k.p1.openshiftapps.com          example-wildfly-app   <all>   edge/Redirect   None
   ```
   In my case, the "example-wildfly-app-thofman-dev.apps.sandbox-m2.ll9k.p1.openshiftapps.com" string is the URL of my
   deployed application. Use your browser to visit the URL shown in your route, and click on the link to the 
   "/api/hello" JAX-RS endpoint. Make a couple of requests there.

5. Check output of your application pod, and it should contain the DEBUG messages printed by the JAX-RS endpoint:
   ```text
   [...]
   12:24:08,356 INFO [org.jboss.as] (Controller Boot Thread) WFLYSRV0025: WildFly Full 26.1.1.Final (WildFly Core 18.1.1.Final) started in 34201ms - Started 269 of 354 services (138 services are lazy, passive or on-demand) - Server configuration file in use: standalone.xml
   12:24:08,357 INFO [org.jboss.as] (Controller Boot Thread) WFLYSRV0060: Http management interface listening on http://0.0.0.0:9990/management
   12:24:08,357 INFO [org.jboss.as] (Controller Boot Thread) WFLYSRV0054: Admin console is not enabled
   13:07:34,653 DEBUG [org.wildfly.demo.config.HelloEndpoint] (default task-1) Received a /hello endpoint request
   13:07:35,747 DEBUG [org.wildfly.demo.config.HelloEndpoint] (default task-1) Received a /hello endpoint request
   ```