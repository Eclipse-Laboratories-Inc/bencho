pragma solidity 0.8.21;

/// @title IEtherBridge
/// @notice Interface for a bridge contract that handles deposits and withdraws of Ether.
interface IEtherBridge {
    /// @notice Contains deposit details sent to the target rollup chain.
    /// @param sender The address which provided the Ether to deposit.
    /// @param recipient The encoded address for the destination on the target chain.
    /// @param amount The amount of Ether to be deposited.
    /// @param fee The transaction fee.
    struct DepositMessage {
        address sender;
        bytes32 recipient;
        uint256 amount;
        uint256 fee;
    }

    /// @notice Contains withdrawal details to allow Ether be be withdrawn from this chain.
    /// @param sender The encoded address on the rollup chain initiating the withdrawal.
    /// @param recipient The address which will be able to unlock and receive Ether.
    /// @param amount The amount of Ether to be withdrawn.
    struct WithdrawMessage {
        bytes32 sender;
        address recipient;
        uint256 amount;
    }

    /// @notice Emitted when Ether is successfully deposited.
    /// @param sender The address of the user who made the deposit.
    /// @param recipient The encoded destination address who receives Ether on the target chain.
    /// @param amount The amount of Ether deposited.
    /// @param fee The transaction fee.
    event Deposited(address indexed sender, bytes32 indexed recipient, uint256 amount, uint256 fee);

    /// @notice Emitted when Ether is successfully withdrawn.
    /// @param sender The address on the rollup chain that initiated the withdrawal.
    /// @param recipient The Ethereum mainnet address receiving the Ether.
    /// @param amount The amount of Ether withdrawn, denominated in wei.
    event Withdrawn(bytes32 indexed sender, address indexed recipient, uint256 amount);

    /// @notice Allows users to deposit ether to the target chain.
    /// @dev Accepts Ether along with the deposit message. Emits the `Deposited` event upon success.
    /// @param recipient The recipient on target chain of the deposit
    /// @param amount The amount of wei to deposit.
    /// @param fee The fee provided to process the deposit
    function deposit(bytes32 recipient, uint256 amount, uint256 fee) external payable;

    /// @notice Initiates a withdrawal of locked Ether to the recipient.
    /// @dev Emits the `Withdrawn` event upon successful processing of the withdrawal request.
    /// @param message The `WithdrawMessage` containing the withdrawal details.
    function withdraw(WithdrawMessage calldata message) external;

    /// @notice Retrieves the current balance of locked Ether.
    /// @return balance The balance of the locked Ether.
    function getBalance() external view returns (uint256 balance);

    /// @notice Retrieves the current balance of total Ether fees.
    /// @return balance The balance of the total Ether fees.
    function getFeeBalance() external view returns (uint256 balance);

    /// @notice Estimates the minimum fee required to deposit.
    /// @return fee The current estimate of the transaction fee.
    function estimateFee() external view returns (uint256 fee);

    /// @dev Get the minimum deposit amount allowed.
    /// @return amount The minimum deposit amount.
    function minDepositAmount() external view returns (uint256 amount);
}
