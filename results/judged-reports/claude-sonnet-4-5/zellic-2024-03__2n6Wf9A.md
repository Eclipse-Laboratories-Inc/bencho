# Security Audit Report

## Critical: Treasury Receives Incorrect Amount in Deposit Function

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-131)

**Root Cause:**  
On line 127, the contract transfers `message.amount` (which is in lamports/gwei, line 113) to the treasury instead of the original `amount` parameter (which is in wei). This causes the treasury to receive only 1/1,000,000,000 of the intended deposit amount.

```solidity
uint256 lamportAmount = amount / WEI_PER_GWEI; // Line 113 - converts to gwei
// ...
(bool success,) = payable(address(treasury)).call{value: message.amount}(""); // Line 127 - sends gwei instead of wei
```

**Impact:**  
This is a critical loss of funds bug. Users deposit wei but the treasury only locks the equivalent in lamports/gwei, meaning 99.9999999% of user deposits are not secured in the treasury and remain in the EtherBridge contract where they can be stolen or lost.

**Recommendation:**  
Change line 127 to transfer the original wei amount: `{value: amount}` instead of `{value: message.amount}`.

## Critical: Missing Nonce Replay Protection in Solana Withdraw

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 31-75)

**Root Cause:**  
The withdrawal function creates a new `WithdrawalReceipt` account using the `withdrawal_nonce` as a seed (lines 18-19), but the Anchor `init` constraint will fail if the account already exists. However, if a user provides a different nonce each time, they can withdraw multiple times with the same destination address, effectively draining funds from the relayer.

**Impact:**  
A malicious user can repeatedly call the withdraw function with different nonces to extract unlimited funds from the relayer account on Solana, as there's no check preventing multiple withdrawals to the same Ethereum address.

**Recommendation:**  
Implement a mapping or account structure that tracks which Ethereum destination addresses have already withdrawn, or require nonces to be derived from a counter that increments sequentially per user.

## Critical: Cross-Chain Signature Replay Attack

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 118-151)

**Root Cause:**  
The signature verification on lines 138-139 creates a hash using `keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce))` but does not include the Ethereum chain ID or the contract address. This means a signature valid on one Ethereum chain (e.g., mainnet) can be replayed on another chain (e.g., a testnet or L2) if the same mailbox is deployed.

**Impact:**  
An attacker can replay messages across different Ethereum-compatible chains, potentially causing unauthorized fund transfers or state changes on multiple chains from a single signed message.

**Recommendation:**  
Include both the Ethereum chain ID and the contract address in the hash: `keccak256(abi.encodePacked(ethereumChainId, address(this), eclipseChainId_, sender_, message_, secParam.nonce))`.

## High: Unbounded Gas Consumption in Router

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()` (lines 47-63)

**Root Cause:**  
Line 61 performs a low-level call without any gas limit: `(bool success,) = actualAddress.call(message)`. This forwards all available gas to the target contract, which could be a malicious contract designed to consume excessive gas or attempt reentrancy attacks.

**Impact:**  
A malicious module contract could consume all available gas, causing transaction failures and potential denial-of-service. Additionally, without proper gas accounting, the relayer may pay unexpectedly high gas costs.

**Recommendation:**  
Add a reasonable gas limit to the call: `actualAddress.call{gas: MAX_ROUTING_GAS}(message)` where `MAX_ROUTING_GAS` is a defined constant.

## High: Predictable Nonce Generation Using Deprecated Field

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 201-206)

**Root Cause:**  
Line 204 uses `block.difficulty` which was replaced by `block.prevrandao` after Ethereum's merge to proof-of-stake. On post-merge chains, `block.difficulty` returns `prevrandao`, but on some L2s or older testnets it may return a predictable or zero value. Additionally, all inputs to the hash (`block.timestamp`, `block.difficulty`, `msg.sender`, `nonceCounter`) are either predictable or known to miners/validators.

**Impact:**  
Nonces can be predicted or manipulated by validators/miners, potentially allowing them to front-run messages or cause nonce collisions if the random value space is constrained.

**Recommendation:**  
Use a commit-reveal scheme or a verifiable random function (VRF) like Chainlink VRF for truly random nonces. As a simpler fix, use a sequential counter instead of attempting randomness.

## High: Treasury Can Be Initialized by Attacker

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `initialize()` (lines 81-96)

**Root Cause:**  
Line 95 calls `treasury.initialize()` from within the EtherBridge's initialize function. If an attacker can front-run the EtherBridge deployment and initialization, they could call `treasury.initialize()` directly first, becoming the treasury owner before the EtherBridge can initialize it.

**Impact:**  
An attacker gaining ownership of the Treasury would have complete control over all deposited funds, allowing them to drain the entire treasury at will.

**Recommendation:**  
Deploy the Treasury with the EtherBridge address as a constructor parameter and have the Treasury set the owner during construction, not via an initializer. Alternatively, check if the treasury is already initialized before calling initialize().

## High: Transfer Method Can Silently Fail

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw()` (lines 23-26)

**Root Cause:**  
Line 25 uses `to.transfer(amount)` which only forwards 2,300 gas. If the recipient is a contract with a complex `receive()` or `fallback()` function that requires more than 2,300 gas, the transfer will revert. While this isn't silent failure per se (it will revert), it creates a denial-of-service where legitimate withdrawals cannot be processed.

**Impact:**  
Users who are smart contracts may be permanently unable to withdraw their funds if their receive function costs more than 2,300 gas, leading to frozen funds.

**Recommendation:**  
Replace `transfer()` with a low-level call: `(bool success, ) = to.call{value: amount}(""); require(success, "Transfer failed");`

## Medium: Incomplete State Cleanup on Contract Unregistration

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract()` (lines 39-48)

**Root Cause:**  
When unregistering a contract, lines 44-45 delete `identifierAddress[identifier]` and `addressIdentifier[contractAddress]`, but line 46 does not delete `addressContractType[contractAddress]`. This leaves stale type information for the unregistered address.

**Impact:**  
If the same address is later registered again with a different contract type, queries to `getContractType()` might return incorrect cached values before the new registration, potentially causing authorization bypasses.

**Recommendation:**  
Add `delete addressContractType[contractAddress];` in the unregisterContract function after line 45.

## Medium: Insufficient Gas Limit for Routing Operations

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 124)

**Root Cause:**  
The routing call on line 124 explicitly limits gas to `MIN_DEPOSIT_GAS_ONLY_ROUTING` (300,000 gas). While this prevents gas exhaustion, it may be insufficient for complex routing logic or if the router needs to make multiple external calls, especially if the called module contract has expensive operations.

**Impact:**  
Deposits could fail if the routing process requires more than 300,000 gas, leading to failed user transactions and a poor user experience. Users lose gas fees without completing their deposit.

**Recommendation:**  
Either increase the gas limit or make it configurable. Consider measuring actual gas consumption in tests to set an appropriate limit with safety margin.

## Medium: No Validation of Decoded String Identifier

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()` (line 54)

**Root Cause:**  
Line 54 decodes bytes into a string using `abi.decode(encodedIdentifier, (string))` without validating that the bytes represent a valid UTF-8 string or checking for malicious characters. If the encoded identifier contains invalid data, this could cause unexpected behavior.

**Impact:**  
While the subsequent registry lookup would likely fail with invalid identifiers, malformed string data could potentially cause issues with logging, event emission, or other string operations. This could be exploited to inject misleading data into events or logs.

**Recommendation:**  
Add validation that the decoded string is non-empty, within reasonable length limits, and contains only expected characters (alphanumeric and specific allowed special characters).

## Medium: Missing Amount Validation in Solana Deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 29-57)

**Root Cause:**  
The deposit function accepts an `amount` parameter but does not validate that it's greater than zero or within reasonable bounds. This allows creation of deposit receipts with zero or dust amounts.

**Impact:**  
Attackers could spam the network with zero-value or dust deposits, creating unnecessary on-chain state and potentially causing issues with relayer accounting or making it harder to track legitimate deposits.

**Recommendation:**  
Add validation: `require!(amount >= MIN_DEPOSIT_AMOUNT, ErrorCode::AmountTooSmall);` and `require!(amount <= MAX_DEPOSIT_AMOUNT, ErrorCode::AmountTooLarge);` where minimum and maximum amounts are defined constants.

## Medium: Missing Amount Validation in Solana Withdraw

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 31-75)

**Root Cause:**  
Similar to the deposit function, the withdraw function does not validate the `amount` parameter to ensure it's greater than zero or within reasonable limits.

**Impact:**  
Users could create withdrawal receipts with zero or unreasonably large amounts, potentially causing issues on the Ethereum side when the relayer processes these withdrawals. Large withdrawal amounts might exceed Ethereum-side limits, causing failed transactions.

**Recommendation:**  
Add amount validation against minimum and maximum thresholds. Additionally, verify that the withdrawer has sufficient balance before allowing the withdrawal.

## Low: Fee Calculation Logic May Be Unclear

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` modifier `sufficientFee()` (lines 38-41)

**Root Cause:**  
Line 39 requires `fee >= MIN_DEPOSIT_GAS * FEE_MARGIN` where `FEE_MARGIN = 20`. The naming suggests this should be a percentage-based margin (e.g., 20% = 1.2x), but it's actually being used as a multiplier. This makes the fee 20x the minimum gas, which seems excessive and inconsistent with the `estimateFee()` function on line 168 which uses the same calculation.

**Impact:**  
While this is implemented consistently, the variable name is misleading. If `FEE_MARGIN` was intended to represent a percentage, deposits would require far less fee than currently enforced. This could be a documentation/naming issue rather than a functional bug, but it creates confusion.

**Recommendation:**  
Rename `FEE_MARGIN` to `FEE_MULTIPLIER` for clarity, or restructure the calculation to use percentage-based logic: `fee >= (MIN_DEPOSIT_GAS * tx.gasprice * (100 + FEE_MARGIN)) / 100`.

## Low: Potential Front-Running of Deposit Receipts

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 29-57)

**Root Cause:**  
The deposit receipt PDA is derived solely from `eth_deposit_nonce` (line 16). If a malicious actor observes a pending deposit transaction, they could attempt to front-run it by submitting their own transaction with the same nonce but different parameters.

**Impact:**  
The original transaction would fail due to the account already existing, causing a denial-of-service where legitimate deposits from the relayer can be blocked. However, since only the relayer can call this function (line 10), this is limited to scenarios where the relayer's private key is compromised or the relayer is malicious.

**Recommendation:**  
Include additional seeds in the PDA derivation such as the recipient address: `seeds = [b"deposit", eth_deposit_nonce.to_le_bytes().as_ref(), to.key().as_ref()]`. This ensures each deposit is unique to the intended recipient.

## Low: No Validation of Destination Address Format

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 31)

**Root Cause:**  
The `destination_address` parameter is accepted as a raw `String` without validation that it's a valid Ethereum address format. Invalid addresses would be logged and sent to the Ethereum side, where they would cause transaction failures.

**Impact:**  
Users could accidentally or intentionally provide malformed destination addresses, leading to failed withdrawals on Ethereum and potential loss of funds if the relayer processes the withdrawal on Solana but cannot complete it on Ethereum.

**Recommendation:**  
Add validation to check that `destination_address` is 42 characters long (including "0x" prefix) and contains only valid hexadecimal characters. Alternatively, store the address as bytes and validate the format.

## Informational: Using Deprecated Solidity Pragma

**File:** Multiple files  
**Location:** All Solidity contracts

**Root Cause:**  
All contracts use `pragma solidity 0.8.21;` which is now several versions behind the latest 0.8.x releases. Newer compiler versions include additional bug fixes and optimizations.

**Impact:**  
While 0.8.21 is still secure for most purposes, newer versions may include important security fixes and gas optimizations that could benefit the contracts.

**Recommendation:**  
Consider upgrading to the latest stable 0.8.x compiler version (0.8.26 or later) and test thoroughly to ensure compatibility.

## Informational: Inefficient Storage in WithdrawalReceipt

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function:** `WithdrawalReceipt::size()` (lines 38-40)

**Root Cause:**  
The size is hardcoded to 1024 bytes with a TODO comment indicating it should be optimized. Given that the struct contains a u64, String, u64, and u8, 1024 bytes is likely excessive.

**Impact:**  
Users pay more rent than necessary for withdrawal receipt accounts, increasing the cost of withdrawals. This doesn't affect security but does impact user experience and economic efficiency.

**Recommendation:**  
Calculate the actual required size based on the struct fields, using a maximum reasonable length for the destination_address string (e.g., 42 bytes for Ethereum address + overhead).

## Informational: Missing Events for Critical State Changes

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract()` (lines 39-48)

**Root Cause:**  
While the function emits a `ContractUnregistered` event, there's no event emitted when updating contract types or when contracts are modified in other ways during the registration process.

**Impact:**  
Lack of comprehensive events makes it harder to track and audit all state changes in the registry, potentially obscuring important administrative actions from off-chain monitoring systems.

**Recommendation:**  
Consider emitting events for all state-changing operations, or ensure existing events capture all relevant state transitions.

## Informational: No Upper Bound Check on Chain ID Length

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Modifier:** `chainIdMaxLength` (lines 45-48)

**Root Cause:**  
The modifier checks that chain IDs are `<= 32` bytes, but there's no lower bound check. A zero-length chain ID would pass this validation but would likely cause issues in comparisons.

**Impact:**  
While the initialize function requires non-zero chain IDs during setup, malformed messages with empty chain IDs could potentially pass initial validation and only fail later, wasting gas.

**Recommendation:**  
Add a minimum length check: `require(_data.length > 0 && _data.length <= 32, "Chain ID must be between 1 and 32 bytes");`
