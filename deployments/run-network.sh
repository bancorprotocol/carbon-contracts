#!/bin/bash

dotenv=$(dirname $0)/../.env
if [ -f "${dotenv}" ]; then
    source ${dotenv}
fi

# Path to the chain ids JSON file
chain_ids_json="./utils/chainIds.json"

# Read the network name from the environment variable, default to 'mainnet' if not set
network_name=${HARDHAT_NETWORK:-'mainnet'}

# Read the network ID from the environment variable, default to '1' if not set
network_id=${NETWORK_ID:-"1"}

# Use jq to extract the network ID from the JSON file
network_id=$(jq -r --arg name "$network_name" '.[$name]' "$chain_ids_json")

# Check if network_id is null or empty
if [ -z "$network_id" ] || [ "$network_id" == "null" ]; then
    # Fallback to the default network ID
    network_id=${TENDERLY_NETWORK_ID:-"1"}
fi

# Create a new dir for the deploy script files and copy them there
mkdir -p ./deploy/scripts/${network_name}
cp -r ./deploy/scripts/network/ ./deploy/scripts/${network_name}/

# Create a new dir for the deployment files
mkdir -p ./deployments/${network_name}

# Create the deployment .chainId file for the network
echo ${network_id} > ./deployments/${network_name}/.chainId

command="HARDHAT_NETWORK=${network_name} ${@:1}"

echo "Running:"
echo
echo ${command}

eval ${command}
