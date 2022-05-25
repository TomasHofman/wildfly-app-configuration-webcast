#!/usr/bin/env bash

echo "Appending CLI operations to ${CLI_SCRIPT_FILE}"

cat /etc/eap-config/eap-config.cli >> "${CLI_SCRIPT_FILE}"
