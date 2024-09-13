#!/bin/bash
# bash decode_secret.sh jfrog-platform-xray-database-creds  devops-acc-us-env

# Check if both parameters are provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <jfrog_platform_secret_name> <namespace>"
  exit 1
fi

jfrog_platform_secret_name="$1"
namespace="$2"

# Get the JSON data for the secret
json_data=$(kubectl get secret "$jfrog_platform_secret_name" -n "$namespace" -o json)

# Function to decode base64-encoded values
decode_base64() {
  echo "$1" | base64 -d
}

# Loop through the keys in .data and decode the values
for key in $(echo "$json_data" | jq -r '.data | keys[]'); do
  value=$(echo "$json_data" | jq -r ".data[\"$key\"]")
  decoded_value=$(decode_base64 "$value")
  echo "$key: $decoded_value"
done

