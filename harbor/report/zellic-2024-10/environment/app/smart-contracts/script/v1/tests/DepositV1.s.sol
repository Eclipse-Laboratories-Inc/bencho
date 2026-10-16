// All Rights Reserved
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import { CanonicalBridge } from "../../../src/v1/CanonicalBridge.sol";
import { Treasury } from "../../../src/v1/Treasury.sol";

contract DepositV1 is Script {

    CanonicalBridge public canonicalBridgeV1;
    Treasury public treasuryV1;

    function run(
        address canonicalBridgeAddress,
        address treasuryProxyAddress,
        bytes32 eclipseAddress,
        uint256 amountWei
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);    

        // Instantiate contracts
        canonicalBridgeV1 = CanonicalBridge(canonicalBridgeAddress);
        treasuryV1 = Treasury(payable(treasuryProxyAddress));

        // Fund the deployer and run deposit to fund the treasury
        vm.deal(address(deployerWallet.addr), amountWei);
        canonicalBridgeV1.deposit{value: amountWei}(eclipseAddress, amountWei);

        // Log configurations
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", deployerWallet.addr);
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("CanonicalBridge(address): %s", address(canonicalBridgeAddress));
        console.log("Treasury(proxy): %s", address(treasuryProxyAddress));

        console.log("");
        console.log("------ config ------");
        console.log("amountWei(config): %s", amountWei);
        console.log("Treasury(balance): %s", treasuryProxyAddress.balance);
    }
}
