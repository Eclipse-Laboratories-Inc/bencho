#!/bin/bash

# verifyTreasury.sh
#
# Purpose: Manually verifies the Treasury implementation contract on Etherscan.
#
# Usage:
#   For Sepolia:
#     ./script/v1/verify/verifyTreasury.sh <CONTRACT_ADDRESS> sepolia
#   For Mainnet:
#     ./script/v1/verify/verifyTreasury.sh <CONTRACT_ADDRESS> mainnet
#
# Prerequisites:
#   - ETHERSCAN_API_KEY set in .env file
#   - Forge installed and configured

# Source the .env file
source .env

# Check if contract address is provided
if [ -z "$1" ]; then
    echo "Please provide the contract address as the first argument."
    exit 1
fi

CONTRACT_ADDRESS=$1

# Set the network (default to sepolia if not specified)
NETWORK=${2:-sepolia}

if [ "$NETWORK" == "mainnet" ]; then
    CHAIN_ID=1
elif [ "$NETWORK" == "sepolia" ]; then
    CHAIN_ID=11155111
else
    echo "Invalid network. Use 'sepolia' or 'mainnet'."
    exit 1
fi

# Verify the contract
forge verify-contract $CONTRACT_ADDRESS Treasury \
    --chain-id $CHAIN_ID \
    --compiler-version 0.8.21 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor()") \
    --etherscan-api-key $ETHERSCAN_API_KEY

if [ $? -eq 0 ]; then
    echo "Treasury contract verification successful"
else
    echo "Treasury contract verification failed"
    exit 1
fi