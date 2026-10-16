#!/bin/bash

# deployAndVerifyTreasury.sh
#
# Purpose: Deploys the Treasury implementation contract and verifies it on Etherscan.
#
# Usage:
#   For Sepolia deployment (default):
#     ./script/v1/publish/deployAndVerifyTreasury.sh
#   For Mainnet deployment:
#     ./script/v1/publish/deployAndVerifyTreasury.sh mainnet
#
# Prerequisites:
#   1. Ensure the following environment variables are set in .env in the ./smart-contracts folder:
#      - SEPOLIA_RPC_URL: RPC URL for Sepolia testnet
#      - MAINNET_RPC_URL: RPC URL for Ethereum mainnet
#      - PRIVATE_KEY: Private key of the deploying account
#      - ETHERSCAN_API_KEY: API key for Etherscan verification
#   2. Make sure you have sufficient ETH in your account for deployment and verification.
#
# This script:
#   1. Runs the DeployTreasury.s.sol Forge script
#   2. Captures and displays the deployment output
#   3. Extracts the deployed contract address
#   4. Verifies the contract on Etherscan
#
# Note: Always test on Sepolia or other testnets before deploying to mainnet.

# Change to the directory containing the script
cd "$(dirname "$0")"

# Source the .env file
source "../../../.env"

# Navigate to the project root (assuming the script is in script/v1/publish/)
cd ../../../

# Function to check if a variable is set
check_var() {
    if [ -z "${!1}" ]; then
        echo "$1 is not set"
        exit 1
    fi
}

# Function to deploy and verify
deploy_and_verify() {
    local rpc_url="$1"
    local chain_id="$2"
    local etherscan_api_key="$3"

    echo "Deploying Treasury contract..."
    DEPLOY_OUTPUT=$(forge script script/v1/publish/DeployTreasury.s.sol:DeployTreasury --rpc-url "$rpc_url" --broadcast -vvvv | tee /dev/tty)
    
    # Extract the deployed address
    DEPLOYED_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP "DEPLOYED_ADDRESS: \K0x[a-fA-F0-9]{40}")
    
    if [ -z "$DEPLOYED_ADDRESS" ]; then
        echo "Failed to extract deployed address"
        exit 1
    fi
    
    echo "Treasury contract deployed at: $DEPLOYED_ADDRESS"
    
    echo "Verifying Treasury contract..."
    forge verify-contract "$DEPLOYED_ADDRESS" Treasury \
        --chain-id "$chain_id" \
        --compiler-version 0.8.21 \
        --num-of-optimizations 200 \
        --watch \
        --constructor-args $(cast abi-encode "constructor()") \
        --etherscan-api-key "$etherscan_api_key"
    
    if [ $? -eq 0 ]; then
        echo "Treasury contract verification successful"
    else
        echo "Treasury contract verification failed"
        exit 1
    fi
}

# Sepolia deployment and verification
sepolia_deploy() {
    check_var SEPOLIA_RPC_URL
    check_var ETHERSCAN_API_KEY
    deploy_and_verify "$SEPOLIA_RPC_URL" 11155111 "$ETHERSCAN_API_KEY"
}

# Mainnet deployment and verification
mainnet_deploy() {
    check_var MAINNET_RPC_URL
    check_var ETHERSCAN_API_KEY
    deploy_and_verify "$MAINNET_RPC_URL" 1 "$ETHERSCAN_API_KEY"
}

# Choose deployment network
if [ "$1" == "mainnet" ]; then
    echo "Deploying to Mainnet..."
    mainnet_deploy
else
    echo "Deploying to Sepolia..."
    sepolia_deploy
fi