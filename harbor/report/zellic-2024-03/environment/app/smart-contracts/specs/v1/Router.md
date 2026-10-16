# Router Contract Specification

The Router contract is a critical component in the system designed to facilitate the routing of messages between contracts within a decentralized application, particularly in environments involving inter-chain communication. This document outlines the key functionalities and design principles of the Router contract, aligning with its implementation in Solidity.

## Overview

The Router operates alongside a Registry contract to determine the appropriate destinations for incoming and outgoing messages. It serves as a middleware that deciphers encoded identifiers to route messages to their respective contracts, ensuring that communication within the network is seamless and efficient.

## Key Features

- **Dynamic Address Resolution:** Utilizes a Registry to dynamically resolve contract addresses based on identifiers, allowing for flexible and updatable contract interactions.
- **Security Checks:** Implements checks to ensure that only authorized contracts (specifically, module contracts and the mailbox contract) can initiate certain actions, enhancing the security of message routing.
- **Non-Reentrancy:** Guards against reentrancy attacks, ensuring that the contract's functions cannot be re-entered while they're still executing.

## Initialization

Upon deployment, the Router contract must be initialized with the address of the deployed Registry contract. This setup establishes a link to the Registry, enabling the Router to query contract addresses and types.

function initialize(address registryAddress) public initializer

## Routing Messages

### Incoming Messages

The Router contract defines a method to handle incoming messages, determining the correct contract destination based on an encoded identifier. This process involves decoding the identifier, retrieving the corresponding address from the Registry, and then forwarding the message to the resolved address.

function routeIncomingMessage(bytes calldata encodedIdentifier, bytes calldata message) external payable

### Outgoing Messages

For outgoing messages, the Router retrieves the calling contract's identifier from the Registry, encodes this identifier, and forwards the message to the Mailbox contract for external communication.

function routeOutgoingMessage(bytes calldata message) external payable

## Security Measures

- **Module Contract Verification:** To ensure that only legitimate module contracts can route outgoing messages, the Router employs a verification mechanism to confirm the contract type through the Registry.
- **Mailbox Contract Verification:** Similarly, incoming messages are accepted only from the authorized Mailbox contract, ensuring that external communications are securely managed.

## Upgradeability

The Router contract is designed to be upgradeable using the UUPS (Universal Upgradeable Proxy Standard) pattern. This feature allows for future improvements and modifications to the contract's logic without the need for redeployment.

## Conclusion

The Router contract is an essential building block for developing decentralized applications that require complex message routing and contract interaction. By leveraging a dynamic Registry for address resolution and enforcing strict security protocols, the Router facilitates efficient and secure communication across different contracts and blockchain networks.
