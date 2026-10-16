# Ethereum Bridge Smart Contracts

This repository contains the Ethereum smart contracts designed for facilitating ether transactions between the Ethereum blockchain and the Eclipse rollup. 

These contracts provide interfaces for secure interactions through relayers and support upgrades and access control.

They will be extended in the future to contain support for forced inclusion and data commitments that support fraud proofs. 

## Features

- **Cross-Chain Ether Transfers:** Enable the transfer of ether between Ethereum and Eclipse, ensuring that all transactions are secure and verifiable.
- **Role-Based Access Control:** Utilizes roles to manage access to critical functions within the contracts, enhancing security and operational integrity.
- **Upgradeability:** Incorporates the UUPS (Universal Upgradeable Proxy Standard) pattern to allow future improvements and iterative development without disrupting existing functionalities.
- **Security and Validation:** Implements multiple layers of checks and validations to ensure the integrity and authenticity of every transaction.

## Organization

- `src` -- sources for the interfaces and implementation contracts 
- `test` --  unit and integration tests for src  
- `specs` -- specifications for smart-contracts
- `script` -- scripts for deployment, authority transfer and upgrades

## Components

### Treasury

The `Treasury` contract acts as a secure vault for ether deposits from the `EtherBridge`.

Withdraws are currently paused and the contract will be managed by a multi-sig authority different from the authority for the other contracts.

### EtherBridge

The `EtherBridge` contract handles the deposit and withdrawal of ether, interfacing directly with end users. 

It locks ether in the`Treasury` contract upon deposits and coordinates withdrawals based on validated requests from the Eclipse rollup through the `Mailbox`.

### Mailbox

The `Mailbox` contract serves as a communication layer between Ethereum and Eclipse, securing message delivery using a trusted relayer model. 

It adheres to a modified EIP-6170 interface, supporting cross-chain messaging with enhanced security features like nonce management to prevent replay attacks.

## Development

The smart contracts are developed, built, and tested using the [Foundry](https://github.com/foundry-rs/foundry) framework.

### Setup

Install dependencies for local development:

```bash
make install-forge-deps
````

### Build

```bash
make forge-build 
````

### Test

```bash
make forge-test 
````

### Deploy

```bash
export SENDER=<SENDER-PUBLIC-KEY>
forge script script/v1/Deployment.s.sol --sig "run(string,string,address)" "Ethereum" "Eclipse" <relayer-public-key> --rpc-url <rpc-url> --broadcast --private-key <private-key>
````
