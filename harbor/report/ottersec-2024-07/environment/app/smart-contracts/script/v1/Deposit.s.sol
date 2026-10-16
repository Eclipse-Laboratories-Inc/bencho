pragma solidity 0.8.21;

import {BaseScript} from "./Base.s.sol";
import {EtherBridge} from "../../src/v1/EtherBridge.sol";

contract DepositScript is BaseScript {
    function run(address etherBridgeProxyAddress, bytes32 recipient, uint256 amountWei) public broadcast {
        // Validate amount is sufficient and recipient is set
        require(
            amountWei >= EtherBridge(etherBridgeProxyAddress).MIN_DEPOSIT(),
            "Amount is less than the minimum deposit required."
        );
        require(recipient != bytes32(0), "Invalid recipient address.");

        // Ensure the bridge is not paused
        EtherBridge etherBridge = EtherBridge(etherBridgeProxyAddress);
        require(etherBridge.paused() == false, "EtherBridge is currently paused.");

        // Call deposit with `value` set to `amountWei`
        etherBridge.deposit{value: amountWei}(recipient, amountWei);
    }
}
