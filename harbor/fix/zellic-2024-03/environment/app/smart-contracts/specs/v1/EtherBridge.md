# EtherBridge Contract Specification

The EtherBridge contract establishes a bridge for depositing and withdrawing ether to and from the Eclipse rollup. 

It is designed to securely lock ether in a treasury for cross-chain transfers to the Eclipse rollup.

## Overview

EtherBridge interfaces with a registry to dynamically resolve contract addresses and utilizes a router for inbound and outbound message routing from the rollup. 

## Key Features

- **ether Deposit and Withdrawal:** Facilitates the deposit and withdrawal of ether, bridging Ethereum with the Eclipse rollup.
- **Minimum and Maximum Transaction Limits:** Enforces minimum and maximum limits on the amounts that can be deposited or withdrawn to prevent abuse and ensure system stability.
- **Fee Management:** Incorporates fee calculations to cover transaction costs, ensuring that the bridge operates sustainably.
- **Security Measures:** Implements non-reentrancy guards and various checks to secure transactions against common attack vectors.

## Initialization

The contract must be initialized with the address of the Registry contract. This step is crucial for setting up the bridge's operational parameters, including linking to the Router and Treasury contracts.

function initialize(address registryAddress) external initializer

## Transactions

### Deposits

ether deposits are secured by locking the deposited ether in the Treasury contract. The deposit function requires a recipient address on the target chain, the amount to be deposited, and a fee to cover transaction costs.

function deposit(bytes32 recipient, uint256 amount, uint256 fee) external payable

### Withdrawals

Withdrawals allow for the transfer of ether from the Treasury back to a specified recipient. This process is initiated by the Router contract to ensure that only authorized withdrawals are processed.

function withdraw(WithdrawMessage calldata message) external

## Fee and Limit Management

The contract defines minimum and maximum amounts for deposits and withdrawals to maintain operational integrity and prevent system abuse. It also includes functions for estimating fees and retrieving current fee balances.

function estimateFee() public view returns (uint256 fee)

function minDepositAmount() public pure returns (uin

