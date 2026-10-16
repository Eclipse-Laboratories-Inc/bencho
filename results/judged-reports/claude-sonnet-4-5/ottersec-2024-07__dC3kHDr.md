# Security Audit Report

## Critical: Weak Nonce Generation in Mailbox Enables Predictability

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 244-250)

**Root Cause:**  
The `generateRandomNonce()` function generates nonces using block properties (`blockhash`, `block.timestamp`, `block.coinbase`) which are manipulable by validators/miners. Critically, `blockhash(block.number - 1)` returns `bytes32(0)` for blocks older than 256 blocks in the past, making nonce generation entirely predictable in that scenario.

**Impact:**  
Attackers can predict future nonces, potentially enabling:
- Message replay attacks by precomputing nonces
- Transaction front-running to manipulate message ordering
- Denial of service by forcing nonce collisions

**Recommendation:**  
Use Chainlink VRF or a commit-reveal scheme for truly random nonce generation. As a minimum, increment a counter deterministically rather than relying on block properties.

---

## Critical: Incorrect Bump Storage in Solana Deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (line 46)

**Root Cause:**  
The function accepts a `bump` parameter and stores it in the deposit receipt at line 46: `deposit_receipt.bump = bump`. However, Anchor's `#[account(init)]` macro with `bump` at lines 12-17 automatically derives and validates the correct bump. The passed-in parameter can differ from the derived bump, storing an incorrect value.

**Impact:**  
Storing an incorrect bump compromises PDA re-derivation. Future operations attempting to re-derive the PDA using the stored bump will fail or derive an incorrect address, potentially:
- Locking funds permanently 
- Enabling PDA collision attacks
- Breaking off-chain indexing and relayer logic

**Recommendation:**  
Use `ctx.bumps.deposit_receipt` instead of the passed-in parameter: `deposit_receipt.bump = ctx.bumps.deposit_receipt`. Remove `bump` from function parameters.

---

## Critical: Incorrect Bump Storage in Solana Withdrawal

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 55)

**Root Cause:**  
Identical to the deposit function, the withdrawal function accepts a `bump` parameter and stores it at line 55: `withdrawal_receipt.bump = bump`. Anchor derives the correct bump automatically via the `#[account(init)]` constraint (lines 18-27), but the user-provided value overwrites it.

**Impact:**  
Same as deposit - incorrect PDA re-derivation leading to:
- Withdrawal receipt inaccessibility
- Relayer confusion when processing withdrawals
- Potential fund loss if the receipt cannot be located

**Recommendation:**  
Use `ctx.bumps.withdrawal_receipt` instead: `withdrawal_receipt.bump = ctx.bumps.withdrawal_receipt`. Remove `bump` from function parameters.

---

## Critical: Unbounded Gas in Module Call Enables DoS

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 205)

**Root Cause:**  
The low-level call to the module at line 205 does not specify a gas limit: `(bool success,) = module.call(message_)`. This forwards all available gas to the module, allowing a malicious or buggy module to consume all gas and cause the transaction to fail.

**Impact:**  
- Malicious modules can grief the relayer by consuming all gas
- Bugs in modules can brick the mailbox
- High gas consumption can make message delivery economically infeasible

**Recommendation:**  
Specify a reasonable gas limit for the call: `module.call{gas: 100000}(message_)`. The limit should be sufficient for legitimate modules but prevent abuse.

---

## High: Missing Initialization Check in Solana Deposit

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (line 35)

**Root Cause:**  
The deposit function accesses `ctx.accounts.config` at line 35 but doesn't verify that `init_config()` has been called. If the configuration account hasn't been initialized, the account will be in an undefined state or the transaction will fail.

**Impact:**  
- Deposits may fail unexpectedly before initialization
- Undefined behavior if account data is zeroed
- Poor user experience with unclear error messages

**Recommendation:**  
Add an initialization check or document that `init_config()` must be called before any deposits. Alternatively, use Anchor's constraint system to enforce initialization order.

---

## High: Missing Initialization Check in Solana Withdrawal

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 46)

**Root Cause:**  
The withdrawal function accesses `ctx.accounts.config` at line 46 without verifying initialization, identical to the deposit issue.

**Impact:**  
- Withdrawals may fail before initialization
- Unpredictable behavior if configuration is uninitialized

**Recommendation:**  
Ensure `init_config()` is called first, or add explicit initialization checks in the withdrawal function.

---

## High: No Minimum Deposit Enforcement on Solana

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (line 31)

**Root Cause:**  
The Ethereum `EtherBridge` enforces `MIN_DEPOSIT` (341,280 wei) to ensure rent-exemption on Solana, but the Solana `deposit()` function accepts any `amount` without validation. This inconsistency allows deposits below the rent-exempt threshold if called directly.

**Impact:**  
- Accounts created below rent-exemption threshold will be subject to rent collection
- Users may lose funds to rent
- Dust accounts clutter the blockchain

**Recommendation:**  
Add minimum deposit validation on Solana side: `require!(amount >= MIN_DEPOSIT_LAMPORTS, ErrorCode::DepositTooSmall)` where `MIN_DEPOSIT_LAMPORTS` matches the Ethereum calculation.

---

## High: Invalid Ethereum Address Not Validated in Withdrawal

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (line 38)

**Root Cause:**  
The `destination_address` parameter is accepted as a `String` without validation. There's no check that it's a valid Ethereum address (0x-prefixed, 40 hex characters, valid checksum).

**Impact:**  
- Users can specify invalid addresses, resulting in undeliverable withdrawals
- Funds transferred to the relayer cannot be recovered
- Withdrawal messages with malformed addresses may fail on Ethereum side

**Recommendation:**  
Validate the address format: check length, hex encoding, and optional EIP-55 checksum. Consider using a fixed-size byte array instead of String.

---

## High: No Withdrawal Processing in EtherBridge

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** N/A (missing withdrawal handler)

**Root Cause:**  
The `EtherBridge` contract implements `deposit()` to lock funds in the Treasury, but provides no function to process withdrawals from Eclipse back to Ethereum. There's no implementation to receive messages from the Mailbox and release funds from the Treasury.

**Impact:**  
- Funds can be locked in the bridge with no native withdrawal path
- Users must rely entirely on manual emergency withdrawals by the admin
- Bridge is functionally one-directional

**Recommendation:**  
Implement a withdrawal handler that the Mailbox can call to release funds from the Treasury to user addresses. This should validate withdrawal signatures/proofs and transfer from Treasury to recipients.

---

## Medium: Module Address Cannot Be Updated

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `addModule()` (lines 148-150)

**Root Cause:**  
The `addModule()` function reverts if `modulesById[moduleId]` is already set (line 148-150). There's no way to update a module address without first calling `removeModule()`.

**Impact:**  
- Module upgrades require two transactions (remove then add)
- Race conditions if messages arrive between removal and re-addition  
- No atomic module updates

**Recommendation:**  
Add an `updateModule()` function or allow `addModule()` to overwrite if the caller is admin and include an event for the change.

---

## Medium: Oversized Account Allocation for WithdrawalReceipt

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function:** `WithdrawalReceipt::size()` (lines 38-40)

**Root Cause:**  
The `size()` function returns 1024 bytes, but the actual data (u64 + String + u64 + u8) requires significantly less. Even with a maximum-length String, this is excessive.

**Impact:**  
- Users pay ~10x more rent than necessary
- Wasted blockchain state storage
- Higher transaction costs

**Recommendation:**  
Calculate the accurate size: `8 + (4 + destination_address.len()) + 8 + 1 + 8 (discriminator)`. For dynamic strings, use a reasonable maximum (e.g., 42 for Ethereum address).

---

## Medium: Oversized Account Allocation for Configuration

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function:** `Configuration::size()` (lines 69-71)

**Root Cause:**  
Returns 1024 bytes for a struct containing only 3 bytes (u8 + bool + bool).

**Impact:**  
- Configuration account requires excessive rent
- Inefficient state usage

**Recommendation:**  
Return accurate size: `8 (discriminator) + 1 + 1 + 1 = 11 bytes`.

---

## Medium: Mailbox Nonce Storage Grows Unbounded

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Storage:** `StorageV1` (lines 56-57)

**Root Cause:**  
The `receiveNonces` and `sendNonces` mappings store every used nonce permanently. Over time, this grows without bound as more messages are sent/received.

**Impact:**  
- Increasing storage costs for the contract owner
- Potential gas increases for state access as the mapping grows
- No mechanism to prune old nonces

**Recommendation:**  
Implement a sliding window or time-based nonce expiration. After a reasonable period (e.g., 30 days), nonces could be pruned using a separate admin function.

---

## Medium: Mailbox Accepts Payment But Doesn't Forward It

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 184)

**Root Cause:**  
The function is marked `payable` but doesn't forward `msg.value` to the module or refund it. ETH sent with the call gets stuck in the Mailbox contract.

**Impact:**  
- User funds can be permanently locked in Mailbox
- No mechanism to recover accidentally sent ETH

**Recommendation:**  
Either remove `payable` modifier or forward `msg.value` to the module call: `module.call{value: msg.value}(message_)`.

---

## Low: Missing Events for Pause State Changes

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Functions:** `pause()`, `unpause()` (lines 131-137)

**Root Cause:**  
The pause and unpause functions don't emit events, making it difficult for off-chain systems to track bridge state changes.

**Impact:**  
- Reduced observability of contract state
- Difficulty tracking when the bridge was paused/unpaused
- Poor UX for dApps integrating the bridge

**Recommendation:**  
Emit `Paused(address)` and `Unpaused(address)` events (these are standard in OpenZeppelin's Pausable).

---

## Low: Missing Events for Solana Pause Operations

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/pause.rs`  
**Functions:** `pause_deposits()`, `resume_deposits()`, `pause_withdrawals()`, `resume_withdrawals()`

**Root Cause:**  
None of the pause/resume functions emit events/logs, making state changes invisible to off-chain observers.

**Impact:**  
- Relayers and UIs cannot easily detect when deposits/withdrawals are paused
- Poor user experience

**Recommendation:**  
Add `msg!()` logging or emit anchor events for each state change.

---

## Low: Redundant Amount Parameter in EtherBridge Deposit

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 101)

**Root Cause:**  
The function requires `amountWei` parameter but validates it must equal `msg.value` (line 66). This makes the parameter redundant since the actual deposited amount is always `msg.value`.

**Impact:**  
- User confusion about which value to use
- Unnecessary parameter increases gas costs slightly
- Potential for user error when values mismatch

**Recommendation:**  
Remove the `amountWei` parameter and use `msg.value` directly throughout the function.

---

## Informational: Treasury AuthorizeUpgrade Has Unnecessary View Modifier

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `_authorizeUpgrade()` (line 69)

**Root Cause:**  
The function has `view` modifier, which is unusual for UUPS upgrade authorization. While this works because the function only checks ownership, it's inconsistent with other contracts.

**Impact:**  
- Inconsistency across codebase (EtherBridge and Mailbox don't use `view`)
- Potential confusion for auditors

**Recommendation:**  
Remove `view` modifier for consistency: `function _authorizeUpgrade(address) internal override onlyOwner {}`.

---

## Informational: DepositReceipt Size Calculation Comment Mismatch

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Function:** `DepositReceipt::size()` (lines 51-56)

**Root Cause:**  
The size calculation is well-documented but the comment says it matches `DEPOSIT_RECEIPT_DATA_LEN = 8 + 32 + 8 + 1 = 49` from the Solidity side. However, the actual implementation returns a different value that includes the Anchor discriminator.

**Impact:**  
- Potential confusion when comparing Ethereum and Solana constants
- Rent calculation may differ from expected

**Recommendation:**  
Update comments to clarify that Solana accounts include an 8-byte discriminator, making total size 57 bytes (8 + 49), not 49.
