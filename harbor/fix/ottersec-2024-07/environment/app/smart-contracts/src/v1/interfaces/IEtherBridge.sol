pragma solidity 0.8.21;

/// @title IEtherBridge
/// @notice Interface for a bridge contract that handles deposits of ether.
/// @dev This smart-contract interface supports a peg between gwei and lamports by messaging out ether values in gwei
interface IEtherBridge {
    /// @notice Contains deposit details sent to the target rollup chain.
    /// @param sender The address which provided the ether to deposit.
    /// @param recipient Abi packed bytes32 of a base58-encoded Solana address on the target chain.
    /// @param amountGwei The amount in gwei to be deposited.
    struct DepositMessage {
        address sender;
        bytes32 recipient;
        uint256 amountGwei;
    }

    /// @notice Emitted on a successful deposit.
    /// @param sender The address of the user who made the deposit.
    /// @param recipient The recipient account on the target chain.
    /// @param amountWei The amount in wei deposited.
    event Deposited(address indexed sender, bytes32 indexed recipient, uint256 amountWei);

    /// @notice Allows users to deposit ether to the target chain.
    /// @dev Accepts Ether along with the deposit message. Emits the `Deposited` event upon success.
    /// @param recipient The recipient account on target chain.
    /// @param amountWei The amount in wei to deposit.
    function deposit(bytes32 recipient, uint256 amountWei) external payable;
}
