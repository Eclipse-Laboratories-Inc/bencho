# Mailbox Specification

## Overview
The Mailbox smart contract facilitates secure messaging between the Ethereum and Eclipse blockchains. It is designed primarily for allowing users on Ethereum to deposit funds to the Eclipse rollup

It uses a slightly modified version of EIP-6170 which has an additional field for extraData in the event. See interfaces/IMailbox.sol for details.

## Features 
* Cross-Chain Messaging: Supports the transmission of arbitrary messages between Ethereum and Eclipse. A trusted relayer extracts events emitted by this contract and relays them to Eclipse.
* Security and Nonce Management: Implements nonce-based mechanisms to prevent replay attacks, crucial for maintaining message integrity and security across chains.
* Role-Based Access Control: Utilizes role-based permissions to restrict operations to authorized entities, enhancing overall system security. Roles include trusted relayers and registered modules.
* Upgradeability: The contract can be upgraded through the UUPS (Universal Upgradeable Proxy Standard) pattern, allowing for iterative improvements and fixes without state migration.
* Validation: Enforces checks on message sender and chain identifiers.

## Interface: IMailbox

This interface is based on EIP-6170 with minor modifications. These are the modifications:

* Added extraData field in MessageReceived
* Proposing chain-ids be created different than standard suggests: ie via abi.encode(keccak256(abi.encodePacked("Ethereum"))).  
  * This would allow all chain ids to be the same number of bytes size and abi encoded such that its easy to recreate in any programming environment.

### Events
* MessageSent: Emitted when a message is prepared to be sent to another chain. A trusted relayer extracts this event and relays it to Eclipse.
* MessageReceived: Emitted upon the successful receipt and processing of a message from another chain.