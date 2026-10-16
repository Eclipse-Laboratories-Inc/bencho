// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @title NotOldTreasury
/// @dev This mock contract simulates a random, initialized contract that is mistaken for
/// the OldTreasury during the upgrade process. 
contract NotMock is Initializable, UUPSUpgradeable {

    // The constructor-like function that initializes the owner and necessary state variables.
    function initialize() external initializer { }

    function reinitialize() external reinitializer(99) { } 

    function _authorizeUpgrade(address newImplementation) internal override { }
}
