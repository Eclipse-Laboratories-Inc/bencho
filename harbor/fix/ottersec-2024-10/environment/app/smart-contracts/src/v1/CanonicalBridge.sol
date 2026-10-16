// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ICanonicalBridge } from "./interfaces/ICanonicalBridge.sol";
import { ITreasury } from "./interfaces/ITreasury.sol";
import { ISemVer } from "./interfaces/ISemVer.sol";

/// @title CanonicalBridge
/// @dev A bridge contract for depositing and withdrawing ether to and from the Eclipse rollup.
contract CanonicalBridge is
    ICanonicalBridge,
    ISemVer,
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    address private constant NULL_ADDRESS = address(0);
    bytes32 private constant NULL_BYTES32 = bytes32(0);
    bytes private constant NULL_BYTES = "";
    uint256 private constant NEVER = type(uint256).max;
    uint256 private constant MIN_DEPOSIT_LAMPORTS = 2_000_000;
    uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;
    uint256 private constant DEFAULT_FRAUD_WINDOW_DURATION = 7 days;
    uint256 private constant MIN_FRAUD_WINDOW_DURATION = 1 days;
    uint256 private constant PRECISION = 1e18;
    uint8 private constant MAJOR_VERSION = 2;
    uint8 private constant MINOR_VERSION = 0;
    uint8 private constant PATCH_VERSION = 0;

    bytes32 public constant override PAUSER_ROLE = keccak256("Pauser");
    bytes32 public constant override STARTER_ROLE = keccak256("Starter");
    bytes32 public constant override WITHDRAW_AUTHORITY_ROLE = keccak256("WithdrawAuthority");
    bytes32 public constant override WITHDRAW_CANCELLER_ROLE = keccak256("WithdrawCanceller");
    bytes32 public constant override FRAUD_WINDOW_SETTER_ROLE = keccak256("FraudWindowSetter");
    bytes32 public constant override ETHER_BRIDGE_ID = keccak256("EtherBridge");
    uint256 public constant override MIN_DEPOSIT = MIN_DEPOSIT_LAMPORTS * WEI_PER_LAMPORT;
    address public immutable override TREASURY;

    uint256 public override fraudWindowDuration = 7 days;
    mapping (bytes32 withdrawMessageHash => uint256 startTime) public override startTime;
    mapping (uint64 withdrawMessageId => bool seen) public override withdrawMsgIdProcessed;

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @dev Ensures that bytes32 data is initialized with data.
    modifier bytes32Initialized(bytes32 _data) {
        if(_data == NULL_BYTES32) revert EmptyBytes32();
        _;
    }

    /// @dev Ensures the deposit amount and msg.value are valid, equal and they are >= to the min deposit amount.
    /// @param amountWei The amount to be deposited.
    modifier validDepositAmount(uint256 amountWei) {
        if (msg.value != amountWei) revert CanonicalBridgeTransactionRejected(0, "Deposit amount mismatch");
        if (msg.value % WEI_PER_LAMPORT != 0) revert CanonicalBridgeTransactionRejected(0, "Fractional value not allowed");
        if (msg.value < MIN_DEPOSIT) revert CanonicalBridgeTransactionRejected(0, "Deposit less than minimum");
        _;
    }

    /// @dev Ensure that withdraw messages are complete.
    modifier validWithdrawMessage(WithdrawMessage memory message) {
        if (message.from == NULL_BYTES32) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "Null message.from");
        }
        if (message.destination == NULL_ADDRESS) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "Null message.destination");
        }
        if (message.amountWei == 0) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.amountWei is 0");
        }
        if (message.withdrawId == 0) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.withdrawId is 0");
        }
        if (message.feeWei > message.amountWei) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee exceeds message.amount");
        }
        _;
    }

    /// @dev Constructor that initializes the contract.
    constructor(address owner, address treasuryAddress) {
        /// @dev The owner receives default ACL-admin role that controls access to the
        /// operational roles that follow.
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        /// @dev These assignments are conveniences, since the owner now has user admin authority.
        _grantRole(PAUSER_ROLE, owner);
        _grantRole(STARTER_ROLE, owner);
        _grantRole(WITHDRAW_AUTHORITY_ROLE, owner);
        _grantRole(WITHDRAW_CANCELLER_ROLE, owner);
        _grantRole(FRAUD_WINDOW_SETTER_ROLE, owner);

        TREASURY = treasuryAddress;
        emit Deployed(msg.sender, owner, treasuryAddress);
        _setFraudWindowDuration(DEFAULT_FRAUD_WINDOW_DURATION);
    }

    /// @inheritdoc ICanonicalBridge
    function withdrawMessageStatus(
        WithdrawMessage calldata message
    )
        external
        view
        override
        validWithdrawMessage(message)
        returns (WithdrawStatus)
    {
        return withdrawMessageStatus(withdrawMessageHash(message));
    }

    /// @inheritdoc ICanonicalBridge
    function withdrawMessageStatus(bytes32 messageHash) public view override returns (WithdrawStatus) {
        uint256 startTime_ = startTime[messageHash];
        if (startTime_ == 0) return WithdrawStatus.UNKNOWN;
        if (startTime_ == NEVER) return WithdrawStatus.CLOSED;
        if (startTime_ > block.timestamp) return WithdrawStatus.PROCESSING;
        return WithdrawStatus.PENDING;
    }

    /// @inheritdoc ICanonicalBridge
    function withdrawMessageHash(WithdrawMessage memory message) public pure override returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    /// @inheritdoc ISemVer
    /// @dev Retrieves the constant version details of the smart contract.
    function getVersionComponents() public pure override returns (Version memory) {
        return Version(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION);
    }

    // Operations

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled, pausible
    function deposit(bytes32 recipient, uint256 amountWei)
        external
        payable
        virtual
        override
        whenNotPaused
        bytes32Initialized(recipient)
        validDepositAmount(amountWei)
        nonReentrant
    {
        bool success;
        (success,) = payable(address(TREASURY)).call{value: amountWei}(abi.encodeWithSignature("depositEth()"));
        if (!success) revert CanonicalBridgeTransactionRejected(0, "failed to transfer funds to the treasury");

        // Emit deposit message
        uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
        emit Deposited(msg.sender, recipient, amountWei, amountGwei);
    }

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled, pausible
    function authorizeWithdraws(
        WithdrawMessage[] calldata messages
    )
        external
        override
        whenNotPaused
        onlyRole(WITHDRAW_AUTHORITY_ROLE)
    {
        for (uint256 i = 0; i < messages.length; i++) {
            _authorizeWithdraw(messages[i]);
        }
    }

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled, pausible
    function authorizeWithdraw(
        WithdrawMessage calldata message
    )
        external
        override
        whenNotPaused
        onlyRole(WITHDRAW_AUTHORITY_ROLE)
    {
        _authorizeWithdraw(message);
    }

    /// @notice Inserts a withdraw authorization with a start time after the fraud window.
    /// @param message The message to record.
    /// @dev Message must pass validation rules.
    function _authorizeWithdraw(
        WithdrawMessage memory message
    )
        private
        validWithdrawMessage(message)
    {
        bytes32 messageHash = withdrawMessageHash(message);
        uint256 messageStartTime = block.timestamp + fraudWindowDuration;
        if (withdrawMessageStatus(messageHash) != WithdrawStatus.UNKNOWN) {
            revert CanonicalBridgeTransactionRejected(message.withdrawId, "Message already exists");
        }
        startTime[messageHash] = messageStartTime;
        withdrawMsgIdProcessed[message.withdrawId] = true;
        emit WithdrawAuthorized(
            msg.sender,
            message,
            messageHash,
            messageStartTime
        );
    }

    /// @inheritdoc ICanonicalBridge
    /// @dev Pausible
    function claimWithdrawal(
        WithdrawMessage calldata message
    )
        external
        override
        whenNotPaused
        validWithdrawMessage(message)
    {
        bytes32 messageHash = withdrawMessageHash(message);
        if (withdrawMessageStatus(messageHash) != WithdrawStatus.PENDING) revert WithdrawUnauthorized();

        // Transfer funds to recipient.
        bool success = ITreasury(TREASURY).withdrawEth(
            message.destination,
            message.amountWei,
            message.feeReceiver,
            message.feeWei
        );
        /// @dev The following condition should never occur and the error should be unreachable code.
        if (!success) revert WithdrawFailed();
        startTime[messageHash] = NEVER;
        emit WithdrawClaimed(message.destination, message.from, messageHash, message);
    }

    // Admin

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled
    function deleteWithdrawMessage(
        WithdrawMessage calldata message
    )
        external
        override
        validWithdrawMessage(message)
        onlyRole(WITHDRAW_CANCELLER_ROLE)
    {
        deleteWithdrawMessage(withdrawMessageHash(message));
        emit WithdrawMessageDeleted(msg.sender, message);
    }

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled
    function deleteWithdrawMessage(bytes32 messageHash) public onlyRole(WITHDRAW_CANCELLER_ROLE) {
        WithdrawStatus status = withdrawMessageStatus(messageHash);
        if (status != WithdrawStatus.PENDING && status != WithdrawStatus.PROCESSING) {
            revert CannotCancel();
        }
        startTime[messageHash] = 0;
        emit WithdrawMessageHashDeleted(msg.sender, messageHash);
    }

    /// @inheritdoc ICanonicalBridge
    /// @dev Access controlled
    function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
        if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
        _setFraudWindowDuration(durationSeconds);
    }

    function _setFraudWindowDuration(uint256 durationSeconds) internal {
        fraudWindowDuration = durationSeconds;
        emit FraudWindowSet(msg.sender, durationSeconds);
    }

    /// @dev Pause deposits
    /// @dev Access controlled
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @dev Unpause deposits
    /// @dev Access controlled
    function unpause() external virtual onlyRole(STARTER_ROLE) {
        _unpause();
    }
}
