// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title MockOldTreasury
/// @dev This mock contract simulates an older version of the Treasury contract
/// that uses OwnableUpgradeable from OpenZeppelin and can accept ETH through 
/// a fallback function.
contract OldTreasuryMock is OwnableUpgradeable, UUPSUpgradeable {

    // The constructor-like function that initializes the owner and necessary state variables.
    function initialize(address initialOwner) public initializer {
        // Initialize the OwnableUpgradeable contract and set the initial owner.
        __Ownable_init(initialOwner);
    }

    /// @dev Fallback function to accept ETH deposits and increase the contract's balance.
    receive() external payable {}

    /// @notice Allows the owner to withdraw a specified amount of ETH from the contract.
    function withdraw(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(owner()).transfer(amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override { }
}
