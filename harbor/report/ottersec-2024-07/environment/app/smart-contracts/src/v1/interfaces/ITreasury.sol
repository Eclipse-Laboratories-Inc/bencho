pragma solidity 0.8.21;

/// @title ITreasury
/// @notice Interface for a treasury contract stores ether
/// @dev This interface assumes the implementation will provide a fallback function to receive ether.
interface ITreasury {
    /// @notice Emitted when ether is deposited into the treasury
    /// @param from The address of the sender who deposited ether
    /// @param amount The amount of ether deposited
    event TreasuryDeposit(address indexed from, uint256 amount);

    /// @notice Emitted when ether is withdrawn from the treasury during an emergency withdraw
    /// @param to The address to which ether was sent
    /// @param amount The amount of ether withdrawn
    event EmergencyTreasuryWithdraw(address indexed to, uint256 amount);

    /// @notice Withdraws an 'amount' of ether during emergencies
    /// @param amount The amount of ether to be sent
    function emergencyWithdraw(uint256 amount) external;
}
