/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import { DeployAndUpgradeFixture } from "../fixtures/DeployAndUpgradeFixture.sol";
import { MockTreasury } from "../mocks/MockTreasury.sol";
import { CanonicalBridge } from "../../src/v1/CanonicalBridge.sol";
import { ICanonicalBridge } from "../../src/v1/interfaces/ICanonicalBridge.sol";
import { Pausable } from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ISemVer } from "../../src/v1/interfaces/ISemVer.sol";

contract CanonicalBridgeTest is DeployAndUpgradeFixture {
    error EmptyBytes32();
    uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;
    bytes32 private constant NULL_BYTES32 = bytes32(0);

    enum InvalidType { EMPTY_FROM, EMPTY_DESTINATION, ZERO_AMOUNT, FEE_EXCEEDS_AMOUNT }

    event Deposited(
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amountWei,
        uint256 amountLamports
    );
    event WithdrawAuthorized(
        address indexed sender,
        ICanonicalBridge.WithdrawMessage message,
        bytes32 indexed messageHash,
        uint256 startTime
    );
    event WithdrawClaimed(
        address indexed receiver,
        bytes32 indexed remoteSender,
        bytes32 indexed messageHash,
        ICanonicalBridge.WithdrawMessage message
    );
    event WithdrawMessageDeleted(
        address authority,
        ICanonicalBridge.WithdrawMessage message
    );
    event WithdrawMessageHashDeleted(address indexed authority, bytes32 indexed messageHash);
    event Paused(address account);
    event Unpaused(address account);

    modifier whenDepositor {
        vm.startPrank(depositor);
        _;
        // vm.stopPrank();
    }

    modifier whenAdmin {
        vm.startPrank(admin);
        _;
        // vm.stopPrank();
    }

    modifier whenPaused {
        vm.startPrank(admin);
        bridgeWithMockedDependencies.pause();
        vm.stopPrank();
        _;
    }

    function setUp () external {
        vm.deal(depositor, 20 ether);
        address admin_ = makeAddr("admin");
        deployMocksAndUpgrade(admin_);
    }

    function test_ConstructorSetsTheOwnerWithDEFAULT_ADMIN_ROLE() external {
        // it sets the owner with DEFAULT_ADMIN_ROLE
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), admin), true);
    }

    function test_ConstructorGrantsPAUSER_ROLEToTheOwner() external {
        // it grants PAUSER_ROLE to the owner
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.PAUSER_ROLE(), admin), true);
    }

    function test_ConstructorGrantsSTARTER_ROLEToTheOwner() external {
        // it grants STARTER_ROLE to the owner
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.STARTER_ROLE(), admin), true);
    }

    function test_ConstructorGrantsWITHDRAW_AUTHORITY_ROLEToTheOwner() external {
        // it grants WITHDRAW_AUTHORITY_ROLE to the owner
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.WITHDRAW_AUTHORITY_ROLE(), admin), true);
    }

    function test_ConstructorGrantsWITHDRAW_CANCELLER_ROLEToTheOwner() external {
        // it grants WITHDRAW_CANCELLER_ROLE to the owner
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.WITHDRAW_CANCELLER_ROLE(), admin), true);
    }

    function test_ConstructorGrantsFRAUD_WINDOW_SETTER_ROLEToTheOwner() external {
        // it grants FRAUD_WINDOW_SETTER_ROLE to the owner
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.hasRole(bridge.FRAUD_WINDOW_SETTER_ROLE(), admin), true);
    }

    function test_ConstructorSetsTheTREASURYAddress() external {
        // it sets the TREASURY address
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.TREASURY(), address(mockTreasury));
    }

    /// @dev Rrturning the bridge to silence un-used variable warning.
    function test_ConstructorEmitsADeployedEvent() external whenDepositor returns (CanonicalBridge bridge) {
        // it emits a Deployed event
        vm.expectEmit(true, true, true, true);
        emit Deployed(depositor, admin, address(mockTreasury));
        bridge = new CanonicalBridge(admin, address(mockTreasury));
    }

    function test_ConstructorSetsTheDefaultFraudWindowDuration() external {
        // it sets the default fraud window duration
        CanonicalBridge bridge = new CanonicalBridge(admin, address(mockTreasury));
        assertEq(bridge.fraudWindowDuration(), 7 days);
    }

    function test_DepositWhenTheContractIsPaused() external whenPaused {
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeWithMockedDependencies.deposit{value: 1 ether}(bytes32(uint256(1)), 1 ether);
    }

    function test_DepositWhenTheRecipientIsNotInitialized() external whenDepositor {
        // it reverts
        vm.expectRevert(EmptyBytes32.selector);
        bridgeWithMockedDependencies.deposit{value: 1 ether}(bytes32(uint256(0)), 1 ether);
    }

    function test_DepositWhenTheDepositAmountDoesNotMatchETHSent() external whenDepositor {
        // it reverts with DepositAmountMismatc
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            0,
            "Deposit amount mismatch"
        ));
        bridgeWithMockedDependencies.deposit{value: 1 ether}(bytes32(uint256(1)), 2 ether);
    }

    function test_DepositWhenTheDepositAmountIsNotDivisibleByWEI_PER_LAMPORT() external whenDepositor {
        // it reverts with FractionalValueNotAllowed
        uint256 amount = 1 ether + 1;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            0,
            "Fractional value not allowed"
        ));
        bridgeWithMockedDependencies.deposit{value: amount}(bytes32(uint256(1)), amount);
    }

    function test_DepositWhenTheDepositAmountIsLessThanMIN_DEPOSIT() external whenDepositor {
        // it reverts with DepositLessThanMinimum
        uint256 amount = 1 * WEI_PER_LAMPORT; // less than MIN_DEPOSIT
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            0,
            "Deposit less than minimum"
        ));
        bridgeWithMockedDependencies.deposit{value: amount}(bytes32(uint256(1)), amount);
    }

    function test_DepositWhenTheTransferToTREASURYFails() external whenDepositor {
        mockTreasury.mockDepositEth(false);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            0,
            "failed to transfer funds to the treasury"
        ));
        bridgeWithMockedDependencies.deposit{value: 1 ether}(bytes32(uint256(1)), 1 ether);
        mockTreasury.mockDepositEth(true);
    }

    function test_DepositWhenAllDepositConditionsAreMet() external whenDepositor {
        uint256 amount = 1 ether;
        uint256 amountGWei = amount / WEI_PER_LAMPORT;

        vm.expectEmit(true, true, true, true);
        emit Deposited(depositor, bytes32(uint256(1)), amount, amountGWei);
        bridgeWithMockedDependencies.deposit{value: amount}(bytes32(uint256(1)), amount);
    }

    function createWithdrawMessages() internal view returns(ICanonicalBridge.WithdrawMessage[] memory messages) {
        // createWithdrawMessages
        messages = new ICanonicalBridge.WithdrawMessage[](2);

        // fill message[0]
        messages[0].from = bytes32(uint256(1));
        messages[0].destination = depositor;
        messages[0].amountWei = 1 ether;
        messages[0].withdrawId = 1;
        messages[0].feeReceiver = deployer;
        messages[0].feeWei = 0.1 ether;

        // fill message[1]
        messages[1].from = bytes32(uint256(2));
        messages[1].destination = depositor;
        messages[1].amountWei = 2 ether;
        messages[1].withdrawId = 2;
        messages[1].feeReceiver = deployer;
        messages[1].feeWei = 0.2 ether;
    }

    function test_AuthorizeWithdrawsWhenTheContractIsPausedForAuthorizeWithdraws() external whenPaused whenAdmin {
        // it reverts
        ICanonicalBridge.WithdrawMessage[] memory messages = createWithdrawMessages();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeWithMockedDependencies.authorizeWithdraws(messages);
    }

    function test_AuthorizeWithdrawsWhenTheCallerIsNotWITHDRAW_AUTHORITY_ROLEForAuthorizeWithdraws()
        external
        whenDepositor
    {
        // it reverts with AccessControlUnauthorizedAccount
        ICanonicalBridge.WithdrawMessage[] memory messages = createWithdrawMessages();

        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.WITHDRAW_AUTHORITY_ROLE()
        ));
        bridgeWithMockedDependencies.authorizeWithdraws(messages);
    }

    function test_AuthorizeWithdrawsWhenAllAuthorizeWithdrawsConditionsAreMet() external whenAdmin {
        // it decodes the messages
        // it calls _authorizeWithdraw for each message
        ICanonicalBridge.WithdrawMessage[] memory messages = createWithdrawMessages();

        for (uint256 i = 0; i < messages.length; i++) {
            uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
            bytes32 messageHash = keccak256(abi.encode(messages[i]));

            vm.expectEmit(true, true, true, true);
            emit WithdrawAuthorized(
                admin,
                messages[i],
                messageHash,
                messageStartTime
            );
        }
        bridgeWithMockedDependencies.authorizeWithdraws(messages);
    }

    function test_AuthorizeWithdrawWhenTheContractIsPausedForAuthorizeWithdraw() external whenAdmin {
        // it reverts
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);

        bridgeWithMockedDependencies.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        bridgeWithMockedDependencies.unpause();
    }

    function test_AuthorizeWithdrawWhenTheCallerIsNotWITHDRAW_AUTHORITY_ROLEForAuthorizeWithdraw() external whenDepositor {
        // it reverts with AccessControlUnauthorizedAccount
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);
        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.WITHDRAW_AUTHORITY_ROLE()
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);
    }

    function test_AuthorizeWithdrawWhenTheWithdrawIsAlreadyAuthorized() external whenAdmin {
        // it reverts with WithdrawAlreadyAuthorized
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        bytes32 messageHash = keccak256(abi.encode(message));

        emit WithdrawAuthorized(
            admin,
            message,
            messageHash,
            messageStartTime
        );
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "Message already exists"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);
    }

    function test_AuthorizeWithdrawWhenTheWithdrawMessageIsInvalid() external whenAdmin {
        // it reverts with InvalidWithdrawMessage
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);

        // normal pass
        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(message);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        // zero from address
        message.from = bytes32(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "Null message.from"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        // zero destination address
        message = createValidWithdrawMessage(depositor);
        message.destination = address(0);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "Null message.destination"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        // zero amount
        message = createValidWithdrawMessage(depositor);
        message.amountWei = 0;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.amountWei is 0"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        // zero withdrawId
        message = createValidWithdrawMessage(depositor);
        message.withdrawId = 0;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.withdrawId is 0"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        // feeWei is greater than amountWei
        message = createValidWithdrawMessage(depositor);
        message.feeWei = 2 ether;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.fee exceeds message.amount"
        ));
        bridgeWithMockedDependencies.authorizeWithdraw(message);
    }

    function test_AuthorizeWithdrawWhenAllAuthorizeWithdrawConditionsAreMet() external whenAdmin {
        // it decodes the message
        // it calls _authorizeWithdraw for the message
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        bytes32 messageHash = keccak256(abi.encode(message));

        vm.expectEmit(true, true, true, true);
        emit WithdrawAuthorized(
            admin,
            message,
            messageHash,
            messageStartTime
        );
        bridgeWithMockedDependencies.authorizeWithdraw(message);
    }

    function test_RevertWhenWithdrawMessageIsInvalid() external {
        CanonicalBridge.WithdrawMessage memory invalidMessage;

        invalidMessage = createInvalidWithdrawMessage(depositor, InvalidType.EMPTY_FROM);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            invalidMessage.withdrawId,
            "Null message.from"
        ));
        canonicalBridge.withdrawMessageStatus(invalidMessage);

        invalidMessage = createInvalidWithdrawMessage(depositor, InvalidType.EMPTY_DESTINATION);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            invalidMessage.withdrawId,
            "Null message.destination"
        ));
        canonicalBridge.withdrawMessageStatus(invalidMessage);
        
        invalidMessage = createInvalidWithdrawMessage(depositor, InvalidType.ZERO_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            invalidMessage.withdrawId,
            "message.amountWei is 0"
        ));
        canonicalBridge.withdrawMessageStatus(invalidMessage);

        invalidMessage = createInvalidWithdrawMessage(depositor, InvalidType.FEE_EXCEEDS_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            invalidMessage.withdrawId,
            "message.fee exceeds message.amount"
        ));
        canonicalBridge.withdrawMessageStatus(invalidMessage);
    }

    function createInvalidWithdrawMessage(
        address claimer,
        InvalidType problem
    )
        internal
        returns(ICanonicalBridge.WithdrawMessage memory)
    {
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(claimer);
        if ( problem == InvalidType. EMPTY_FROM ) {
            message.from = NULL_BYTES32;
        } else if (problem == InvalidType.EMPTY_DESTINATION) {
            message.destination = NULL_ADDRESS;
        } else if (problem == InvalidType.ZERO_AMOUNT) {
            message.amountWei = 0;
        } else if (problem == InvalidType.FEE_EXCEEDS_AMOUNT) {
            message.amountWei = 1;
            message.feeWei = 2;
        } else {
            revert("Internal test logic error");
        }
        return message;
    }

    function createValidWithdrawMessage(address claimer) internal returns(ICanonicalBridge.WithdrawMessage memory) {
        /// @dev pseudo-random meaningless unique id
        uint256 timeInterval = 1 minutes;
        vm.warp(block.timestamp + timeInterval);
        uint64 id = uint64(uint256(keccak256(abi.encodePacked(block.timestamp))));

        ICanonicalBridge.WithdrawMessage memory message;
        message.from = bytes32(uint256(1));
        message.destination = claimer;
        message.amountWei = 1 ether;
        message.withdrawId = id;
        message.feeReceiver = deployer;
        message.feeWei = 0.1 ether;

        return message;
    }

    function prepareWithdraw(address claimer) internal whenAdmin returns(ICanonicalBridge.WithdrawMessage memory) {
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(claimer);

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        bytes32 messageHash = keccak256(abi.encode(message));

        emit WithdrawAuthorized(
            admin,
            message,
            messageHash,
            messageStartTime
        );
        bridgeWithMockedDependencies.authorizeWithdraw(message);

        return message;
    }

    function test_claimWithdrawalalWhenTheContractIsPausedForclaimWithdrawal() external {
        // it reverts
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);

        vm.startPrank(admin);
        bridgeWithMockedDependencies.pause();
        vm.stopPrank();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        bridgeWithMockedDependencies.claimWithdrawal(message);
    }

    function test_claimWithdrawalWhenTheWithdrawIsNotAuthorized() external {
        // it reverts with WithdrawUnauthorized
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);
        vm.expectRevert(ICanonicalBridge.WithdrawUnauthorized.selector);
        bridgeWithMockedDependencies.claimWithdrawal(message);
    }

    function test_claimWithdrawalWhenTheWithdrawFails() external {
        // it reverts with WithdrawFailed
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);
        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        mockTreasury.mockWithdrawEth(false, true);

        vm.expectRevert(ICanonicalBridge.WithdrawFailed.selector);
        bridgeWithMockedDependencies.claimWithdrawal(message);

        mockTreasury.mockWithdrawEth(true, true);
    }

    function test_claimWithdrawalWhenAllclaimWithdrawalConditionsAreMet() external {
        // it transfers funds to the recipient
        // it transfers the fee to the fee receiver
        // it marks the withdraw as claimed
        // it emits a WithdrawClaimed event
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        vm.expectEmit(true, true, true, true);
        emit WithdrawClaimed(
            depositor,
            message.from,
            keccak256(abi.encode(message)),
            message
        );
        bridgeWithMockedDependencies.claimWithdrawal(message);
    }

    function test_DeleteWithdrawMessageWhenTheCallerIsNotWITHDRAW_CANCELLER_ROLEForMessageDeletion()
        external
    {
        // it reverts with AccessControlUnauthorizedAccount
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);

        vm.startPrank(depositor);

        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.WITHDRAW_CANCELLER_ROLE()
        ));
        bridgeWithMockedDependencies.deleteWithdrawMessage(message);

        vm.stopPrank();
    }

    function test_DeleteWithdrawMessageWhenTheWithdrawMessageIsInvalid() external whenAdmin {
        // it reverts with InvalidWithdrawMessage
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CannotCancel.selector
        ));
        bridgeWithMockedDependencies.deleteWithdrawMessage(message);
    }

    function test_DeleteWithdrawMessageWhenAllMessageDeletionConditionsAreMet() external {
        // it deletes the withdraw message

        // 1. Cancelling processing.
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);

        vm.startPrank(admin);

        // it emits a WithdrawMessageDeleted event
        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageDeleted(
            admin,
            message
        );
        bridgeWithMockedDependencies.deleteWithdrawMessage(message);

        vm.stopPrank();

        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        vm.expectRevert(ICanonicalBridge.WithdrawUnauthorized.selector);
        bridgeWithMockedDependencies.claimWithdrawal(message);

        // 2. Cancelling pending. admin repeat the message.
        ICanonicalBridge.WithdrawMessage memory message2 = prepareWithdraw(depositor);

        messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message2)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.PENDING));

        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageDeleted(
            admin,
            message2
        );
        bridgeWithMockedDependencies.deleteWithdrawMessage(message2);

        vm.stopPrank();
    }

    function test_DeleteWithdrawMessageWhenTheCallerIsNotWITHDRAW_CANCELLER_ROLEForHashDeletion()
        external
    {
        // it reverts with AccessControlUnauthorizedAccount
        bytes32 messageHash = keccak256(abi.encode(prepareWithdraw(depositor)));

        vm.startPrank(depositor);

        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.WITHDRAW_CANCELLER_ROLE()
        ));
        bridgeWithMockedDependencies.deleteWithdrawMessage(messageHash);

        vm.stopPrank();
    }

    function test_DeleteWithdrawMessageWhenTheWithdrawStatusDoesNotExist() external {
        // it reverts with CannotCancel
        // UNKNOWN status
        bytes32 messageHash = keccak256(abi.encode("Random message"));
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CannotCancel.selector
        ));
        bridgeWithMockedDependencies.deleteWithdrawMessage(messageHash);

        vm.stopPrank();

        // CLOSE
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);
        messageHash = keccak256(abi.encode(message));

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        // it claims the withdraw
        bridgeWithMockedDependencies.claimWithdrawal(message);

        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(messageHash);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.CLOSED));

        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CannotCancel.selector
        ));
        bridgeWithMockedDependencies.deleteWithdrawMessage(messageHash);

        vm.stopPrank();
    }

    function test_DeleteWithdrawMessageWhenAllHashDeletionConditionsAreMet() external {
        // it deletes the withdraw message
        // it emits a WithdrawMessageHashDeleted event

        // 1. Cancelling processing.
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);
        bytes32 messageHash = keccak256(abi.encode(message));

        vm.startPrank(admin);

        // it emits a WithdrawMessageDeleted event
        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageHashDeleted(
            admin,
            messageHash
        );
        bridgeWithMockedDependencies.deleteWithdrawMessage(messageHash);

        vm.stopPrank();

        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(messageHash);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        status = bridgeWithMockedDependencies.withdrawMessageStatus(messageHash);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        vm.expectRevert(ICanonicalBridge.WithdrawUnauthorized.selector);
        bridgeWithMockedDependencies.claimWithdrawal(message);

        // 2. Cancelling pending. admin repeat the message.
        ICanonicalBridge.WithdrawMessage memory message2 = prepareWithdraw(depositor);

        messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();
        vm.warp(messageStartTime);

        messageHash = keccak256(abi.encode(message2));

        status = bridgeWithMockedDependencies.withdrawMessageStatus(messageHash);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.PENDING));

        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageHashDeleted(
            admin,
            messageHash
        );
        bridgeWithMockedDependencies.deleteWithdrawMessage(messageHash);

        vm.stopPrank();
    }

    function test_SetFraudWindowDurationWhenTheCallerIsNotFRAUD_WINDOW_SETTER_ROLE() external whenDepositor {
        // it reverts with AccessControlUnauthorizedAccount
        uint256 duration = 1 days;

        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.FRAUD_WINDOW_SETTER_ROLE()
        ));
        bridgeWithMockedDependencies.setFraudWindowDuration(duration);
    }

    function test_SetFraudWindowDurationWhenTheDurationIsLessThanMIN_fraudWindowDuration() external whenAdmin {
        // it reverts with DurationTooShort
        uint256 duration = 1 hours;

        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.DurationTooShort.selector
        ));
        bridgeWithMockedDependencies.setFraudWindowDuration(duration);
    }

    function test_SetFraudWindowDurationWhenAllSetFraudWindowDurationConditionsAreMet() external whenAdmin {
        // it sets the new fraud window duration
        // it emits a FraudWindowSet event
        uint256 duration = 1 days;
        vm.expectEmit(true, true, true, true);
        emit FraudWindowSet(admin, duration);
        bridgeWithMockedDependencies.setFraudWindowDuration(duration);
    }

    function test_PauseWhenTheCallerIsNotPAUSER_ROLE() external whenDepositor {
        // it reverts with AccessControlUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.PAUSER_ROLE()
        ));
        bridgeWithMockedDependencies.pause();
    }

    function test_PauseWhenTheCallerHasPAUSER_ROLE() external whenAdmin {
        // it pauses the contract
        // it emits a Paused event
        vm.expectEmit(true, true, true, true);
        emit Paused(admin);
        bridgeWithMockedDependencies.pause();

        assertEq(bridgeWithMockedDependencies.paused(), true);
        bridgeWithMockedDependencies.unpause();
    }

    function test_UnpauseWhenTheCallerIsNotSTARTER_ROLE() external {
        // it reverts with AccessControlUnauthorizedAccount
        // puase first
        vm.startPrank(admin);
        bridgeWithMockedDependencies.pause();
        vm.stopPrank();

        vm.startPrank(depositor);

        vm.expectRevert(abi.encodeWithSelector(
            AccessControlUnauthorizedAccount.selector,
            depositor,
            bridgeWithMockedDependencies.STARTER_ROLE()
        ));

        bridgeWithMockedDependencies.unpause();

        vm.stopPrank();

        vm.startPrank(admin);
        bridgeWithMockedDependencies.unpause();
        vm.stopPrank();
    }

    function test_UnpauseWhenTheCallerHasSTARTER_ROLE() external whenAdmin {
        // it unpauses the contract
        // it emits an Unpaused event
        // pause first
        bridgeWithMockedDependencies.pause();
        vm.expectEmit(true, true, true, true);
        emit Unpaused(admin);
        bridgeWithMockedDependencies.unpause();
        assertEq(bridgeWithMockedDependencies.paused(), false);
    }

    function test_WithdrawMessageStatusWhenTheWithdrawMessageIsInvalidForStatusCheck()
        external
    {
        // it reverts with InvalidWithdrawMessage
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);

        // normal pass
        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(message);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));

        // zero from address
        message.from = bytes32(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "Null message.from"
        ));
        bridgeWithMockedDependencies.withdrawMessageStatus(message);

        // zero destination address
        message = createValidWithdrawMessage(depositor);
        message.destination = address(0);
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "Null message.destination"
        ));
        bridgeWithMockedDependencies.withdrawMessageStatus(message);

        // zero amount
        message = createValidWithdrawMessage(depositor);
        message.amountWei = 0;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.amountWei is 0"
        ));
        bridgeWithMockedDependencies.withdrawMessageStatus(message);

        // zero withdrawId
        message = createValidWithdrawMessage(depositor);
        message.withdrawId = 0;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.withdrawId is 0"
        ));
        bridgeWithMockedDependencies.withdrawMessageStatus(message);

        // feeWei is greater than amountWei
        message = createValidWithdrawMessage(depositor);
        message.feeWei = 2 ether;
        vm.expectRevert(abi.encodeWithSelector(
            ICanonicalBridge.CanonicalBridgeTransactionRejected.selector,
            message.withdrawId,
            "message.fee exceeds message.amount"
        ));
        bridgeWithMockedDependencies.withdrawMessageStatus(message);
    }

    function test_WithdrawMessageStatusWhenTheMessageIsValidForStatusCheck() external {
        // it returns the correct withdraw status
        ICanonicalBridge.WithdrawMessage memory message = prepareWithdraw(depositor);
        uint256 messageStartTime = vm.getBlockTimestamp() + bridgeWithMockedDependencies.fraudWindowDuration();

        ICanonicalBridge.WithdrawStatus status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.PROCESSING));

        // duration paased
        vm.warp(messageStartTime);

        status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.PENDING));

        // claim the withdraw
        bridgeWithMockedDependencies.claimWithdrawal(message);

        status = bridgeWithMockedDependencies.withdrawMessageStatus(keccak256(abi.encode(message)));
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.CLOSED));

        // find a message that does not exist
        bytes32 messageHash = keccak256(abi.encode("Random message"));
        status = bridgeWithMockedDependencies.withdrawMessageStatus(messageHash);
        assertEq(uint(status), uint(ICanonicalBridge.WithdrawStatus.UNKNOWN));
    }

    function test_GetVersionComponentsReturnsTheCorrectVersionNumbers() external view {
        // it returns the correct version numbers
        ISemVer.Version memory version = bridgeWithMockedDependencies.getVersionComponents();

        assertEq(version.major, 2);
        assertEq(version.minor, 0);
        assertEq(version.patch, 0);
    }

    function test_withdrawMessageHashReturnsTheHashMatchesTheMessage() external {
        // it returns the hash of the message
        ICanonicalBridge.WithdrawMessage memory message = createValidWithdrawMessage(depositor);
        bytes32 messageHash = bridgeWithMockedDependencies.withdrawMessageHash(message);

        assertEq(messageHash, keccak256(abi.encode(message)));
    }
}

