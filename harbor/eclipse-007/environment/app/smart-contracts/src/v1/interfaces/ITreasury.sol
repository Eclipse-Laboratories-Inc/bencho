// SPDX-License-Identifier: UNLICENSED 
pragma solidity 0.8.21;

/// @title ITreasury
/// @notice Interface for a treasury contract stores ether.
/// @dev This interface assumes the implementation will provide a fallback function to receive ether.
interface ITreasury {
    /// @notice Emitted when the treasury is re-initialized. 
    /// @param admin Address that initiated the re-initialization. 
    /// @param oldOwner Address that was granted various permissions. 
    event TreasuryReinitialized(address admin, address oldOwner);

    /// @notice Emitted when ether is deposited into the treasury.
    /// @param from The address of the sender who deposited ether.
    /// @param amountWei The amount of ether deposited.
    event TreasuryDeposit(address indexed from, uint256 amountWei);

    /// @notice Emitted when ether is withdrawn from the treasury.
    /// @param authority The sender of the withdrawal instruction.
    /// @param to The address of the sender who received ether.
    /// @param amountWei The amount of ether withdrawn.
    /// @param feeReceiver The address that will receive service fee.
    /// @param feeWei Amount to deduce from gross amount and transfer to feeReceiver.
    event TreasuryWithdrawal(
        address authority, 
        address indexed to, 
        uint256 amountWei,
        address feeReceiver,
        uint256 feeWei
    );

    /// @notice Emitted when ether is withdrawn from the treasury during an emergency withdraw.
    /// @param to The address to which ether was sent.
    /// @param amountWei The amount of ether withdrawn.
    event EmergencyTreasuryWithdraw(address indexed to, uint256 amountWei);

    /// @notice Emitted when withdrawals couldn't be sent to the receiver.
    error TreasuryTransferFailed();

    /// @notice Emitted when withdrawal amount exceeds funds on hand.
    error InsufficientFunds();

    /// @notice Emitted when an input address is a prohibited address(0).
    error ZeroAddress();

    /// @notice Returns the depositor role id.
    function DEPOSITOR_ROLE() external view returns (bytes32);

    /// @notice Returns the withdrawal authority role id.
    function WITHDRAW_AUTHORITY_ROLE() external view returns (bytes32);

    /// @notice Returns the pauser role id.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the starter role id.
    function STARTER_ROLE() external view returns (bytes32);

    /// @notice Returns the upgrader role id.
    function UPGRADER_ROLE() external view returns (bytes32);

    /// @notice Returns the emergency authority role id. 
    function EMERGENCY_ROLE() external view returns (bytes32);

    /// @notice Reinitializes the Treasury. Grants roles to the owner.
    function reinitialize() external;

    /// @notice Accepts eth deposits. 
    function depositEth() external payable;

    /// @notice Withdraws Eth from the Treasury.
    /// @param to The receiver of the withdrawn Eth.
    /// @param amountWei The gross amount of Eth to withdraw.
    /// @param feeReceiver The address that will receive service fee.
    /// @param feeWei Amount to deduce from gross amount and transfer to feeReceiver.
    /// @return success True if the withdrawal was succesful.
    function withdrawEth(
        address to, 
        uint256 amountWei,
        address feeReceiver,
        uint256 feeWei
    ) external returns (bool success);

    /// @notice Stops deposits. Requires the PAUSER_ROLE.
    function pause() external;

    /// @notice Starts deposits. Requires the STARTER_ROLE.
    function unpause() external;

    /// @notice Withdraws an 'amount' of ether during emergencies.
    /// @param amountWei The amount of ether to be sent.
    function emergencyWithdraw(uint256 amountWei) external;
}
