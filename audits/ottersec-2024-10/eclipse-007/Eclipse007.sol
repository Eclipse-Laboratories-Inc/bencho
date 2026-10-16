// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OldTreasuryMock} from "../mocks/OldTreasuryMock.sol";
import {Treasury} from "../../src/v1/Treasury.sol";
import {Test} from "forge-std/Test.sol";

contract Eclipse007_Test is Test {
    Treasury internal treasury;

    function setUp() public {
        address admin = makeAddr("admin");
        OldTreasuryMock impl = new OldTreasuryMock();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (admin)));
        Treasury nextImpl = new Treasury();
        vm.prank(admin);
        OldTreasuryMock(payable(address(proxy))).upgradeToAndCall(
            address(nextImpl), abi.encodeCall(Treasury.reinitialize, ())
        );
        treasury = Treasury(payable(address(proxy)));
        bytes32 role = treasury.WITHDRAW_AUTHORITY_ROLE();
        vm.prank(admin);
        treasury.grantRole(role, address(this));
    }

    function test_audit_feeIsTakenFromAmount() external {
        address user = makeAddr("user");
        address feeTo = makeAddr("fee");
        uint256 amount = 1 ether;
        uint256 fee = 0.1 ether;
        vm.deal(address(treasury), amount);

        treasury.withdrawEth(user, amount, feeTo, fee);

        assertEq(user.balance, amount - fee);
        assertEq(feeTo.balance, fee);
    }

    function test_keep_insufficientBalanceStillReverts() external {
        address user = makeAddr("user-short");
        address feeTo = makeAddr("fee-short");
        vm.deal(address(treasury), 0.9 ether);
        vm.expectRevert();
        treasury.withdrawEth(user, 1 ether, feeTo, 0.1 ether);
    }

    function test_keep_feeExceedingAmountReverts() external {
        address user = makeAddr("user-bigfee");
        address feeTo = makeAddr("fee-bigfee");
        vm.deal(address(treasury), 2 ether);
        vm.expectRevert();
        treasury.withdrawEth(user, 1 ether, feeTo, 1.1 ether);
    }

    function test_keep_zeroFeeWithdrawPaysFullAmount() external {
        address user = makeAddr("user-zero-fee");
        address feeTo = makeAddr("fee-zero");
        vm.deal(address(treasury), 1 ether);

        treasury.withdrawEth(user, 1 ether, feeTo, 0);

        assertEq(user.balance, 1 ether);
        assertEq(feeTo.balance, 0);
    }
}
