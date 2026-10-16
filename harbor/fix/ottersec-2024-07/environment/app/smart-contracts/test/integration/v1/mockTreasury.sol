pragma solidity 0.8.21;

import {Treasury} from "../../../src/v1/Treasury.sol";

error Deprecated(address to, uint256 amount);

/// @title MockTreasury
/// @dev Modified version of Treasury for testing purposes.
/// @custom:oz-upgrades-from Treasury
contract MockTreasury is Treasury {
    uint256 public constant V2_CONSTANT = 1337;
    uint256 private something;

    function someFunction() public returns (uint256) {
        something = 5;
        return something;
    }

    /// @notice Override to modify the withdrawal behavior to revert
    /// @param amount The amount of Ether (in wei) to withdraw.
    function emergencyWithdraw(uint256 amount) public virtual override nonReentrant {
        revert Deprecated(msg.sender, amount);
    }

    /// @dev Modified fallback function to allow only etherBridgeAddress to send funds.
    receive() external payable virtual override {
        StorageV1 storage $ = _getStorageV1();
        require(msg.sender == $.etherBridgeAddress, "Unauthorized sender");
        emit TreasuryDeposit(msg.sender, msg.value);
    }
}
