#!/bin/bash

dotenv=$(dirname $0)/../.env
if [ -f "${dotenv}" ]; then
    source ${dotenv}
fi

username=${TENDERLY_USERNAME}
if [ -n "${TEST_FORK}" ]; then
    project=${TENDERLY_TEST_PROJECT}
else
    project=${TENDERLY_PROJECT}
fi

# Path to the chain ids JSON file
chain_ids_json="./utils/chainIds.json"

# Read the network name from the environment variable, default to 'mainnet' if not set
network_name=${TENDERLY_NETWORK_NAME:-'mainnet'}

# Use jq to extract the network ID from the JSON file
network_id=$(jq -r --arg name "$network_name" '.[$name]' "$chain_ids_json")

# Check if network_id is null or empty
if [ -z "$network_id" ] || [ "$network_id" == "null" ]; then
    # Fallback to the default network ID
    network_id=${TENDERLY_NETWORK_ID:-"1"}
fi

echo "Creating a $network_name Tenderly Testnet with Chain Id $network_id... "
echo

# API Endpoint for creating a testnet
TENDERLY_TESTNET_API="https://api.tenderly.co/api/v1/account/${username}/project/${project}/testnet/container"

# Setup cleanup function
cleanup() {
    if [ -n "${testnet_id}" ] && [ -n "${TEST_FORK}" ]; then
        echo "Deleting a testnet ${testnet_id} from ${username}/${project}..."
        echo

        curl -sX DELETE "${TENDERLY_TESTNET_API}/${testnet_id}" \
            -H "Content-Type: application/json" -H "X-Access-Key: ${TENDERLY_ACCESS_KEY}"
    fi
}

trap cleanup TERM EXIT

# Create a testnet and extract testnet id and provider url
response=$(curl -sX POST "$TENDERLY_TESTNET_API" \
    -H "Content-Type: application/json" -H "X-Access-Key: ${TENDERLY_ACCESS_KEY}" \
    -d '{
        "displayName": "Fast Lane Testnet",
        "description": "",
        "visibility": "TEAM",
        "tags": {
            "purpose": "development"
        },
        "networkConfig": {
            "networkId": "'${network_id}'",
            "blockNumber": "latest",
            "baseFeePerGas": "1"
        },
        "private": true,
        "syncState": false
    }')

testnet_id=$(echo "$response" | jq -r '.container.id')
provider_url=$(echo "$response" | jq -r '.container.connectivityConfig.endpoints[0].uri')

echo "Created Tenderly Testnet ${testnet_id} at ${username}/${project}..."
echo

command="TENDERLY_TESTNET_ID=${testnet_id} TENDERLY_TESTNET_PROVIDER_URL=${provider_url} ${@:1}"

echo "Running:"
echo
echo ${command}

eval ${command}
