# Security Audit Report

## Critical: Incorrect Amount Deposited to Treasury

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

**Description:**  
On line 127, the contract transfers `message.amount` to the treasury, but this value has been converted to lamports (divided by `WEI_PER_GWEI` on line 113). This means only 1/1,000,000,000 of the user's actual deposit reaches the treasury, while the remaining funds accumulate in the EtherBridge contract as unrecoverable fees.

```solidity
uint256 lamportAmount = amount / WEI_PER_GWEI;  // Line 113
// ...
(bool success,) = payable(address(treasury)).call{value: message.amount}("");  // Line 127 - WRONG!
```

The user sends `amount` wei but only `lamportAmount` (in wei equivalent) is transferred to treasury.

**Impact:** Users lose ~99.9999999% of their deposited funds. This is a critical fund loss vulnerability.

**Recommendation:** Transfer the original `amount` parameter, not the converted `message.amount`:
```solidity
(bool success,) = payable(address(treasury)).call{value: amount}("");
```

## Critical: Predictable Nonce Generation Enables Replay Attacks

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()`

**Description:**  
The `generateRandomNonce()` function on line 201-206 uses `block.difficulty` which is always 0 post-merge, making nonces predictable. Additionally, the function is public and non-view, allowing anyone to manipulate the nonce counter.

```solidity
uint256 largeNonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nonceCounter)));
```

**Impact:** Attackers can predict future nonces and pre-compute signatures, or call this function repeatedly to force specific nonce values, enabling message replay attacks.

**Recommendation:** Use `block.prevrandao` instead of `block.difficulty`, make the function internal, and consider using a commit-reveal scheme or VRF for true randomness.

## High: Arbitrary External Call in Router

**File:** `smart-contracts/src/v1/Router.sol`  
**Function:** `routeIncomingMessage()`

**Description:**  
On line 61, the router makes an arbitrary call to any address registered as a MODULE with user-controlled calldata:

```solidity
(bool success,) = actualAddress.call(message);
require(success, "External call failed");
```

**Impact:** If a malicious contract is registered as a MODULE (or if the registry is compromised), an attacker can execute arbitrary code with the router's context. This could drain funds, manipulate state, or cause other critical damage.

**Recommendation:** Implement an interface that MODULE contracts must conform to, and use typed function calls instead of raw `.call()`. Add additional access controls and validation for module registration.

## High: Missing Signature Replay Protection Across Chains

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()`

**Description:**  
The signature verification on line 138 does not include the contract address or Ethereum chainId in the signed message:

```solidity
bytes32 hash = keccak256(abi.encodePacked(eclipseChainId_, sender_, message_, secParam.nonce));
```

**Impact:** A valid signature for one deployment can be replayed on another deployment of the same contract system (e.g., testnet vs mainnet, or different rollup instances), allowing unauthorized message execution.

**Recommendation:** Include the contract address and Ethereum chain ID in the hash. Use EIP-712 structured data hashing for better security:
```solidity
bytes32 hash = keccak256(abi.encodePacked(address(this), ethereumChainId, eclipseChainId_, sender_, message_, secParam.nonce));
```

## High: Treasury Transfer Can Permanently Lock Funds

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdraw()`

**Description:**  
Line 25 uses `.transfer()` which provides only 2300 gas and will fail if the recipient is a contract with non-trivial receive/fallback logic:

```solidity
to.transfer(amount);
```

**Impact:** Withdrawals to smart contract wallets (multisigs, account abstraction wallets) will permanently fail, locking funds in the treasury with no recovery mechanism.

**Recommendation:** Use `.call{value: amount}("")` with proper error handling:
```solidity
(bool success, ) = to.call{value: amount}("");
require(success, "Transfer failed");
```

## High: Hardcoded Relayer Creates Single Point of Failure

**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`  
**Location:** Line 11

**Description:**  
The relayer public key is hardcoded as a constant:

```rust
pub const RELAYER_PUBKEY: Pubkey = pubkey!("ec1vCnQKsQSnTbcTyc3SH2azcDXZquiFB3QqtRvm3Px");
```

**Impact:** If the relayer's private key is compromised, stolen, or lost, the entire bridge system becomes unusable or vulnerable. There is no way to rotate the relayer key without upgrading the program.

**Recommendation:** Store the relayer pubkey in a configurable account that can be updated by an admin through a secure multi-sig process.

## High: No Withdrawal Nonce Replay Protection

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()`

**Description:**  
The withdrawal nonce is user-provided (line 31) and only used as a PDA seed. There's no verification that this nonce hasn't been used before or that it corresponds to a valid Ethereum deposit.

**Impact:** If the PDA derivation allows collisions or if nonces are reused across different withdrawal attempts, users might be able to withdraw multiple times for a single deposit, draining the bridge.

**Recommendation:** Maintain a global nonce counter or verify nonces against a mapping of used nonces to prevent replay attacks.

## High: Unprotected Treasury Initialization

**File:** `smart-contracts/src/v1/Treasury.sol` and `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `initialize()`

**Description:**  
In EtherBridge.sol line 95, the code calls `treasury.initialize()` on an already-deployed treasury contract. If the Treasury was deployed but not initialized, anyone could initialize it first and become the owner.

**Impact:** An attacker could front-run the EtherBridge initialization to become the Treasury owner, allowing them to drain all deposited funds.

**Recommendation:** Deploy and initialize Treasury atomically within the EtherBridge initializer, or ensure Treasury initialization is access-controlled and called immediately after deployment.

## Medium: Excessive Fee Calculation Overcharges Users

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

**Description:**  
The fee validation on line 39 requires:
```solidity
require(fee >= MIN_DEPOSIT_GAS * FEE_MARGIN, "Deposit fee amount is not enough to execute call");
```
Where `MIN_DEPOSIT_GAS = 400,000` and `FEE_MARGIN = 20`, requiring fees for 8,000,000 gas - far exceeding actual usage.

**Impact:** Users are significantly overcharged for deposits. These excess fees accumulate in the EtherBridge contract with no mechanism to withdraw or refund them.

**Recommendation:** Calibrate `FEE_MARGIN` to realistic gas costs (typically 1-2x actual usage), and implement a fee withdrawal mechanism for the contract owner.

## Medium: Hardcoded Gas Limit Can Cause Fund Loss

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

**Description:**  
On line 124, the routing call has a hardcoded gas limit:
```solidity
router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}(encodedMessage);
```

**Impact:** If the router or downstream contracts require more than 300,000 gas, the call will fail but the user's funds are already locked in the treasury with no rollback mechanism.

**Recommendation:** Remove the gas restriction or make it configurable. Implement proper error handling that reverts the entire transaction if routing fails.

## Medium: Missing Registry Contract Type Cleanup

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `unregisterContract()`

**Description:**  
Line 39-47 deletes mappings but doesn't clear the `addressContractType` mapping:

```solidity
delete identifierAddress[identifier];
delete addressIdentifier[contractAddress];
// Missing: delete addressContractType[contractAddress];
```

**Impact:** The `getContractType()` function will still return the old type for unregistered contracts, potentially causing authorization bypasses if the address is reused.

**Recommendation:** Add `delete addressContractType[contractAddress];` to the unregisterContract function.

## Medium: No Validation of Ethereum Address Format

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()`

**Description:**  
The `destination_address` parameter (line 31) accepts any string without validating it's a proper Ethereum address format (0x-prefixed, 40 hex characters).

**Impact:** Users may lose funds by providing malformed addresses. The withdrawal message will be emitted but cannot be processed on Ethereum, permanently locking funds.

**Recommendation:** Validate the destination_address format:
```rust
require!(destination_address.starts_with("0x") && destination_address.len() == 42, ErrorCode::InvalidAddress);
```

## Medium: No Access Control on Deposit Function

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()`

**Description:**  
While the function requires the relayer to sign (line 11), there's no verification that the deposit corresponds to an actual Ethereum transaction. The relayer could arbitrarily mint deposits.

**Impact:** A compromised or malicious relayer could create fake deposits, inflating the supply on Eclipse without corresponding Ethereum deposits.

**Recommendation:** Implement cryptographic verification of Ethereum state (e.g., Merkle proof verification) to prove the deposit actually occurred on Ethereum.

## Low: Use of Deprecated block.difficulty

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()`

**Description:**  
Line 204 uses `block.difficulty` which has been deprecated since The Merge and is always 0:
```solidity
uint256 largeNonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nonceCounter)));
```

**Impact:** Reduced entropy in nonce generation, making nonces more predictable.

**Recommendation:** Replace `block.difficulty` with `block.prevrandao`.

## Low: Missing Event Emission for Critical Operations

**File:** `smart-contracts/src/v1/Registry.sol`  
**Function:** `registerContract()`

**Description:**  
Contract registration emits an event (line 34), but the contract type is not included in the event parameters, making off-chain tracking difficult.

**Impact:** Monitoring systems cannot easily determine what type of contract was registered without making additional calls.

**Recommendation:** Include `contractType` in the `ContractRegistered` event.

## Low: Unbounded String Storage in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Struct:** `WithdrawalReceipt`

**Description:**  
Line 7 stores `destination_address` as an unbounded String. The size calculation on line 38-40 allocates a fixed 1024 bytes regardless of actual string length.

**Impact:** Memory inefficiency and potential for exploitation if extremely long strings are provided, wasting rent-exempt lamports.

**Recommendation:** Enforce a maximum string length and calculate size accurately, or use a fixed-size array for Ethereum addresses (42 bytes).

## Informational: Typo in Error Message

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Line:** 32

**Description:**  
Error message contains typo "deposite" instead of "deposit":
```solidity
require(amount <= MAX_DEPOSIT_AMOUNT, "Deposit amount must be less than equal to the max deposite amount");
```

**Recommendation:** Fix typo to "deposit".

## Informational: Inefficient RLP Encoding Logged Without Purpose

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `log_outbox_message()`

**Description:**  
Lines 77-80 encode and log the withdrawal message, but this data is not used on-chain and creates unnecessary computation cost.

**Impact:** Increased transaction costs for users.

**Recommendation:** Consider whether this logging is necessary, or move encoding off-chain if it's only needed for relayer indexing.

## Informational: Missing Input Validation for Amount Bounds

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()`

**Description:**  
No validation that the withdrawal amount is within reasonable bounds (not zero, not exceeding user's balance).

**Impact:** Users can attempt withdrawals with zero amount or amounts they don't have, wasting gas.

**Recommendation:** Add validation:
```rust
require!(amount > 0, ErrorCode::InvalidAmount);
require!(from_account.lamports() >= amount, ErrorCode::InsufficientBalance);
```
