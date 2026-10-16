pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploymentScript is BaseScript {
    EtherBridge public etherBridge;

    function run(
        address treasuryProxyAddress,
        address etherBridgeProxyAddress,
        address mailboxProxyAddress,
        address bridgeMailboxOwner
    ) public broadcast {
        // Set contract variables
        etherBridge = EtherBridge(etherBridgeProxyAddress);

        // Initialize the treasury and ether bridge
        etherBridge.initialize(bridgeMailboxOwner, mailboxProxyAddress, treasuryProxyAddress);
    }
}
