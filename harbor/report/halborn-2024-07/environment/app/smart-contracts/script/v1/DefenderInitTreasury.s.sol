pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploymentScript is BaseScript {
    Treasury public treasury;

    function run(address treasuryProxyAddress, address etherBridgeProxyAddress, address treasuryOwner)
        public
        broadcast
    {
        // Set contract variables
        treasury = Treasury(payable(treasuryProxyAddress)); // payable because of fallback function

        // Initialize the treasury and ether bridge
        treasury.initialize(treasuryOwner, etherBridgeProxyAddress);
    }
}
