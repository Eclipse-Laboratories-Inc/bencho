# Security Audit Report

## Critical: Weak Randomness in Nonce Generation Enables Prediction and Manipulation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 244-250)

**Root Cause:**  
The nonce generation relies on predictable blockchain properties: `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase`. These values can be predicted by observers and potentially manipulated by validators/miners. The function combines these with `lastNonce` but the result remains predictable since all inputs are public or influenceable.

**Impact:**  
An attacker who can predict or influence nonces could:
- Precompute future nonces to craft malicious messages in advance
- Validators could manipulate `block.coinbase` or select favorable timestamps
- Enable front-running attacks where attackers predict the next nonce
- Compromise the replay protection mechanism's integrity

**Recommendation:**  
Use Chainlink VRF or a commit-reveal scheme for cryptographically secure random nonce generation. Alternatively, allow the message sender to provide nonces with proper replay protection, or use a simple incrementing counter which is more predictable but at least monotonic and collision-free.

## Critical: Missing Contract Existence Check Before External Call to Module

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 205)

**Root Cause:**  
The code performs a low-level `call()` to the module address without verifying it contains contract code:
```solidity
address module = $.modulesById[bytes32(sender_)];
require(module != address(0), "Module does not exist.");
(bool success,) = module.call(message_);
```

While it checks for `address(0)`, it doesn't verify the address has code. A call to an EOA (externally owned account) will succeed and return `true`, but no actual processing occurs.

**Impact:**  
- If a module address is set to an EOA (accidentally or maliciously), messages will appear to succeed but are never processed
- Funds could be locked if the message was meant to trigger withdrawals
- Silent failures where the system believes messages were delivered but they weren't

**Recommendation:**  
Add a contract existence check using assembly or OpenZeppelin's `Address.isContract()`:
```solidity
require(module.code.length > 0, "Module address is not a contract");
```

## High: No Validation of Destination Address Format in Solana Withdrawal

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 36-89)

**Root Cause:**  
The `destination_address` parameter is accepted as an arbitrary `String` without validation that it's a valid Ethereum address. The string is directly stored in the withdrawal receipt and logged in the message without format checking.

**Impact:**  
- Users could lose funds by providing malformed Ethereum addresses
- Invalid addresses (wrong length, invalid characters, missing 0x prefix) would be logged in withdrawal messages
- The relayer receiving these messages would fail to process them, causing funds to be stuck
- No recovery mechanism exists for messages with invalid destination addresses

**Recommendation:**  
Add validation to ensure `destination_address`:
1. Starts with "0x" prefix
2. Has exactly 42 characters (0x + 40 hex chars)
3. Contains only valid hexadecimal characters
Alternatively, use a fixed-size byte array (20 bytes) instead of String.

## High: Deposit Nonce Collision Enables Denial of Service

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 31-62)

**Root Cause:**  
The deposit receipt PDA is derived from `eth_deposit_nonce` (line 15):
```rust
seeds = [b"deposit", eth_deposit_nonce.to_le_bytes().as_ref()],
```

If the same `eth_deposit_nonce` is used twice, the `init` constraint fails because the PDA already exists. However, there's no explicit validation preventing nonce reuse attempts. A malicious actor or even the relayer accidentally could DOS deposits by front-running with the same nonce.

**Impact:**  
- Legitimate deposits can be blocked if an attacker front-runs with the same nonce
- Relayer errors (network retries, bugs) could cause unintentional nonce reuse
- No clear error recovery path for users whose deposits are blocked
- Funds from failed deposits may need manual intervention to recover

**Recommendation:**  
Add explicit nonce tracking and validation before attempting PDA initialization. Alternatively, use a different seed derivation that includes the user's public key to prevent collision attacks.

## High: Missing Chain ID Validation in Outbound Messages

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage()` (lines 214-234)

**Root Cause:**  
The `sendMessage` function accepts a `chainId_` parameter but never validates it against the expected Eclipse chain ID. Unlike `receiveMessage` which validates incoming chain IDs (line 77), outbound messages can be sent to arbitrary chains:
```solidity
function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
```

The first parameter (destination chainId) is unnamed and completely ignored.

**Impact:**  
- Modules could accidentally send messages to wrong chains
- No protection against misconfiguration or bugs in module code
- Messages sent to wrong chains are irretrievable
- Funds associated with wrong-chain messages would be permanently lost

**Recommendation:**  
Add validation in `sendMessage`:
```solidity
require(decodeChainId(chainId_) == $.eclipseChainId, "Invalid destination chain");
```

## High: Treasury Ownership Transfer Bypasses Deposit Authorization

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `receive()` (lines 72-76)

**Root Cause:**  
The `receive()` function checks if the sender is either the Ether bridge or the current owner:
```solidity
require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
```

However, when ownership is transferred via `transferOwnership()`, the new owner immediately gains deposit privileges without any additional setup or validation.

**Impact:**  
- Unintended addresses could deposit funds during ownership transfer process
- The 2-step ownership transfer creates a window where the new owner (pending) cannot deposit but will be able to after accepting
- If ownership is transferred to a contract, that contract's behavior might not be compatible with direct ETH deposits
- Breaks the intended invariant that only the bridge should deposit operational funds

**Recommendation:**  
Remove the `owner()` check from the receive function and add a dedicated `ownerDeposit()` function with explicit access control, or validate that the owner is an EOA if direct deposits are intended.

## Medium: Unbounded String Allocation in Withdrawal Message

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` and state definition (lines 38, 52)

**Root Cause:**  
The `destination_address` is stored as a `String` type with no length restrictions. The `WithdrawalReceipt` allocates a fixed 1024 bytes (state.rs:39) but doesn't enforce that the string fits within reasonable bounds.

**Impact:**  
- Extremely long strings could cause transaction failures
- Wasted rent costs for users providing unnecessarily long addresses
- Potential for griefing by making withdrawal receipts expensive to create
- RLP encoding of oversized messages could fail or create malformed data

**Recommendation:**  
Enforce a maximum length on `destination_address` (e.g., 42 characters for Ethereum addresses):
```rust
require!(destination_address.len() <= 42, ErrorCode::AddressTooLong);
```

## Medium: Missing Zero Amount Validation in Deposit and Withdrawal

**File:** `smart-contracts/src/v1/EtherBridge.sol` (line 101) and `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs` (line 36)  
**Functions:** `deposit()` and `withdraw()`

**Root Cause:**  
Neither the Solidity `deposit` nor the Solana `withdraw` functions validate that the amount is greater than zero. While the Solidity contract has `MIN_DEPOSIT` validation, the Solana withdraw has no minimum.

**Impact:**  
- Zero-amount withdrawals waste gas and create useless withdrawal receipts
- Zero-amount transactions clutter state and emit meaningless events  
- On Solana, users could create withdrawal receipts that cost rent but transfer nothing
- Increases bloat in both on-chain state and relayer message queues

**Recommendation:**  
Add validation:
- Solidity: The `MIN_DEPOSIT` check already prevents this for deposits
- Solana: Add `require!(amount > 0, ErrorCode::ZeroAmount);` in the withdraw function

## Medium: No Balance Verification Before Sending Deposit Message

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-128)

**Root Cause:**  
The deposit function sends the message to the mailbox (line 120) before transferring funds to the treasury (line 124). While both operations revert on failure, there's a logical ordering issue: a message could be emitted if the mailbox call succeeds but the treasury transfer fails.

**Impact:**  
- If the treasury transfer fails, the mailbox message was already sent and events emitted
- The `nonReentrant` modifier prevents reentrancy, but doesn't address ordering
- In edge cases where the treasury's `receive()` is paused, deposits would fail AFTER messaging
- Creates inconsistency between on-chain events and actual fund transfers

**Recommendation:**  
Reorder operations to transfer funds to treasury BEFORE sending the mailbox message:
```solidity
// Lock funds in the treasury FIRST
(bool success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");
require(success, "Transfer failed");

// Then forward to mailbox
success = $.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "");
require(success, "Unable to forward deposit message to Mailbox");
```

## Medium: Module Address Can Be Maliciously Replaced

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Functions:** `removeModule()` and `addModule()` (lines 141-174)

**Root Cause:**  
The `removeModule` and `addModule` functions allow the admin to change which address is mapped to a module ID. While access-controlled, there's no timelock or multi-sig requirement. A compromised admin key could redirect messages to a malicious contract.

**Impact:**  
- Single point of failure: compromised admin key can redirect all messages
- No notification or delay before module addresses change
- Messages could be redirected to attacker-controlled contracts
- Funds or sensitive operations could be stolen if messages contain value

**Recommendation:**  
Implement a timelock for module changes, require multi-sig for critical operations, or emit events and add a delay period before module address changes take effect.

## Medium: Missing Nonce Expiration Mechanism

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Storage:** `receiveNonces` and `sendNonces` mappings (lines 56-57)

**Root Cause:**  
Nonces are stored permanently in mappings without any expiration or cleanup mechanism:
```solidity
mapping(uint64 => bool) receiveNonces;
mapping(uint64 => bool) sendNonces;
```

These mappings grow indefinitely as more messages are processed.

**Impact:**  
- Unbounded storage growth increases gas costs over time
- No way to clear old nonces that are no longer relevant
- Eventually could hit storage limits or make operations prohibitively expensive
- Storage slots are occupied forever even for ancient, irrelevant nonces

**Recommendation:**  
Implement a time-based or block-based expiration window for nonces, or use a different replay protection mechanism like a Merkle tree of recent nonces with periodic pruning.

## Low: Missing Access Control Events for Pause Operations

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/pause.rs`  
**Functions:** `pause_deposits()`, `resume_deposits()`, `pause_withdrawals()`, `resume_withdrawals()`

**Root Cause:**  
The pause and resume functions modify critical bridge state but don't emit events. Unlike the Solidity contracts which inherit `Pausable` (which emits events), the Solana program silently changes pause state.

**Impact:**  
- No on-chain record of when pause state changed
- Difficult to audit or monitor pause/resume operations
- Users and integrators can't easily detect when bridge functionality is disabled
- Relayers might not realize the bridge is paused and waste resources

**Recommendation:**  
Add event emissions for all pause and resume operations:
```rust
emit!(DepositsPaused { authority: ctx.accounts.authority.key() });
```

## Low: Inefficient Fixed Storage Allocation

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Functions:** `WithdrawalReceipt::size()` and `Configuration::size()` (lines 38-40, 68-71)

**Root Cause:**  
Both `WithdrawalReceipt` and `Configuration` allocate a fixed 1024 bytes:
```rust
pub fn size() -> usize {
    1024  // TODO: optimize here
}
```

However, the actual data structures are much smaller. `Configuration` only needs 3 bytes (1 bump + 2 bools).

**Impact:**  
- Users pay excessive rent for oversized accounts
- Wasted storage on-chain increases costs for everyone
- Poor user experience due to unnecessarily high transaction costs
- The TODO comment indicates this is a known issue left unresolved

**Recommendation:**  
Calculate proper sizes:
```rust
// Configuration: 8 (discriminator) + 1 (bump) + 1 (deposits_paused) + 1 (withdrawals_paused)
pub fn size() -> usize { 8 + 1 + 1 + 1 }

// WithdrawalReceipt: 8 (discriminator) + 8 (nonce) + 4 + string_len + 8 (amount) + 1 (bump)
// Use String::len() or enforce max length
```

## Low: No Rate Limiting on Bridge Operations

**File:** `smart-contracts/src/v1/EtherBridge.sol` and `eclipse-programs/programs/canonical_bridge/src/instructions/`  
**Functions:** `deposit()` and `withdraw()`

**Root Cause:**  
There are no rate limits, maximum transaction sizes, or daily volume caps on deposits or withdrawals. Any user can deposit/withdraw any amount (above minimum) at any frequency.

**Impact:**  
- No protection against rapid fund extraction in case of compromise
- Large sudden withdrawals could drain the treasury before incident response
- No circuit breaker to pause operations if anomalous activity detected
- Difficult to prevent economic attacks or manipulation

**Recommendation:**  
Consider implementing:
- Maximum single transaction limits
- Daily/hourly volume caps
- Time delays for large withdrawals
- Anomaly detection with automatic circuit breakers

## Low: Treasury Emergency Withdraw Has No Time Delay

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 52-58)

**Root Cause:**  
The owner can immediately withdraw any amount from the treasury with no delay, notification period, or multi-sig requirement. While this is intended for emergencies, it creates centralization risk.

**Impact:**  
- Single compromised owner key can drain all funds instantly
- No time for community or other stakeholders to react
- Users have no protection if the owner account is compromised
- Violates principles of progressive decentralization

**Recommendation:**  
Add a timelock (24-48 hours) for emergency withdrawals, require multi-sig approval, or implement a governance process for treasury access.

## Informational: Missing Input Sanitization for Chain IDs

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `initialize()` (lines 109-138)

**Root Cause:**  
The `ethereumChainId` and `eclipseChainId` strings are not validated for format, length, or content. They're directly hashed into bytes32 values without sanitization.

**Impact:**  
- Empty strings or identical chain IDs would be accepted
- Could create confusion or misconfiguration
- No enforcement of chain ID naming conventions
- Potential for duplicate chain IDs if not carefully managed

**Recommendation:**  
Add validation:
```solidity
require(bytes(params.ethereumChainId).length > 0 && bytes(params.ethereumChainId).length <= 32, "Invalid ethereum chain id");
require(bytes(params.eclipseChainId).length > 0 && bytes(params.eclipseChainId).length <= 32, "Invalid eclipse chain id");
require(keccak256(bytes(params.ethereumChainId)) != keccak256(bytes(params.eclipseChainId)), "Chain IDs must be different");
```

## Informational: Single Trusted Relayer Creates Centralization Risk

**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs` and `smart-contracts/src/v1/Mailbox.sol`  
**Constants/Roles:** `RELAYER_PUBKEY` and `TRUSTED_RELAYER_ROLE`

**Root Cause:**  
Both the Solana program and Ethereum contract rely on a single trusted relayer. All cross-chain messages must go through this one account (lines 14-17 in lib.rs and role assignment in Mailbox.sol).

**Impact:**  
- Single point of failure: if relayer is down, bridge is non-functional
- No redundancy or failover mechanism
- Relayer compromise could halt operations or manipulate messages
- Censorship risk if relayer refuses to process certain transactions

**Recommendation:**  
Consider implementing:
- Multiple relayers with threshold signatures
- Decentralized relayer network with economic incentives
- Fallback mechanisms if primary relayer is unresponsive
- Rotation policy for relayer keys

## Informational: No Versioning in Cross-Chain Messages

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs` and `smart-contracts/src/v1/EtherBridge.sol`  
**Structures:** `Message`, `DepositMessage`, `WithdrawalMessageSent`

**Root Cause:**  
The cross-chain message formats don't include version fields. If the message structure needs to change in the future, there's no backward compatibility mechanism.

**Impact:**  
- Future upgrades could break compatibility with older contracts
- No graceful migration path for protocol changes
- Relayer can't distinguish between message format versions
- Could require complex coordination for any protocol updates

**Recommendation:**  
Add a version field to all message structures:
```solidity
struct DepositMessage {
    uint8 version;
    address sender;
    bytes32 recipient;
    uint256 amountGwei;
}
```

## Informational: Solana Deposit Does Not Emit Event

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 31-62)

**Root Cause:**  
Unlike the withdrawal function which logs a message (withdraw.rs:86), the deposit function completes silently without emitting any event or log. The only record is the created PDA.

**Impact:**  
- Harder to monitor and index deposit activity
- Off-chain services must scan for PDA creation rather than listening for events
- Inconsistent with withdrawal pattern which does emit logs
- More difficult to build analytics or monitoring tools

**Recommendation:**  
Add event emission after successful deposit:
```rust
msg!("Deposit completed: eth_nonce={}, to={}, amount={}", eth_deposit_nonce, to_account.key(), amount);
```
