#!/usr/bin/env bash

injected_dir=$1

echo "Copy postconfigure.sh script to ${JBOSS_HOME}/extensions/"

mkdir -p "${JBOSS_HOME}/extensions/"
cp "${injected_dir}/postconfigure.sh" "${JBOSS_HOME}/extensions/"
