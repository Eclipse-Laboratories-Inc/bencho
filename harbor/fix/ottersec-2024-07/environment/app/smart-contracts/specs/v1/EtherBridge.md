# EtherBridge Specification

## Overview

The EtherBridge smart contract is designed for transferring ether (as gwei) between the Ethereum blockchain and the Eclipse rollup. It (will in the future) receive messages from the Mailbox contract for withdraw commitments.  It sends deposit messages to the Mailbox to be relayed across the canonical bridge. 

## Features

* Direct Ethereum to Eclipse Transfers: Facilitates the transfer of ether to the rollup by locking funds in a treasury on Ethereum and signaling these transfers to the Eclipse chain through the Mailbox contract.
* Security and Validation: Implements checks to ensure that transactions meet specified conditions for min deposit amount.  
* Role-Based Access Control and Modularity: Leverages roles to control access to critical functions, with specific allowances for operations initiated by the Mailbox.
* Upgradeability: Supports upgrades via the UUPS pattern, allowing future enhancements without disrupting existing functionality.

The minimum deposit amount is based on the minimum data that can be published on Eclipse which is rent exempt.  See source code for details. 

## Interface: IEtherBridge

### Events

* Deposited: Emitted when ether is successfully deposited into the treasury and a corresponding message is sent to Eclipse.

### Methods

* deposit: Locks a specified amount of ether in the treasury and routes a deposit message through the Mailbox to Eclipse.
* pause/unpause: Disables and enables deposits to the treasury.  This is useful for emergencies and upgrades. 

## Contract: EtherBridge

### Inheritance

* IEtherBridge: Interface defining the contract's core functionalities.
* Initializable, UUPSUpgradeable: Ensures that the contract can be upgraded post-deployment.
* AccessControlUpgradeable: Manages roles for accessing restricted functions.
* PausableUpgradeable: Manages pausing and unpausing deposits. 
* ReentrancyGuardUpgradeable: Prevents reentrant calls to critical functions.

