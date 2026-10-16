#!/bin/bash
# Verifies that every upgradeable contract reserves exactly MAX_GAP_SIZE contract-level storage slots.
#
# Same rule as the hardhat `shouldHaveGap` helper it replaces:
#   - the last storage variable of the contract must be `__gap`
#   - if the contract declares its own state (FIRST_VAR given), the span from that first variable to the end
#     of the gap must be exactly MAX_GAP_SIZE slots
#   - otherwise the gap alone must be MAX_GAP_SIZE slots
#
# Layouts come from `forge inspect <Contract> storage`, so this runs on the Foundry build and needs no hardhat.
set -euo pipefail

MAX_GAP_SIZE=50

# Contract:FirstStateVariable (empty when the contract declares no state of its own)
CONTRACTS=(
    "CarbonController:"
    "Pairs:_lastPairId"
    "Strategies:_strategyCounter"
    "Voucher:_useGlobalURI"
    "CarbonVortex:_totalCollected"
    "CarbonPOL:_marketPriceMultiply"
)

cd "$(dirname "$0")/.."

failures=0
for spec in "${CONTRACTS[@]}"; do
    contract=${spec%%:*}
    first_var=${spec#*:}

    layout=$(forge inspect "$contract" storage --json)

    last_label=$(jq -r '.storage | last | .label' <<<"$layout")
    last_slot=$(jq -r '.storage | last | .slot | tonumber' <<<"$layout")
    last_type=$(jq -r '.storage | last | .type' <<<"$layout")

    if [[ "$last_label" != "__gap" ]]; then
        echo "FAIL  $contract: last storage variable is '$last_label', expected '__gap'"
        failures=$((failures + 1))
        continue
    fi

    # e.g. t_array(t_uint256)47_storage -> 47
    if [[ "$last_type" =~ t_array\(t_uint256\)([0-9]+)_storage ]]; then
        gap_size=${BASH_REMATCH[1]}
    else
        echo "FAIL  $contract: cannot read gap size from type '$last_type'"
        failures=$((failures + 1))
        continue
    fi

    if [[ -n "$first_var" ]]; then
        # last declaration wins when a label is shadowed; "null" when the variable is not in the layout at all
        first_slot=$(jq -r --arg v "$first_var" '[.storage[] | select(.label == $v)] | last | if . == null then "null" else (.slot | tonumber) end' <<<"$layout")
        if [[ "$first_slot" == "null" ]]; then
            echo "FAIL  $contract: state variable '$first_var' not found in storage layout"
            failures=$((failures + 1))
            continue
        fi
        used=$((last_slot - first_slot + gap_size))
        detail="slots $first_slot..$last_slot + gap $gap_size = $used"
    else
        used=$gap_size
        detail="gap $gap_size"
    fi

    if [[ "$used" -ne "$MAX_GAP_SIZE" ]]; then
        echo "FAIL  $contract: $detail, expected exactly $MAX_GAP_SIZE"
        failures=$((failures + 1))
    else
        echo "ok    $contract: $detail"
    fi
done

if [[ "$failures" -ne 0 ]]; then
    echo
    echo "$failures contract(s) violate the $MAX_GAP_SIZE-slot storage gap rule"
    exit 1
fi
