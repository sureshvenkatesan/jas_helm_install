#!/bin/bash
# bash ./decode-secret.sh <namespace> <secret-name> <key-name>

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <namespace> <secret-name> <key-name>"
    exit 1
fi

# Variables
NAMESPACE=$1
SECRET_NAME=$2
KEY_NAME=$3

# Fetch the secret and decode the specified key value
kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath="{.data.$KEY_NAME}" | base64 --decode

# Output a newline character for readability
echo
