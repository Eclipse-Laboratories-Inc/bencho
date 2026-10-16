// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OldTreasuryMock } from "../mocks/OldTreasuryMock.sol";
import { NotMock } from "../mocks/NotMock.sol";
import { Treasury } from "../../src/v1/Treasury.sol";
import { ISemVer } from "../../src/v1/interfaces/ISemVer.sol";
import { DeployAndUpgradeFixture } from "../fixtures/DeployAndUpgradeFixture.sol";
import { console } from "../../lib/forge-std/src/console.sol";

contract TreasuryTest is DeployAndUpgradeFixture {

    event TreasuryDeposit(address indexed from, uint256 amountWei);
    event TreasuryWithdrawal(
        address authority,
        address indexed to,
        uint256 amountWei,
        address feeReceiver,
        uint256 feeWei
    );
    event EmergencyTreasuryWithdraw(address indexed to, uint256 amountWei);

    error TransferFailed();
    error InsufficientFunds();
    error ZeroAddress();
    error EnforcedPause();

    modifier whenTreasuryIsPaused() {
        vm.startPrank(admin);
        treasury.pause();
        vm.stopPrank();
        _;
    }

    modifier whenAdmin() {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        address admin_ = makeAddr("admin");
        deployMocksAndUpgrade(admin_);
    }

    function test_DepositEthWhenContractIsPaused() external whenTreasuryIsPaused {
        assertEq(treasury.paused(), true);
        vm.expectRevert(EnforcedPause.selector);
        treasury.depositEth{value: 1 ether}();
    }

    function test_DepositEthWhenCallerDoesNotHaveDepositorRole() external {
        vm.deal(notBridge, 10 ether);
        vm.startPrank(notBridge);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                notBridge,
                treasury.DEPOSITOR_ROLE()
            )
        );
        treasury.depositEth{value: 1 ether}();
        vm.stopPrank();
    }

    function test_WhenGetVersionComponentsIsCalled() external view {
        // it should return correct version numbers
        ISemVer.Version memory v = treasury.getVersionComponents();
        assertEq(v.major, 2);
        assertEq(v.minor, 0);
        assertEq(v.patch, 0);
    }

    function test_DepositEthWhenContractIsNotPausedAndCallerHasDepositorRole() external {
        vm.startPrank(admin);
        treasury.grantRole(treasury.DEPOSITOR_ROLE(), depositor);
        vm.stopPrank();
        assertEq(treasury.paused(), false);

        uint256 initialBalance = address(treasury).balance;

        vm.startPrank(depositor);
        vm.expectEmit(true, true, true, true);
        emit TreasuryDeposit(depositor, 1 ether);

        treasury.depositEth{value: 1 ether}();
        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance + 1 ether);
    }

    function test_WithdrawEthWhenContractIsPaused() external whenTreasuryIsPaused {
        assertEq(treasury.paused(), true);
        uint256 initialBalance = address(treasury).balance;

        vm.expectRevert(EnforcedPause.selector);
        treasury.withdrawEth(deployer, 1 ether, deployer, 0.01 ether);

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_WithdrawEthWhenCallerDoesNotHaveWithdrawalAuthorityRole() external {
        vm.deal(notBridge, 10 ether);
        uint256 initialBalance = address(treasury).balance;

        vm.startPrank(notBridge);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                notBridge,
                treasury.WITHDRAW_AUTHORITY_ROLE()
            )
        );

        treasury.withdrawEth(notBridge, 1 ether, notBridge, 0.01 ether);
        vm.stopPrank();

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_WithdrawEthWhenToAddressIsNull() external {
        uint256 initialBalance = address(treasury).balance;

        vm.expectRevert(ZeroAddress.selector);
        treasury.withdrawEth(NULL_ADDRESS, 1 ether, deployer, 0.01 ether);

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_WithdrawEthWhenFeeReceiverAddressIsNull() external {
        treasury.grantRole(treasury.WITHDRAW_AUTHORITY_ROLE(), deployer);
        uint256 initialBalance = address(treasury).balance;

        vm.expectRevert(ZeroAddress.selector);
        treasury.withdrawEth(deployer, 1 ether, NULL_ADDRESS, 0.01 ether);

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_WithdrawEthWhenWithdrawalAmountExceedsContractBalance() external {
        vm.startPrank(admin);
        treasury.grantRole(treasury.WITHDRAW_AUTHORITY_ROLE(), withdrawalAuthority);

        uint256 initialBalance = address(treasury).balance;
        assertTrue(initialBalance < 200 ether);

        vm.startPrank(withdrawalAuthority);
        vm.expectRevert(InsufficientFunds.selector);
        treasury.withdrawEth(deployer, 200 ether, deployer, 0.01 ether);

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_WithdrawEthWhenContractIsNotPausedAndCallerHasWithdrawalAuthorityRoleAndAllParametersAreValid() external {
        vm.deal(payable(address(treasury)), 10 ether);
        vm.startPrank(admin);
        treasury.grantRole(treasury.WITHDRAW_AUTHORITY_ROLE(), withdrawalAuthority);
        assertEq(treasury.paused(), false);

        uint256 initialBalance = address(treasury).balance;
        uint256 withdrawalAmount = 1 ether;
        uint256 fee = 0.01 ether;

        vm.startPrank(withdrawalAuthority);
        vm.expectEmit(true, true, true, true);
        emit TreasuryWithdrawal(withdrawalAuthority, recipient, withdrawalAmount, feeRecipient, fee);
        treasury.withdrawEth(recipient, withdrawalAmount, feeRecipient, fee);

        uint256 newBalance = address(treasury).balance;
        assertEq(initialBalance - newBalance, withdrawalAmount);

        uint256 expectedRecipientBalance = withdrawalAmount - fee;
        uint256 expectedFeeRecipientBalance = fee;

        assertEq(recipient.balance, expectedRecipientBalance);
        assertEq(feeRecipient.balance, expectedFeeRecipientBalance);
    }

    function test_EmergencyWithdrawWhenCallerDoesNotHaveEmergencyRole() external {
        address unauthorizedCaller = vm.addr(123);
        uint256 initialBalance = address(treasury).balance;

        vm.startPrank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                unauthorizedCaller,
                treasury.EMERGENCY_ROLE()
            )
        );

        treasury.emergencyWithdraw(1 ether);
        vm.stopPrank();

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_EmergencyWithdrawWhenWithdrawalAmountExceedsContractBalance() external {
        address emergencyCaller = vm.addr(456);
        treasury.grantRole(treasury.EMERGENCY_ROLE(), emergencyCaller);
        uint256 initialBalance = address(treasury).balance;
        assertTrue(initialBalance < 200 ether);

        vm.startPrank(emergencyCaller);
        vm.expectRevert(InsufficientFunds.selector);
        treasury.emergencyWithdraw(200 ether);
        vm.stopPrank();

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance);
    }

    function test_EmergencyWithdrawWhenCallerHasEmergencyRoleAndWithdrawalAmountIsValid() external {
        address emergencyCaller = vm.addr(789);
        treasury.grantRole(treasury.EMERGENCY_ROLE(), emergencyCaller);
        uint256 initialBalance = address(treasury).balance;

        uint256 withdrawalAmount = 1 ether;
        assertTrue(initialBalance >= withdrawalAmount);

        vm.startPrank(emergencyCaller);
        vm.expectEmit(true, true, true, true);
        emit EmergencyTreasuryWithdraw(emergencyCaller, withdrawalAmount);

        treasury.emergencyWithdraw(withdrawalAmount);
        vm.stopPrank();

        uint256 newBalance = address(treasury).balance;
        assertEq(newBalance, initialBalance - withdrawalAmount);
        assertEq(emergencyCaller.balance, withdrawalAmount);
    }

    function test_PauseWhenCallerDoesNotHavePauserRole() external {
        address unauthorizedCaller = vm.addr(456);

        vm.startPrank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                unauthorizedCaller,
                treasury.PAUSER_ROLE()
            )
        );

        treasury.pause();
        vm.stopPrank();
    }

    function test_PauseWhenCallerHasPauserRole() external {
        address pauserCaller = vm.addr(123);
        treasury.grantRole(treasury.PAUSER_ROLE(), pauserCaller);

        vm.startPrank(pauserCaller);
        assertEq(treasury.paused(), false);

        treasury.pause();
        vm.stopPrank();

        assertEq(treasury.paused(), true);
    }

    function test_UnpauseWhenCallerDoesNotHaveStarterRole() external whenAdmin {
        // address unauthorizedCaller = vm.addr(456);
        // treasury.grantRole(treasury.PAUSER_ROLE(), deployer);
        treasury.pause();
        assertEq(treasury.paused(), true);

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                nonAdmin,
                treasury.STARTER_ROLE()
            )
        );

        treasury.unpause();
        vm.stopPrank();
    }

    function test_UnpauseWhenCallerHasStarterRole() external {
        vm.startPrank(admin);
        treasury.grantRole(treasury.PAUSER_ROLE(), starter);
        vm.startPrank(starter);
        treasury.pause();
        assertEq(treasury.paused(), true);

        vm.startPrank(admin);
        treasury.grantRole(treasury.STARTER_ROLE(), starter);
        vm.startPrank(starter);
        treasury.unpause();
        vm.stopPrank();

        assertEq(treasury.paused(), false);
    }

    function test_ReinitializeWhenContractIsAlreadyInitialized() external {
        assertEq(treasury.getVersionComponents().major, 2);

        vm.startPrank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidInitialization.selector
            )
        );

        treasury.reinitialize();
        vm.stopPrank();
    }

    function test_ReinitializeWhenContractIsNotInitialized() external {
        Treasury treasuryImpl = new Treasury();
        NotMock notTreasuryImpl = new NotMock();
        ERC1967Proxy notTreasuryProxy = new ERC1967Proxy(
            address(notTreasuryImpl),
            abi.encodeWithSelector(notTreasuryImpl.initialize.selector)
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        treasuryImpl.reinitialize();

        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        NotMock(payable(address(notTreasuryProxy))).upgradeToAndCall(
            address(treasuryImpl),
            abi.encodeWithSelector(Treasury.reinitialize.selector)
        );
    }

    function test_UpgradeWhenAdmin() external whenAdmin {
        NotMock newTreasuryImpl = new NotMock();

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(newTreasuryImpl));

        vm.expectEmit(true, true, true, true);
        emit Initialized(99);

        treasury.upgradeToAndCall(
            address(newTreasuryImpl),
            abi.encodeWithSelector(Treasury.reinitialize.selector)
        );
    }
}
