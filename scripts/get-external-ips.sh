#!/bin/bash
# get the external ip of the private nodes in a nodepool in GCP k8s cluster 

# Note first run: gcloud auth login , before running this script.
PROJECT_ID="support-prod-157422"
CLUSTER_NAME="varunm"
NODE_POOL_NAME="pool-1"
COMPUTE_ZONE="us-east1-b"

# Set project and zone
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $COMPUTE_ZONE

# Get instance group URLs for the node pool
INSTANCE_GROUP_URLS=$(gcloud container clusters describe $CLUSTER_NAME --format="json(nodePools)" | jq -r --arg NODE_POOL_NAME "$NODE_POOL_NAME" '.nodePools[] | select(.name == $NODE_POOL_NAME) | .instanceGroupUrls[]')

# Check if INSTANCE_GROUP_URLS is empty
if [ -z "$INSTANCE_GROUP_URLS" ]; then
  echo "No instance groups found for node pool $NODE_POOL_NAME"
  exit 1
fi

# Get instance names from the instance groups
INSTANCE_NAMES=""
for url in $INSTANCE_GROUP_URLS; do
  INSTANCE_GROUP=$(basename $url)
  INSTANCE_NAMES+=$(gcloud compute instance-groups list-instances $INSTANCE_GROUP --format="json" | jq -r '.[].instance | split("/")[-1]')
  INSTANCE_NAMES+=" "
done

# Check if INSTANCE_NAMES is empty
if [ -z "$INSTANCE_NAMES" ]; then
  echo "No instances found in the instance groups."
  exit 1
fi

# Get external IPs of the instances
gcloud compute instances list --filter="name:($INSTANCE_NAMES)" --format="table(name, networkInterfaces.accessConfigs[0].natIP)"