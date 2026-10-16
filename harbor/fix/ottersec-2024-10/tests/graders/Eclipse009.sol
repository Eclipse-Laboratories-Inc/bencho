// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OldTreasuryMock} from "../mocks/OldTreasuryMock.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {CanonicalBridge} from "../../src/v1/CanonicalBridge.sol";
import {ICanonicalBridge} from "../../src/v1/interfaces/ICanonicalBridge.sol";
import {Test} from "forge-std/Test.sol";

contract ClaimStatusProbe {
    CanonicalBridge public bridge;
    ICanonicalBridge.WithdrawMessage internal pending;
    uint8 public seen;
    bool public called;

    function arm(CanonicalBridge bridge_, ICanonicalBridge.WithdrawMessage memory message_) external {
        bridge = bridge_;
        pending = message_;
    }

    receive() external payable {
        called = true;
        seen = uint8(bridge.withdrawMessageStatus(pending));
    }
}

contract Eclipse009_Test is Test {
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

    function test_audit_claimClosesBeforeExternalCall() external {
        address admin = makeAddr("admin");
        Treasury treasury = _treasury(admin);
        CanonicalBridge bridge = new CanonicalBridge(admin, address(treasury));
        bytes32 role = treasury.WITHDRAW_AUTHORITY_ROLE();
        vm.prank(admin);
        treasury.grantRole(role, address(bridge));
        vm.deal(address(treasury), 2 ether);

        ClaimStatusProbe probe = new ClaimStatusProbe();
        ICanonicalBridge.WithdrawMessage memory message = ICanonicalBridge.WithdrawMessage({
            from: bytes32(uint256(1)),
            destination: address(probe),
            amountWei: 1 ether,
            withdrawId: 9,
            feeReceiver: makeAddr("fee"),
            feeWei: 0
        });
        probe.arm(bridge, message);

        vm.prank(admin);
        bridge.authorizeWithdraw(message);
        vm.warp(block.timestamp + 8 days);

        bridge.claimWithdrawal(message);

        assertTrue(probe.called(), "destination was not paid");
        assertEq(probe.seen(), uint8(ICanonicalBridge.WithdrawStatus.CLOSED));
        assertEq(address(probe).balance, 1 ether);
    }
}
