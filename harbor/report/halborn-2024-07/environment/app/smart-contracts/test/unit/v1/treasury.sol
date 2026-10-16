pragma solidity 0.8.21;

import {Treasury} from "../../../src/v1/Treasury.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "./attacker.sol";
import "forge-std/Test.sol";

contract TreasuryInitializable is Treasury {
    // The storage slot used by Initializable for _initialized variable.
    // This must match the actual slot used by the OpenZeppelin's Initializable contract.
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    function enableInitializers() internal {
        // Using assembly to directly write to the storage slot.
        assembly {
            // Writing 0 to the slot to indicate the contract is not initialized.
            // The storage layout must ensure this operation only modifies the _initialized field.
            sstore(INITIALIZABLE_STORAGE, 0)
        }
    }

    constructor() {
        enableInitializers();
    }
}

contract TreasuryTest is Test {
    TreasuryInitializable private treasury;

    address payable private deployAuthority;
    address payable private constant initialTreasuryAuthority = payable(address(0xA));
    address payable private constant nextTreasuryAuthority = payable(address(0xB));
    address payable private constant etherBridgeAddress = payable(address(0xC));

    uint256 private initialBalance = 10 ether;

    event Initialized(uint64 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event EmergencyTreasuryWithdraw(address indexed to, uint256 amount);
    event TreasuryDeposit(address indexed from, uint256 amount);

    function setUp() public {
        deployAuthority = payable(address(this));
        treasury = new TreasuryInitializable();
        treasury.initialize(deployAuthority, etherBridgeAddress);
        vm.deal(address(payable(treasury)), initialBalance);
    }

    // Initializable
    function test_Treasury_CannotInitAgain() public {
        // Expect a revert on calling initialize after setup
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        treasury.initialize(deployAuthority, etherBridgeAddress);

        // Expect a revert on calling it again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        treasury.initialize(deployAuthority, etherBridgeAddress);

        // Expect a revert on calling it again with a different address
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        treasury.initialize(deployAuthority, address(0xD));
    }

    function test_Treasury_InitializeEmitsCorrectEvents() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(0), address(this));
        vm.expectEmit(true, true, true, true);
        emit Initialized(1);
        TreasuryInitializable anotherTreasury = new TreasuryInitializable();
        anotherTreasury.initialize(deployAuthority, etherBridgeAddress);
    }

    // Ownable
    function test_Treasury_TransferAndAcceptOwnership() public {
        // Check initial owner is the deployer (this contract)
        assertEq(treasury.owner(), deployAuthority);

        // Invoke transfer ownership to initial treasury authority
        treasury.transferOwnership(initialTreasuryAuthority);

        // Check ownership is not yet transferred
        assertEq(treasury.owner(), deployAuthority);

        // Initial treasury authority accepts ownership
        vm.prank(initialTreasuryAuthority);
        treasury.acceptOwnership();
        vm.stopPrank();

        // Verify ownership was transferred to the treasury authority
        assertEq(treasury.owner(), initialTreasuryAuthority);

        // Transfer ownership to next treasury authority
        vm.prank(initialTreasuryAuthority);
        treasury.transferOwnership(nextTreasuryAuthority);
        vm.stopPrank();

        // Check ownership is still treasury authority
        assertEq(treasury.owner(), initialTreasuryAuthority);

        // Next treasury authority accepts ownership
        vm.prank(nextTreasuryAuthority);
        treasury.acceptOwnership();
        vm.stopPrank();

        // Verify ownership is transferred to next treasury authority
        assertEq(treasury.owner(), nextTreasuryAuthority);
    }

    // Pausable
    function test_Treasury_OnlyOwnerCanPauseUnpause() public {
        treasury.pause();
        assertEq(treasury.paused(), true);
        treasury.unpause();
        assertEq(treasury.paused(), false);
    }

    function test_Treasury_OnlyOwnerCanPause() public {
        // Verify treasury is not paused after initialize
        assertEq(treasury.paused(), false);

        // Pause the treasury and ensure it is in paused state
        treasury.pause();
        assertEq(treasury.paused(), true);

        // Transfer authority and accept ownership
        treasury.transferOwnership(initialTreasuryAuthority);
        vm.prank(initialTreasuryAuthority);
        treasury.acceptOwnership();
        vm.stopPrank();

        // 'initial' authority calls unpause then verifiers state is now unpaused
        vm.prank(initialTreasuryAuthority);
        treasury.unpause();
        vm.stopPrank();
        assertEq(treasury.paused(), false);

        // 'initial' authorit6y then calls pause to verifies state is now paused
        vm.prank(initialTreasuryAuthority);
        treasury.pause();
        vm.stopPrank();
        assertEq(treasury.paused(), true);

        // 'initial' authority transfers ownership to next authority who accepts it
        vm.prank(initialTreasuryAuthority);
        treasury.transferOwnership(nextTreasuryAuthority);
        vm.stopPrank();
        vm.prank(nextTreasuryAuthority);
        treasury.acceptOwnership();
        vm.stopPrank();

        // now previous 'initial' authority will get revert if they try to unpause since they aren't owner
        vm.prank(initialTreasuryAuthority);
        vm.expectRevert();
        treasury.unpause();
        vm.stopPrank();

        // now we unpause with actual authority
        vm.prank(nextTreasuryAuthority);
        treasury.unpause();
        vm.stopPrank();

        // previous authority will also get a revert if they call pause
        vm.prank(initialTreasuryAuthority);
        vm.expectRevert();
        treasury.pause();
        vm.stopPrank();
    }

    function test_Treasury_PausingPreventsDeposits() public {
        // fund ether bridge
        vm.deal(etherBridgeAddress, 10 ether);

        // Send 2 ether from ether bridge when treasury is not paused
        assertEq(treasury.paused(), false);
        vm.prank(etherBridgeAddress);
        (bool success,) = payable(address(treasury)).call{value: 2 ether}("");
        require(success, "Failed to send Ether to attacker");
        vm.stopPrank();

        // Pause and verify we are paused
        treasury.pause();
        assertEq(treasury.paused(), true);

        // The bridge sends 2 ether when paused should not succeed
        vm.prank(etherBridgeAddress);
        (success,) = payable(address(treasury)).call{value: 2 ether}("");
        assertEq(success, false);
        vm.stopPrank();
    }

    function test_Treasury_EmergencyWithdrawsAlwaysAvailable() public {
        assertEq(treasury.paused(), false);
        assertEq(address(treasury).balance, initialBalance, "Treasury balance should be at initial balance");
        uint256 withdrawAmount = 1 ether;
        treasury.emergencyWithdraw(withdrawAmount);

        assertEq(
            address(treasury).balance,
            initialBalance - withdrawAmount,
            "Treasury balance should be at initial balance - withdrawAmount"
        );
        treasury.pause();
        assertEq(treasury.paused(), true);

        treasury.emergencyWithdraw(withdrawAmount);
        assertEq(
            address(treasury).balance,
            initialBalance - 2 * withdrawAmount,
            "Treasury balance should be at initial balance - 2 * withdrawAmount"
        );
    }

    function test_Treasury_PauseShouldEmitEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Paused(address(this));
        treasury.pause();
    }

    // Test deposits
    function test_Treasury_DepositsCorrectAmount() public {
        uint256 depositAmount = 1 ether;
        (bool success,) = address(treasury).call{value: depositAmount}("");
        require(success, "Low-level call failed");
        assertEq(address(treasury).balance, initialBalance + depositAmount);
    }

    function test_Treasury_FallbackEmitsDepositEvent() public {
        // prefund ether bridge for now
        vm.deal(etherBridgeAddress, initialBalance);

        // Expect a treasury deposit event
        uint256 amount = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit TreasuryDeposit(etherBridgeAddress, amount);

        // Deposit 1 ether using fallback
        vm.prank(etherBridgeAddress);
        (bool success,) = address(treasury).call{value: amount}("");
        vm.stopPrank();
        require(success, "Failed to send Ether or call fallback function.");
    }

    // Emergency Withdraw
    function test_Treasury_EmergencyWithdrawInsufficientBalance_ShouldFail() public {
        vm.expectRevert("Insufficient funds");
        treasury.emergencyWithdraw(initialBalance + 1 wei);
    }

    function test_Treasury_EmergencyWithdrawExactBalance() public {
        // Verify initial balance of treasury is correct
        assertEq(address(treasury).balance, initialBalance, "Treasury balance should be at initial balance");

        // Expect that the entirety of the initial balance will be to the deploy authority in an event
        vm.expectEmit(true, true, true, true);
        emit EmergencyTreasuryWithdraw(deployAuthority, initialBalance);

        // Call emergency withdraw and check final treasury balance
        treasury.emergencyWithdraw(initialBalance);
        assertEq(address(treasury).balance, 0, "Treasury balance should be zero after exact withdraw");
    }

    function test_Treasury_EmergencyWithdrawLessThanTreasuryBalance() public {
        assertEq(address(treasury).balance, initialBalance, "Treasury balance should be at initial balance");

        // Expect to withdraw 1 wei less than initial balance of treasury
        uint256 withdrawAmount = 1 wei;
        vm.expectEmit(true, true, true, true);
        emit EmergencyTreasuryWithdraw(deployAuthority, initialBalance - withdrawAmount);

        // Ensure the final balance is correct
        treasury.emergencyWithdraw(initialBalance - withdrawAmount);
        assertEq(address(treasury).balance, withdrawAmount, "Treasury balance should be 1 wei");

        // Set same initial balance in treasury (not vm.deal just sets value instead of increasing it)
        vm.deal(address(payable(treasury)), initialBalance);
        assertEq(address(treasury).balance, initialBalance, "Treasury balance should be at initial balance");

        // Expect to withdraw a small amount of wei (1 wei) only
        vm.expectEmit(true, true, true, true);
        emit EmergencyTreasuryWithdraw(deployAuthority, withdrawAmount);
        treasury.emergencyWithdraw(withdrawAmount);
        assertEq(
            address(treasury).balance,
            initialBalance - withdrawAmount,
            "Treasury balance should be at initial balance - withdraw amount"
        );
    }

    function test_Treasury_EmergencyWithdrawNonOwner_ShouldFail() public {
        // Unauthorized error if you do emergency withdraw using a non-owner address
        vm.prank(nextTreasuryAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nextTreasuryAuthority)
        );
        treasury.emergencyWithdraw(initialBalance - 1 ether);
        vm.stopPrank();
    }

    // Tests using deposit and withdraw
    function test_Treasury_AllEventsAreEmittedCorrectly() public {
        // Expect a deposit event when sending ether to the contract
        vm.expectEmit(true, true, true, true);
        emit TreasuryDeposit(deployAuthority, 1 ether); // Use address(this) or the actual caller's address
        (bool success2,) = address(treasury).call{value: 1 ether}("");
        require(success2, "Failed to send Ether or call fallback function.");

        // Expect a withdrawal event when ether is withdrawn to 'otherAddress'
        vm.expectEmit(true, true, true, true);
        emit EmergencyTreasuryWithdraw(deployAuthority, 1 ether);
        treasury.emergencyWithdraw(1 ether);
    }

    function test_Treasury_ValidBalanceAfterDepositWithdraw() public {
        // Check state after various interactions
        uint256 initialBal = address(treasury).balance;

        // Deposit 1 ether
        (bool success,) = address(treasury).call{value: 1 ether}("");
        require(success, "Low-level call failed");
        assertEq(address(treasury).balance, initialBal + 1 ether);

        // Withdraw 1 ether
        treasury.emergencyWithdraw(1 ether);
        assertEq(address(treasury).balance, initialBal);
    }

    // Reentrancy for emergency withdraw
    function test_Treasury_WithdrawReentrancyAttack_ShouldFail() public {
        // Deploy & fund attacker contract
        ReentrantAttacker attacker = new ReentrantAttacker(address(treasury));
        vm.deal(address(attacker), 10);

        // Make attacker the treasury owner / authority
        treasury.transferOwnership(address(attacker));
        vm.prank(address(attacker));
        treasury.acceptOwnership();
        vm.stopPrank();

        // Perform attack
        vm.expectRevert("Failed to send Ether");
        attacker.attack();
    }

    // Adding a fallback function so that this contract can receive ether from treasury
    receive() external payable {}
}
