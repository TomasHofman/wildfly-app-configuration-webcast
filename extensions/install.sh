#!/usr/bin/env bash
source /usr/local/s2i/install-common.sh
injected_dir=$1

echo "Applying ${injected_dir}/wildfly-buildtime-config.cli"
$JBOSS_HOME/bin/jboss-cli.sh --file="${injected_dir}/wildfly-buildtime-config.cli"
