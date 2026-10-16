pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Mailbox} from "../../src/v1/Mailbox.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeploymentScript is BaseScript {
    address public treasuryProxyAddress;
    address public etherBridgeProxyAddress;
    address public mailboxProxyAddress;

    Treasury public treasury;
    EtherBridge public etherBridge;
    Mailbox public mailbox;

    function run(
        string memory ethereumChainId,
        string memory eclipseChainId,
        address owner,
        address treasuryOwner,
        address trustedRelayerAddress
    ) public broadcast {
        // Deploy all proxies with empty init data
        bytes memory emptyInitData = "";
        treasuryProxyAddress = Upgrades.deployUUPSProxy("Treasury.sol:Treasury", emptyInitData);
        etherBridgeProxyAddress = Upgrades.deployUUPSProxy("EtherBridge.sol:EtherBridge", emptyInitData);
        mailboxProxyAddress = Upgrades.deployUUPSProxy("Mailbox.sol:Mailbox", emptyInitData);

        // Set contract variables
        treasury = Treasury(payable(treasuryProxyAddress)); // payable because of fallback function
        etherBridge = EtherBridge(etherBridgeProxyAddress);
        mailbox = Mailbox(mailboxProxyAddress);

        // Initialize the treasury and ether bridge
        treasury.initialize(treasuryOwner, etherBridgeProxyAddress);
        etherBridge.initialize(owner, mailboxProxyAddress, treasuryProxyAddress);

        // Initialize the mailbox using init params
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = etherBridge.ETHER_BRIDGE_ID();
        address[] memory modules = new address[](1);
        modules[0] = etherBridgeProxyAddress;

        Mailbox.InitParams memory initParams = Mailbox.InitParams({
            initialOwner: owner,
            trustedRelayer: trustedRelayerAddress,
            ids: ids,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });

        mailbox.initialize(initParams);
    }
}
