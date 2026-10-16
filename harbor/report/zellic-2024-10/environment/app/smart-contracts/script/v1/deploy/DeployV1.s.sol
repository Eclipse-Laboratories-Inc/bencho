// All Rights Reserved
pragma solidity 0.8.21;

// V0 implementations
import { TreasuryV0 } from "../../../src/v0/TreasuryV0.sol";
import { MailboxV0 } from "../../../src/v0/MailboxV0.sol";

// V1 implementations
import { CanonicalBridge } from "../../../src/v1/CanonicalBridge.sol";
import { Treasury } from "../../../src/v1/Treasury.sol";

import "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Script } from "forge-std/Script.sol";

contract DeployV1 is Script {
    TreasuryV0 public treasuryV0;
    MailboxV0 public mailboxV0;

    CanonicalBridge public canonicalBridgeV1;
    Treasury public treasuryV1;

    Treasury public _treasuryV1;

    function run(
        address treasuryProxyAddress,
        address trustedRelayerAddress
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy V1 contract stack
        canonicalBridgeV1 = new CanonicalBridge(deployerWallet.addr, treasuryProxyAddress);
        treasuryV1 = new Treasury();

        // Run upgrade on Treasury and Mailbox
        Treasury(payable(treasuryProxyAddress)).upgradeToAndCall(
            address(treasuryV1),
            abi.encodeWithSelector(Treasury.reinitialize.selector)
        );

        // Grant the trustedRelayer the withdraw authority role
        canonicalBridgeV1.grantRole(
            canonicalBridgeV1.WITHDRAW_AUTHORITY_ROLE(), 
            trustedRelayerAddress
        );

        // Grant the canonicalBridge the depositor role
        _treasuryV1 = Treasury(treasuryProxyAddress);
        _treasuryV1.grantRole(_treasuryV1.DEPOSITOR_ROLE(), address(canonicalBridgeV1));

        // Log deployed configuration
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", deployerWallet.addr);
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("CanonicalBridge(address): %s", address(canonicalBridgeV1));
        console.log("Treasury(address): %s", address(treasuryV1));
        console.log("Treasury(proxy): %s", address(treasuryProxyAddress));

        console.log("");
        console.log("------ configs ------");
        console.log("Treasury(balance): %s", treasuryProxyAddress.balance);

        vm.stopBroadcast();
    }
}
