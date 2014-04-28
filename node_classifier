#!/bin/bash

FQDN=$1

# Get the parent of the folder this script is in
ROOT_DIR="$(dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ))"
YAML="$ROOT_DIR/node_classification/${1}.yaml"

[ ! -e "$YAML" ] && { echo "Node not found"; exit 1; }

cat "$YAML"
