// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {CanonicalBridge} from "../../src/v1/CanonicalBridge.sol";
import {ICanonicalBridge} from "../../src/v1/interfaces/ICanonicalBridge.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse010_Test is Test {
    function _message(address feeReceiver) internal returns (ICanonicalBridge.WithdrawMessage memory) {
        return ICanonicalBridge.WithdrawMessage({
            from: bytes32(uint256(1)),
            destination: makeAddr("dest"),
            amountWei: 1 ether,
            withdrawId: 4,
            feeReceiver: feeReceiver,
            feeWei: 0
        });
    }

    function test_audit_authorizeRejectsZeroFeeReceiver() external {
        address admin = makeAddr("admin");
        CanonicalBridge bridge = new CanonicalBridge(admin, address(0x1234));
        vm.prank(admin);
        vm.expectRevert();
        bridge.authorizeWithdraw(_message(address(0)));
    }

    function test_keep_authorizeAcceptsFeeReceiver() external {
        address admin = makeAddr("admin");
        CanonicalBridge bridge = new CanonicalBridge(admin, address(0x1234));
        ICanonicalBridge.WithdrawMessage memory message = _message(makeAddr("fee"));
        vm.prank(admin);
        bridge.authorizeWithdraw(message);
        assertTrue(bridge.withdrawMsgIdProcessed(message.withdrawId) != bridge.withdrawMsgIdProcessed(5));
    }
}
