// All Rights Reserved
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import { EtherBridgeV0 } from "../../../src/v0/EtherBridgeV0.sol";
import { TreasuryV0 } from "../../../src/v0/TreasuryV0.sol";

contract DepositV0 is Script {

    EtherBridgeV0 public etherBridgeV0;
    TreasuryV0 public treasuryV0;

    function run(
        address etherBridgeProxyAddress,
        address treasuryProxyAddress,
        bytes32 eclipseAddress,
        uint256 amountWei
    ) public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);    

        // Instantiate contracts
        etherBridgeV0 = EtherBridgeV0(etherBridgeProxyAddress);
        treasuryV0 = TreasuryV0(payable(treasuryProxyAddress));

        // Fund the deployer and run deposit to fund the treasury
        vm.deal(address(deployerWallet.addr), amountWei);
        etherBridgeV0.deposit{value: amountWei}(eclipseAddress, amountWei);

        // Log configurations
        console.log("");
        console.log("------ deployer ------");
        console.log("deployer(wallet): %s", deployerWallet.addr);
        console.log("deployer(msg.sender): %s", msg.sender);

        console.log("");
        console.log("------ contracts ------");
        console.log("EtherBridge(proxy): %s", address(etherBridgeProxyAddress));
        console.log("Treasury(proxy): %s", address(treasuryProxyAddress));

        console.log("");
        console.log("------ config ------");
        console.log("amountWei(config): %s", amountWei);
        console.log("Treasury(balance): %s", treasuryProxyAddress.balance);
    }
}
