// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../../../src/v1/Treasury.sol";

contract DeployTreasury is Script {
    function run() public {
        // Load the private key from the environment
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting using the private key
        vm.startBroadcast(privateKey);

        // Deploy the Treasury contract
        Treasury treasury = new Treasury();

        // Log the deployed address
        console.log("DEPLOYED_ADDRESS:", address(treasury));

        // Stop broadcasting
        vm.stopBroadcast();
    }
}