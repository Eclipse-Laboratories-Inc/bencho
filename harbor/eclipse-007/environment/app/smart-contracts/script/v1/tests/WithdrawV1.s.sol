// All Rights Reserved
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ICanonicalBridge } from "../../../src/v1/interfaces/ICanonicalBridge.sol";
import { CanonicalBridge } from "../../../src/v1/CanonicalBridge.sol";
import { Treasury } from "../../../src/v1/Treasury.sol";

contract WithdrawV1 is Script {

    CanonicalBridge public canonicalBridgeV1;
    Treasury public treasuryV1;

    function run(
        address canonicalBridgeAddress,
        bytes32 eclipseAddress,
        address destination,
        uint256 amountWei,
        uint64 withdrawId,
        address feeReceiver,
        uint256 feeWei
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);    

        // Instantiate contracts
        canonicalBridgeV1 = CanonicalBridge(canonicalBridgeAddress);

        // Build withdraw message
        ICanonicalBridge.WithdrawMessage memory message = ICanonicalBridge.WithdrawMessage({
            from: eclipseAddress,
            destination: destination,
            amountWei: amountWei,
            withdrawId: withdrawId,
            feeReceiver: feeReceiver,
            feeWei: feeWei
        });

        canonicalBridgeV1.authorizeWithdraw(message);

        // Log configurations
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", deployerWallet.addr);
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("CanonicalBridge(address): %s", address(canonicalBridgeAddress));

        console.log("");
        console.log("------ config ------");
        console.log("destination(config): %s", destination);
        console.log("amountWei(config): %s", amountWei);
        console.log("withdrawId(config): %s", withdrawId);
        console.log("feeReceiver(config): %s", feeReceiver);
        console.log("feeWei(config): %s", feeWei);
    }
}
