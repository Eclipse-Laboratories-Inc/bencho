// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OldTreasuryMock} from "../mocks/OldTreasuryMock.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {CanonicalBridge} from "../../src/v1/CanonicalBridge.sol";
import {ICanonicalBridge} from "../../src/v1/interfaces/ICanonicalBridge.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse010_Test is Test {
    function _message(address feeReceiver, uint256 feeWei) internal returns (ICanonicalBridge.WithdrawMessage memory) {
        return ICanonicalBridge.WithdrawMessage({
            from: bytes32(uint256(1)),
            destination: makeAddr("dest"),
            amountWei: 1 ether,
            withdrawId: 4,
            feeReceiver: feeReceiver,
            feeWei: feeWei
        });
    }

    function _treasury(address admin) internal returns (Treasury treasury) {
        OldTreasuryMock impl = new OldTreasuryMock();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (admin)));
        Treasury nextImpl = new Treasury();
        vm.prank(admin);
        OldTreasuryMock(payable(address(proxy))).upgradeToAndCall(
            address(nextImpl), abi.encodeCall(Treasury.reinitialize, ())
        );
        treasury = Treasury(payable(address(proxy)));
    }

    // The auditor allows either remediation: reject a zero fee receiver at
    // authorization (the reference fix), or handle it at claim time so the
    // withdrawal can still be paid. What must not happen is the original
    // deadlock: authorized, then unclaimable.
    function test_audit_zeroFeeReceiverCannotDeadlock() external {
        address admin = makeAddr("admin");
        Treasury treasury = _treasury(admin);
        CanonicalBridge bridge = new CanonicalBridge(admin, address(treasury));
        bytes32 role = treasury.WITHDRAW_AUTHORITY_ROLE();
        vm.prank(admin);
        treasury.grantRole(role, address(bridge));
        vm.deal(address(treasury), 2 ether);

        ICanonicalBridge.WithdrawMessage memory message = _message(address(0), 0.1 ether);
        vm.prank(admin);
        try bridge.authorizeWithdraw(message) {
            // Alternative fix: authorized, so it must be claimable after the
            // fraud window and pay amountWei - feeWei to the destination.
            vm.warp(block.timestamp + 8 days);
            bridge.claimWithdrawal(message);
            assertEq(message.destination.balance, 0.9 ether);
        } catch {
            // Reference fix: rejected before the message was stored.
            assertFalse(bridge.withdrawMsgIdProcessed(message.withdrawId));
        }
    }

    function test_keep_authorizeAcceptsFeeReceiver() external {
        address admin = makeAddr("admin");
        CanonicalBridge bridge = new CanonicalBridge(admin, address(0x1234));
        ICanonicalBridge.WithdrawMessage memory message = _message(makeAddr("fee"), 0);
        vm.prank(admin);
        bridge.authorizeWithdraw(message);
        assertTrue(bridge.withdrawMsgIdProcessed(message.withdrawId));
    }
}
