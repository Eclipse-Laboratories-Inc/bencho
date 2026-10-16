// All Rights Reserved
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import { EtherBridgeV0 } from "../../../src/v0/EtherBridgeV0.sol";
import { TreasuryV0 } from "../../../src/v0/TreasuryV0.sol";
import { MailboxV0 } from "../../../src/v0/MailboxV0.sol";

contract DeployV0 is Script {
    address public etherBridgeProxyAddress;
    address public treasuryProxyAddress;
    address public mailboxProxyAddress;

    EtherBridgeV0 public etherBridgeV0;
    TreasuryV0 public treasuryV0;
    MailboxV0 public mailboxV0;

    // V0 implementation of the eclipse bridge requires three contracts to be deployed 
    // (Treasury, Mailbox, EtherBridge). After each of these deployments, initialize() 
    // must be called on all three contracts. All three deployments must run before 
    // initialize so a monolithic deploy script is required to bootstrap the protocol.
    function run(
        string memory ethereumChainId,
        string memory eclipseChainId,
        address owner,
        address trustedRelayerAddress
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy proxies / contracts and get deployed instances
        bytes memory emptyInitData = "";
        etherBridgeProxyAddress = Upgrades.deployUUPSProxy("EtherBridgeV0.sol:EtherBridgeV0", emptyInitData);
        treasuryProxyAddress = Upgrades.deployUUPSProxy("TreasuryV0.sol:TreasuryV0", emptyInitData);
        mailboxProxyAddress = Upgrades.deployUUPSProxy("MailboxV0.sol:MailboxV0", emptyInitData);

        etherBridgeV0 = EtherBridgeV0(etherBridgeProxyAddress);
        treasuryV0 = TreasuryV0(payable(treasuryProxyAddress));
        mailboxV0 = MailboxV0(mailboxProxyAddress);

        // Call initialization functions
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = etherBridgeV0.ETHER_BRIDGE_ID();
        address[] memory modules = new address[](1);
        modules[0] = etherBridgeProxyAddress;

        // mailbox initialization requires an array of "modules" to be 
        // passed to the mailbox, and initializtion will fail if these
        // arrays are empty. In this case we set the following config
        //
        // $.modulesById[keccak256("EtherBridge")] = etherBridgeProxyAddress
        //
        MailboxV0.InitParams memory initParams = MailboxV0.InitParams({
            initialOwner: owner,
            trustedRelayer: trustedRelayerAddress,
            ids: ids,
            modules: modules,
            ethereumChainId: ethereumChainId,
            eclipseChainId: eclipseChainId
        });

        etherBridgeV0.initialize(owner, address(mailboxProxyAddress), address(treasuryProxyAddress));
        treasuryV0.initialize(owner, address(etherBridgeProxyAddress));
        mailboxV0.initialize(initParams);

        // Log deployed configuration
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", deployerWallet.addr);
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("EtherBridge(address): %s", address(etherBridgeV0));
        console.log("EtherBridge(proxy): %s", address(etherBridgeProxyAddress));
        console.log("Treasury(address): %s", address(treasuryV0));
        console.log("Treasury(proxy): %s", address(treasuryProxyAddress));
        console.log("Mailbox(address): %s", address(mailboxV0));
        console.log("Mailbox(proxy): %s", address(mailboxProxyAddress));

        console.log("");
        console.log("------ configs ------");
        console.log("trustedRelayerAddress: %s", trustedRelayerAddress);
        console.log("Treasury(balance): %s", treasuryProxyAddress.balance);
        console.log("owner(config): %s", owner);

        vm.stopBroadcast();
    }
}
