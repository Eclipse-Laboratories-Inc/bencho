// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {CanonicalBridge} from "../../src/v1/CanonicalBridge.sol";
import {ICanonicalBridge} from "../../src/v1/interfaces/ICanonicalBridge.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse008_Test is Test {
    function _message(uint64 id) internal returns (ICanonicalBridge.WithdrawMessage memory) {
        return ICanonicalBridge.WithdrawMessage({
            from: bytes32(uint256(1)),
            destination: makeAddr("dest"),
            amountWei: 1 ether,
            withdrawId: id,
            feeReceiver: makeAddr("fee"),
            feeWei: 0
        });
    }

    function test_audit_cancelClearsWithdrawId() external {
        address admin = makeAddr("admin");
        CanonicalBridge bridge = new CanonicalBridge(admin, address(0x1234));
        ICanonicalBridge.WithdrawMessage memory message = _message(7);

        vm.roll(5);
        vm.startPrank(admin);
        bridge.authorizeWithdraw(message);
        bridge.deleteWithdrawMessage(message);
        vm.stopPrank();

        assertEq(bridge.withdrawMsgIdProcessed(message.withdrawId), bridge.withdrawMsgIdProcessed(8));
    }
}
