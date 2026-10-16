pragma solidity 0.8.21;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @title Treasury
/// @dev Smart contract allows Ether deposits and withdrawals.
///      This contract is designed to be used as a treasury for storing funds that can only
///      be accessed by the owner (intended to be another smart contract).
contract Treasury is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @dev Initializes the Treasury contract setting the owner.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    /// @dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Allows owner to withdraw funds from the contract to a specific address.
    /// @param to The address to which the funds will be sent.
    /// @param amount The amount of Ether (in wei) to withdraw.
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient funds");
        to.transfer(amount);
    }

    /// @dev Function to receive Ether. msg.data must be empty.
    receive() external payable {}
}
