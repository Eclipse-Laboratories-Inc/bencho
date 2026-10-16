// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrader0to1} from "../../../src/v1/upgrader/Upgrader0to1.sol";

contract DeployUpgrader0to1 is Script {


    function run() public {

        // Load the private key from the environment
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting using the private key
        vm.startBroadcast(privateKey);

        Upgrader0to1 upgrader = new Upgrader0to1();

        console.log("DEPLOYED_ADDRESS:", address(upgrader));
    }
}
