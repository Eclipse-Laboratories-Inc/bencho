# Treasury Specification

## Overview

The Treasury smart contract acts as a secure repository for ether deposits sourced from the EtherBridge contract. It supports controlled emergency withdrawal of funds by an authority.  The contract is pausable for deposits, but not emergency withdraws

## Features

* Secure Storage: Holds ether deposits that can be withdrawn only by authorized governance account in emergencies.
* Ownable2Step Upgradeable Access Control: After deployment authority transfer to governance contract requires accepting ownership by governance entity. 
* Pause and Unpause Functionality: Allows the contract to be paused or unpaused by the owner, providing an emergency stop capability.
* Upgradeability: The contract includes upgradeability through the UUPS pattern, permitting future improvements without disrupting the current functionalities.

## Interface: ITreasury

### Methods

* emergencySithdraw: Unlocks a specified amount of ether and sends it to authority only
* fallback: Allows only the EtherBridge and authority to deposit ether

## Contract: Treasury

### Inheritance

* ITreasury: Defines the core functionality for managing ether withdrawals.
* CommonContainer: An abstract utility contract that contains modifiers for validating inputs 
* Initializable, UUPSUpgradeable: Ensures that the contract can be upgraded after deployment.
* Ownable2StepUpgradeable: Ensures a secure process for transferring contract ownership.
* PausableUpgradeable: Provides mechanisms to pause and unpause contract operations, enhancing security.
* ReentrancyGuardUpgradeable: Protects against reentrancy attacks during withdrawals.
