pragma solidity 0.8.21;

import {EtherBridge} from "../../../src/v1/EtherBridge.sol";
import {ITreasury} from "../../../src/v1/interfaces/ITreasury.sol";
import {IMailbox} from "../../../src/v1/interfaces/IMailbox.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "forge-std/Test.sol";

contract MockTreasury is ITreasury {
    bool public FAILURE_MODE = false;

    function emergencyWithdraw(uint256 amount) external {
        if (FAILURE_MODE) {
            revert();
        }
    }

    receive() external payable {
        if (FAILURE_MODE) {
            revert();
        }
    }

    function setFailure(bool mode) public {
        FAILURE_MODE = mode;
    }
}

contract MockMailbox is IMailbox {
    bool public FAILURE_MODE = false;
    bool public FALSE_MODE = false;

    function setFailure(bool mode) public {
        FAILURE_MODE = mode;
    }

    function setFalse(bool mode) public {
        FALSE_MODE = mode;
    }

    function sendMessage(bytes memory chainId_, bytes memory receiver_, bytes memory message_, bytes memory data_)
        external
        payable
        returns (bool)
    {
        if (FAILURE_MODE) {
            revert("MockMailbox revert");
        }
        if (FALSE_MODE) {
            return false;
        }
        return true;
    }

    function receiveMessage(bytes memory chainId_, bytes memory sender_, bytes memory message_, bytes memory data_)
        external
        payable
        returns (bool)
    {
        if (FAILURE_MODE) {
            revert();
        }
        if (FALSE_MODE) {
            return false;
        }
        return true;
    }
}

contract EtherBridgeTest is Test {
    EtherBridge private etherBridge;

    address payable private deployAuthority;
    address payable private mailboxAddress;
    address payable private treasuryAddress;
    address payable private constant adminAuthority = payable(address(0xC));
    bytes32 private constant recipient = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    event Deposited(address indexed sender, bytes32 indexed recipient, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        mailboxAddress = payable(address(new MockMailbox()));
        treasuryAddress = payable(address(new MockTreasury()));
        deployAuthority = payable(address(this));
        etherBridge = new EtherBridge();
        etherBridge.initialize(mailboxAddress, treasuryAddress);
    }

    // Initializable
    function test_EtherBridge_CannotInitAgain() public {
        // Expect a revert on calling initialize after setup
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        etherBridge.initialize(mailboxAddress, treasuryAddress);
    }

    function test_EtherBridge_InitAddressSet() public {
        etherBridge = new EtherBridge();
        vm.expectRevert("CommonUtility: zero address");
        etherBridge.initialize(address(0), treasuryAddress);
        vm.expectRevert("CommonUtility: zero address");
        etherBridge.initialize(mailboxAddress, address(0));
    }

    // AccessControl
    function test_EtherBridge_AdminCanPauseUnpause() public {
        // Pause the bridge and verify that bridge is paused
        etherBridge.pause();
        assertEq(etherBridge.paused(), true);

        // Unpause and verify bridge is unpaused
        etherBridge.unpause();
        assertEq(etherBridge.paused(), false);
    }

    function test_EtherBridge_OnlyAdminCanCallPause() public {
        // Admin authority cannot pause because not yet granted role
        vm.prank(adminAuthority);
        vm.expectRevert("Only an admin can call this method.");
        etherBridge.pause();

        // Grant admin role to admin and revoke deploy authority admin role
        etherBridge.grantRole(etherBridge.DEFAULT_ADMIN_ROLE(), adminAuthority);
        etherBridge.revokeRole(etherBridge.DEFAULT_ADMIN_ROLE(), deployAuthority);

        // Have admin authority pause and verify the contract is paused
        vm.prank(adminAuthority);
        etherBridge.pause();
        vm.stopPrank();
        assertEq(etherBridge.paused(), true);
    }

    // Pausable
    function test_EtherBridge_DepositWhenPaused() public {
        // Pause the bridge
        assertEq(etherBridge.paused(), false);
        etherBridge.pause();
        assertEq(etherBridge.paused(), true);

        // Attempt to deposit should fail
        uint256 depositAmount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        etherBridge.deposit{value: depositAmount}(recipient, depositAmount);

        // Note: Strange error which may have a bug in foundry or related to optimizations
        // If you replace this line from above:
        //    etherBridge.deposit{value: depositAmount}(recipient, depositAmount);
        // With the following line:
        //   etherBridge.deposit{value: etherBridge.MIN_DEPOSIT_AMOUNT()}(recipient,  etherBridge.MIN_DEPOSIT_AMOUNT());
        // It will fail. The reason for this failure is not clear.
    }

    // Deposit Functionality
    function test_EtherBridge_DepositSuccess() public {
        // Verify initial balance in treasury is 0 and etherbridge isn't paused
        assertEq(treasuryAddress.balance, 0);
        assertEq(etherBridge.paused(), false);

        // Expect deposit event
        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectEmit(true, true, true, true);
        emit Deposited(deployAuthority, recipient, amount);

        // Perform deposit and verify balance in treasury
        etherBridge.deposit{value: amount}(recipient, amount);
        assertEq(treasuryAddress.balance, amount);

        // Expect another deposit event
        uint256 amount2 = etherBridge.MIN_DEPOSIT() + 1 gwei;
        vm.expectEmit(true, true, true, true);
        emit Deposited(deployAuthority, recipient, amount2);

        // Perform another deposit and verify balance in treasury
        etherBridge.deposit{value: amount2}(recipient, amount2);
        assertEq(treasuryAddress.balance, amount + amount2);
    }

    function test_EtherBridge_DepositFailureOnLowAmount() public {
        uint256 amount = etherBridge.MIN_DEPOSIT() - 1 gwei;
        vm.expectRevert("Deposit amount must be greater than equal to the minimum wei amount");
        etherBridge.deposit{value: amount}(recipient, amount);
    }

    function test_EtherBridge_DepositFailureOnFractionalGweiDust() public {
        uint256 amount = etherBridge.MIN_DEPOSIT() - 1 wei;
        vm.expectRevert("Deposit msg.value must not have a fractional gwei value");
        etherBridge.deposit{value: amount}(recipient, amount);
    }

    function test_EtherBridge_DepositFailureUninitializedRecipient() public {
        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert("CommonUtility: empty bytes32");
        etherBridge.deposit{value: amount}(bytes32(0), amount);
    }

    function test_EtherBridge_DepositMismatchValueAndAmount() public {
        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert("Deposit amount and msg.value must be equal");
        etherBridge.deposit{value: amount}(recipient, amount + 1 wei);
        vm.expectRevert("Deposit amount and msg.value must be equal");
        etherBridge.deposit{value: amount + 1 wei}(recipient, amount);
    }

    function test_EtherBridge_TreasuryLockRevert() public {
        MockTreasury t = MockTreasury(treasuryAddress);
        t.setFailure(true);

        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert("Transfer failed");
        etherBridge.deposit{value: amount}(recipient, amount);
    }

    function test_EtherBridge_MailboxSendMessageFalse() public {
        MockMailbox m = MockMailbox(mailboxAddress);
        m.setFalse(true);

        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert("Unable to forward deposit message to Mailbox");
        etherBridge.deposit{value: amount}(recipient, amount);
    }

    function test_EtherBridge_MailboxSendMessageRevert() public {
        MockMailbox m = MockMailbox(mailboxAddress);
        m.setFailure(true);

        uint256 amount = etherBridge.MIN_DEPOSIT();
        vm.expectRevert("MockMailbox revert");
        etherBridge.deposit{value: amount}(recipient, amount);
    }

    function test_EtherBridge_DepositReentrancyAttack() public {
        // TODO
    }
}
