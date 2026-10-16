pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploymentScript is BaseScript {
    EtherBridge public etherBridge;
    Mailbox public mailbox;

    function run(
        address etherBridgeProxyAddress,
        address mailboxProxyAddress,
        address bridgeMailboxOwner,
        string memory ethereumChainId,
        string memory eclipseChainId,
        address trustedRelayerAddress
    ) public broadcast {
        // Set contract variables
        etherBridge = EtherBridge(etherBridgeProxyAddress);
        mailbox = Mailbox(mailboxProxyAddress);

        // Initialize the mailbox using init params
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = etherBridge.ETHER_BRIDGE_ID();
        address[] memory modules = new address[](1);
        modules[0] = etherBridgeProxyAddress;

        Mailbox.InitParams memory initParams = Mailbox.InitParams({
            initialOwner: bridgeMailboxOwner,
            trustedRelayer: trustedRelayerAddress,
            ids: ids,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });

        mailbox.initialize(initParams);
    }
}
