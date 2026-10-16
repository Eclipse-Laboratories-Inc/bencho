// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/// @title IEtherBridge
/// @notice Interface for a bridge contract that handles deposits of ether.
interface ICanonicalBridge {
    /// @notice Contains deposit details sent to the target rollup chain.
    /// @param sender The address which provided the ether to deposit.
    /// @param recipient Abi packed bytes32 of a base58-encoded Solana address on the target chain.
    /// @param amountGwei The amount deposited in Gwei.
    struct DepositMessage {
        address sender;
        bytes32 recipient;
        uint256 amountGwei;
    }

    /// @notice Contains withdrawl details sent by an authoritative state updater.
    /// @param pubKey Public key of the primary txn signer.
    /// @param destination Receiver who can claim the withdraw.
    /// @param amountWei Amount of wei that can be withdrawn.
    /// @param withdrawId Unique identifier can be used once.
    /// @param feeReceiver The address that will receive the transaction fee.
    /// @param feeWei The amount of fee to deduct from the amountWei.
    struct WithdrawMessage {
        bytes32 from;
        address destination;
        uint256 amountWei;
        uint64 withdrawId;
        address feeReceiver;
        uint256 feeWei;
    }

    enum WithdrawStatus { UNKNOWN, PROCESSING, PENDING, CLOSED }

    /// @notice Emitted from the contract constructor.
    /// @param deployer The deployer address.
    /// @param owner The address that received the default permissions.
    /// @param treasuryAddress The address that will hold received funds.
    event Deployed(address indexed deployer, address owner, address treasuryAddress);

    /// @notice Emitted when the fraud window is set.
    /// @param sender The authority that updated the fraud window.
    /// @param durationSeconds The new fraud window.
    event FraudWindowSet(address indexed sender, uint256 durationSeconds);

    /// @notice Emitted on a successful deposit.
    /// @param sender The address of the user who made the deposit.
    /// @param recipient The recipient account on the target chain.
    /// @param amountWei The amount in wei deposited.
    event Deposited(
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amountWei,
        uint256 amountLamports
    );

    /// @notice Emitted when a withdraw message is accepted.
    /// @param sender The address of the withdraw authority that forwarded the message.
    /// @param message The withdraw message accepted.
    /// @param messageHash The hash of the withdrawMessage.
    /// @param startTime The earliest timestamp when the withdraw can be executed.
    event WithdrawAuthorized(
        address indexed sender, 
        WithdrawMessage message, 
        bytes32 indexed messageHash, 
        uint256 startTime);

    /// @notice Emitted when a withdrawl is claimed and executed.
    /// @param receiver The recipient of the funds who is also the requester.
    /// @param message The withdraw message includes details such as origin and amount.
    /// @param messageHash The hash of the withdrawMessage.
    event WithdrawClaimed(
        address indexed receiver,
        bytes32 indexed remoteSender,
        bytes32 indexed messageHash,
        WithdrawMessage message
    );

    /// @notice Emitted when an authorized withdraw is cancelled, by pre-image.
    /// @param authority The sender to authorized the cancellation.
    /// @param message The withdraw message that was cancelled.
    event WithdrawMessageDeleted(address authority, WithdrawMessage message);

    /// @notice Emitted when an authorized withdraw is cancelled, by hash.
    /// @param authority The sender to authorized the cancellation.
    /// @param messageHash The withdraw message hash that was cancelled.
    event WithdrawMessageHashDeleted(address indexed authority, bytes32 indexed messageHash);

    /// @notice Emitted when a withdraw authorization is cancelled.
    /// @param sender The authority that cancelled with the withdraw.
    /// @param messageHash The hash of the withdraw message that was cancelled.
    event WithdrawCancelled(address indexed sender, bytes32 indexed messageHash);

    /// @notice Emitted when the withdraw authorization is rejected.
    /// @param withdrawId The transactionId that was rejected.
    /// @dev withdrawId is 0 if deposit transaction. It is meaningful if a withdraw transaction or batch.
    error CanonicalBridgeTransactionRejected(uint64 withdrawId, string reason);

    /// @notice Emitted when the requested fraud window is less than the hard-code minimum.
    error DurationTooShort();

    /// @notice Emitted when the Treasury fails to withdraw funds as instructed.
    error WithdrawFailed();

    /// @notice Emitted when an attempted withdraw is unauthorized.
    error WithdrawUnauthorized();

    /// @notice Emitted when an unable to cancel an authorized withdraw.
    /// @dev The authorized withdraw must be in the PENDING state or it cannot be cancelled.
    error CannotCancel();

    /// @notice Emitted when a bytes32 input is empty.
    error EmptyBytes32();

    /// @notice Returns the pauser role id.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the starter role id.
    function STARTER_ROLE() external view returns (bytes32);

    /// @notice Returns the withdraw authority role id.
    function WITHDRAW_AUTHORITY_ROLE() external view returns (bytes32);

    /// @notice Returns the withdraw canceller role id.
    function WITHDRAW_CANCELLER_ROLE() external view returns (bytes32);

    /// @notice Returns the fraud window duration setter role id.
    function FRAUD_WINDOW_SETTER_ROLE() external view returns (bytes32);

    /// @notice Returns the minimum wei required to acquire a single lamport.
    function MIN_DEPOSIT() external view returns (uint256);

    /// @notice Returns the address of the treasury that will receive locked funds.
    function TREASURY() external view returns (address);

    /// @notice Returns the fraud window duration that governs withdraw eligibility.
    function fraudWindowDuration() external view returns (uint256);

    /// @notice Returns the startTime of withdraw eligibility for a withdraw message hash.
    /// @param withdrawMessageHash A hash of a withdraw message.
    /// @dev Eth timestamp format is in seconds. zero is not possible for a withdraw message
    /// with a non-zero amount. 2^^256 means the withdraw has been claimed and can never
    /// be executed again.
    function startTime(bytes32 withdrawMessageHash) external view returns (uint256);

    /// @notice Returns the status of the withdraw message.
    /// @param message The message to check.
    function withdrawMessageStatus(WithdrawMessage calldata message) external view returns (WithdrawStatus);

    /// @notice Returns the status of the withdraw message.
    /// @param messageHash The message to check.
    function withdrawMessageStatus(bytes32 messageHash) external view returns (WithdrawStatus);

    /// @notice Set the duration to delay withdraw eligibility.
    /// @param durationSeconds The delay duration when withdraw messages are accepted.
    function setFraudWindowDuration(uint256 durationSeconds) external;

    /// @notice Allows users to deposit ether to the target chain.
    /// @dev Accepts Ether along with the deposit message. Emits the `Deposited` event upon success.
    /// @param recipient The recipient account on target chain.
    /// @param amountWei The amount in wei to deposit.
    function deposit(bytes32 recipient, uint256 amountWei) external payable;

    /// @notice Establishes permissiom to withdraw funds after the fraud window passes.
    /// @param messages abi.encoded array of Withdraw messages to authorize.
    function authorizeWithdraws(WithdrawMessage[] calldata messages) external;

    /// @notice Establishes permission to withdraw funds after the fraud window passes.
    /// @param message abi.encoded Withdraw message to authorize.
    function authorizeWithdraw(WithdrawMessage calldata message) external;

    /// @notice Allows the receiver to claim an authorized withdraw.
    /// @param message The message to execute.
    function claimWithdrawal(WithdrawMessage calldata message) external;

    /// @notice Allows the fraud authority to cancel a pending withdraw.
    /// @param message The authorized withdraw message to cancel.
    function deleteWithdrawMessage(WithdrawMessage calldata message) external;

    /// @notice Allows the fraud authority to cancel a pending withdraw.
    /// @param messageHash The hash of the authorized withdraw message to cancel.
    function deleteWithdrawMessage(bytes32 messageHash) external;

    /// @notice Returns the hash of a withdraw message.
    /// @param message The message to hash
    function withdrawMessageHash(WithdrawMessage calldata message) external pure returns (bytes32);

    /// @notice Returns true if the withdraw message id has been observed and recorded.
    /// @param withdrawMsgId The message id to inspect.
    function withdrawMsgIdProcessed(uint64 withdrawMsgId) external view returns (bool);
}
