# Wildfly OpenShift Image Configuration Example

This is an example application showcasing how to configure Wildfly OpenShift image via a Wildfly CLI script.

## The Usual Way

Normally, when deploying Wildfly (or JBoss EAP) container on an OpenShift cluster, configuration of the container is
done via environment variables. Taking a database configuration as an example, you would need to take two steps to
ensure your application image is able to connect to the database:

1. Ensure that the containerized Wildfly instance contains appropriate database driver.
2. Set environment variables for database connection string, username, password etc, which the Wildfly initialization
   scripts will use to create a datasource for your application.

### Step 1. - Adding the Database Driver <a name="add-db-driver"></a>

Say we want to connect to a PostgreSQL database instance. Including necessary JDBC driver module in the Wildfly image
can be achieved by adding the `postgresql-datasource` galleon layer to your provisioning configuration. (This particular
galleon layer does two things: it adds the JDBC driver module to the application server; and it creates a datasource in
the application server configuration.)

Note that this step takes place during the application container image *build time*.

How to add the galleon layer depends on which method you use to instantiate your OpenShift resources.

If you use *Helm Chart* to create the OpenShift manifests, the Galleon layers are defined in
the `build.s2i.galleonLayers` section of the Helm Chart YAML configuration:

```yaml
build:
  uri: https://github.com/TomasHofman/wildfly-openshift-configuration-example.git
  ref: main
  contextDir: helloworld-rs
  s2i:
    galleonLayers:
      - jaxrs-server
      - postgresql-datasource # <- the database driver layer
  mode: bootable-jar
  ...
```

If you create the OpenShift resources via the `oc new-app` CLI command, specify the `GALLEON_PROVISION_LAYERS` build
environment variable:

```shell
oc new-app --name wildfly-app \
     https://github.com/TomasHofman/wildfly-openshift-configuration-example.git \
     --image-stream=wildfly \
     --build-env GALLEON_PROVISION_LAYERS=jaxrs-server,postgresql-datasource \
     ...
```

If you already have the resource manifests in YAML format, you set the `GALLEON_PROVISION_LAYERS` variable in
the `*-build-artifacts` build config:

```yaml
- apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: wildfly-app-build-artifacts
  spec:
    strategy:
      type: Source
      sourceStrategy:
        from:
          kind: DockerImage
          name: 'quay.io/wildfly/wildfly-centos7:26.1'
        env:
          - name: GALLEON_PROVISION_LAYERS
            value: 'jaxrs-server,postgresql-datasource' # <- the database driver layer
          - name: GALLEON_PROVISION_DEFAULT_FAT_SERVER
            value: 'true'
    ...
```

(See the [wildfly-datasources-galleon-pack](https://github.com/wildfly-extras/wildfly-datasources-galleon-pack) for the
list of supported database vendors and available layers.)

### Step 2. - Configuring EAP via Env Variables

Now, after the Wildfly application image is built, it's going to contain the PostgreSQL driver module. The next step is
to configure a datasource, which uses this driver. The usual way is to set following environment variables on the
application runtime image:

* POSTGRESQL_URL,
* POSTGRESQL_PASSWORD,
* POSTGRESQL_USER.

There's a lot more variables available, which allow you to configure additional details on the datasource, check the
[documentation](https://github.com/wildfly-extras/wildfly-datasources-galleon-pack/blob/main/doc/postgresql/README.md).

## Configuration with a CLI Script

Here we finally come to the point. What if you want to configure something that's not possible to achieve with
environment variables? Or perhaps you feel more comfortable configuring Wildfly with a CLI script, because that's what
you already know from your baremetal days. We are going to investigate this apprach in this section.

### Step 1. - Adding the Database Driver

Staying with the original example of configuring a datasource, we still need to include the database JDBC driver. We
would achieve that in exactly the same way as [before](#add-db-driver), with the only difference being that instead of
the `postgresql-datasource` galleon layer, we would use the `postgresql-driver` layer. The latter layer only adds the
JDBC driver module, but *doesn't configure any datasource* by itself, as we are going to that via a Wildfly CLI script.

### Step 2. - Configuration via a CLI Script

As already mentioned, the Wildfly application images contain initialization scripts which configure and then run the
Wildfly instance when the image is executed. These scripts define certain injection points, that allow you to insert
some actions of your own. In particular, you can define a `preconfigure.sh` and `postconfigure.sh` scripts, which are
executed before and after the standard Wildfly configuration (meaning the configuration driven by environment variables)
takes place.

The `preconfigure.sh` and `postconfigure.sh` are expected to be present in the `$JBOSS_HOME/extensions/` directory. They
do not exist by default. If you provide them, they will be executed at respective times before 