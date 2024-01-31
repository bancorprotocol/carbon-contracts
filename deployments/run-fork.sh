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

echo "Creating a $network_name Tenderly Fork with Chain Id $network_id... "
echo

TENDERLY_FORK_API="https://api.tenderly.co/api/v1/account/${username}/project/${project}/fork"

cleanup() {
    if [ -n "${fork_id}" ] && [ -n "${TEST_FORK}" ]; then
        echo "Deleting a fork ${fork_id} from ${username}/${project}..."
        echo

        curl -sX DELETE "${TENDERLY_FORK_API}/${fork_id}" \
            -H "Content-Type: application/json" -H "X-Access-Key: ${TENDERLY_ACCESS_KEY}"
    fi
}

trap cleanup TERM EXIT

fork_id=$(curl -sX POST "${TENDERLY_FORK_API}" \
    -H "Content-Type: application/json" -H "X-Access-Key: ${TENDERLY_ACCESS_KEY}" \
    -d '{"network_id": "'${network_id}'"}' | jq -r '.simulation_fork.id')

echo "Created Tenderly Fork ${fork_id} at ${username}/${project}..."
echo

command="TENDERLY_FORK_ID=${fork_id} TENDERLY_NETWORK_NAME=${network_name} ${@:1}"

echo "Running:"
echo
echo ${command}

eval ${command}
