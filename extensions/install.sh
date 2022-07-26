#!/usr/bin/env bash

injected_dir=$1

echo "Applying ${injected_dir}/wildfly-buildtime-config.cli"
$JBOSS_HOME/bin/jboss-cli.sh --file="${injected_dir}/wildfly-buildtime-config.cli"

# Delete configuration history, because in container environment Wildfly would not be able to move this directory anymore at run-time.
rm -fr $JBOSS_HOME/standalone/configuration/standalone_xml_history/current
