#!/bin/bash
set -e

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

# if deployments/${network_name} doesn't exist, exit the script
if [ ! -d "./deployments/${network_name}" ]; then
    echo "Error: Deployments directory for ${network_name} does not exist."
    exit 1
fi

### Copy the upgrade script to the current network's deploy scripts dir
upgrade_file="./deploy/scripts/upgrade/000x-CarbonVortex-upgrade.ts"
target_dir="./deploy/scripts/${network_name}"
migrations_file="./deployments/${network_name}/.migrations.json"

# Delete and recreate the deploy scripts dir
rm -rf "$target_dir"
mkdir -p "$target_dir"

# Get the highest migration number from the migrations file using jq
highest_num="$(jq -r '
  [ keys[]?                                   # collect all keys
    | capture("^(?<n>\\d+)").n                # grab leading digits
    | tonumber ]                              # to number
  | (if length==0 then 0 else max end)
' "$migrations_file")"

# Get new migration number - highest+1 and pad it to 4 digits
new_num=$((highest_num + 1))
printf -v padded "%04d" "$new_num"

# Copy and rename the template
cp "$upgrade_file" "${target_dir}/${padded}-CarbonVortex-upgrade.ts"
echo "Created: ${target_dir}/${padded}-CarbonVortex-upgrade.ts"

command="HARDHAT_NETWORK=${network_name} ${@:1}"

echo "Running:"
echo
echo ${command}

eval ${command}
