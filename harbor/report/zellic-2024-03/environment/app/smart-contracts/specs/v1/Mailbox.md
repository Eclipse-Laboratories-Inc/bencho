# Mailbox Contract Specification

The Mailbox contract is crucial for facilitating inter-chain communications between Ethereum and Eclipse.  

It is designed to deliver arbitrary cross-chain messages using EIP-6170. 

It includes interfaces for routing messages to destination contracts and managing security parameters to ensure message integrity, authorization and to prevent replay attacks.

## Overview

The Mailbox contract serves as an intermediary for inter-chain communications between the Ethereum settlement layer and a rollup node on the Eclipse chain. 

It currently supports a single trusted relayer instance, where this relayer is responsible for forwarding messages from the rollup and listening for events to relay back.  

In the future there will be an effort to decentralize relayers and ensure they are trustless though the interface of the Mailbox will likely stay the same.

Messages processed by the Mailbox contract contain security parameters, including a unique, random nonce. This nonce is used to verify the uniqueness of each message, acting as a security measure against replay attacks. The contract also facilitates routing messages through a router to the intended destination contracts for processing.  This allows a smart-contract on Ethereum to talk to a smart-contract on the Eclipse rollup and vice versa. 

The Mailbox contract is intended to eventually be UUPS upgradeable until it is frozen. This feature has not been completed nor tested.

Moreoever, our current design moves data from Ethereum to the rollup directly using this relayer, but we will likely need to move this data to a sequencer for deposits.  

## Key Points

- Messages have a security parameter that contains a random nonce to prevent replay attacks.
- A router interface routes messages to appropriate destination contracts, enhancing message handling and delivery.
- The contract assumes a single trusted relayer for sending and receiving messages, simplifying the security model but potentially centralizing trust.
- The Mailbox contract is intended to be UUPS upgradeable, offering flexibility for future updates and improvements.
- The Mailbox contract sends and receives fields of bytes of information that are abi encoded data 
- The 'chain_id' on Ethereum is simply an abi encoded unsigned integer.  For the rollup it will correspond to an abi encoded string representing the 'cluster' which is the equivalent of a chain-id in the Solana ecosystem.
- The 'to/from' address will be an abi encoded string such as 'EtherBridge' to identify which contract a message is being sent to or retrieved from.  This makes it easier to work with than using addresses which would be different for each chain.

## Mailbox Methods

### MailboxMailOutgoingMessage Method

The mailOutgoingMessage method allows the router to send outgoing messages. It ensures that:

- The 'to_' field must be 32 bytes long; otherwise, it reverts with an error message.
- Messages must not be empty; otherwise, it reverts with an error message.
- On successful validation, it increments and records a unique nonce for the message, then calls sendMessage with the necessary parameters.

### MailboxReceiveMessage Method

The receiveMessage method allows a single trusted relayer to submit incoming messages. It verifies:

- The chainId must be 32 bytes long and match the Eclipse chain id; otherwise, it reverts with an error message.
- The nonce must be unique; otherwise, it reverts with an error message.
- The sequencer's signature must validate; otherwise, it reverts with an error message.
- On successful validation, it records the message nonce and routes the message to the intended destination.

### MailboxSendMessage Method

The sendMessage method, called indirectly via the router, ensures:

- Only the router can call this method; otherwise, it reverts.
- The chainId must be 32 bytes long and match the Ethereum chain id; otherwise, it reverts.
- On successful validation, it emits a {MessageSent} event.

This specification reflects the current implementation and design intentions of the Mailbox contract, highlighting its role in secure, efficient inter-chain communication and its adaptability through upgradeability features.

