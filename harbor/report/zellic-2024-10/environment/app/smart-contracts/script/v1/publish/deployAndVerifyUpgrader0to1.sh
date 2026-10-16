#!/bin/bash

# deployUpgrader0to1.sh
# Deploys the upgrader and verifies. 
# Add mainnet to the command to deploy to mainnet. 
# Runs the DeployUpgrader0to1.s.sol forge script.
# Ensure RPC_URLs and PRIVATE_KEY are set in .env in the ./smart-contracts folder. 

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

    echo "Deploying contract..."
    DEPLOY_OUTPUT=$(forge script script/v1/publish/DeployUpgrader0to1.s.sol:DeployUpgrader0to1 --rpc-url "$rpc_url" --broadcast -vvvv | tee /dev/tty)
    
    # Extract the deployed address
    DEPLOYED_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP "DEPLOYED_ADDRESS: \K0x[a-fA-F0-9]{40}")
    
    if [ -z "$DEPLOYED_ADDRESS" ]; then
        echo "Failed to extract deployed address"
        exit 1
    fi
    
    echo "Contract deployed at: $DEPLOYED_ADDRESS"
    
    echo "Verifying contract..."
    forge verify-contract "$DEPLOYED_ADDRESS" Upgrader0to1 \
        --chain-id "$chain_id" \
        --compiler-version 0.8.21 \
        --num-of-optimizations 200 \
        --watch \
        --constructor-args $(cast abi-encode "constructor()") \
        --etherscan-api-key "$etherscan_api_key"
    
    if [ $? -eq 0 ]; then
        echo "Contract verification successful"
    else
        echo "Contract verification failed"
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
