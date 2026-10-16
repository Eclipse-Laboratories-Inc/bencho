# Security Audit Report

## Critical: Predictable Nonce Generation Enables Replay Attacks

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 244-251)

**Root Cause:**  
The `generateRandomNonce()` function uses predictable block properties (`blockhash`, `block.timestamp`, `block.coinbase`) to generate nonces. These values are either known in advance or manipulable by miners/validators, making the nonce generation deterministic and predictable.

**Impact:**  
An attacker (especially a miner/validator) can predict future nonces and craft messages with those nonces before they are generated. Additionally, weak randomness increases the probability of nonce collisions, which could allow replay attacks if the same nonce is generated twice. This undermines the entire message authentication system.

**Recommendation:**  
Use a secure source of randomness such as Chainlink VRF or implement a simple incrementing counter instead. A counter-based approach is more secure for this use case:
```solidity
function generateRandomNonce() internal returns (uint64) {
    StorageV1 storage $ = _getStorageV1();
    $.lastNonce = $.lastNonce + 1;
    return uint64($.lastNonce);
}
```

## High: Unbounded Gas Consumption in Module Callback

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 205)

**Root Cause:**  
The external call to the module `module.call(message_)` does not specify a gas limit, forwarding all available gas to the potentially untrusted module contract.

**Impact:**  
A malicious or buggy module could consume all available gas, causing the transaction to fail and preventing legitimate messages from being processed. This creates a denial-of-service vector where the relayer wastes gas on failing transactions. Additionally, it could enable griefing attacks against the trusted relayer.

**Recommendation:**  
Limit the gas forwarded to the module to a reasonable amount:
```solidity
(bool success,) = module.call{gas: 100000}(message_);
```

## High: Missing Nonce Uniqueness Check Before Assignment

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage()` (lines 225-227)

**Root Cause:**  
The function generates a nonce and immediately sets `$.sendNonces[outboundNonce] = true` without first checking if that nonce has already been used. Due to the weak randomness in `generateRandomNonce()`, the same nonce could theoretically be generated multiple times.

**Impact:**  
If a nonce collision occurs, the second message with the same nonce would silently overwrite the first in the mapping, but both messages would be emitted as events. This could lead to duplicate message processing on the Eclipse side or lost messages if the relayer processes the second event.

**Recommendation:**  
Check for nonce uniqueness before using it:
```solidity
uint64 outboundNonce = generateRandomNonce();
require($.sendNonces[outboundNonce] == false, "Nonce collision detected");
$.sendNonces[outboundNonce] = true;
```

## High: No Validation of Deposited Amount in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 31-62)

**Root Cause:**  
The `deposit` function accepts an `amount` parameter but does not validate that this amount matches the actual lamports transferred from the relayer. The function blindly trusts the relayer-provided amount parameter and uses it to create the transfer instruction.

**Impact:**  
A compromised or malicious relayer could specify a larger `amount` than what was actually deposited on Ethereum, effectively minting free tokens. Alternatively, they could specify a smaller amount, stealing the difference. This breaks the 1:1 peg between Ethereum deposits and Solana credits.

**Recommendation:**  
The Solana program should verify the actual balance change or derive the amount from the Ethereum event data rather than accepting it as a trusted parameter. Alternatively, implement a verification mechanism that checks the amount against signed attestations from multiple sources.

## High: Insufficient Validation of Destination Address Format

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 36-89)

**Root Cause:**  
The `destination_address` parameter is accepted as an arbitrary `String` without any validation to ensure it is a valid Ethereum address. Invalid addresses could be accepted and stored.

**Impact:**  
Users could submit withdrawals with invalid or malformed destination addresses, resulting in funds being locked forever when the relayer attempts to process these withdrawals on Ethereum. The funds leave Eclipse but cannot be delivered on Ethereum. This leads to permanent loss of user funds.

**Recommendation:**  
Validate the destination address format:
```rust
require!(destination_address.len() == 42, ErrorCode::InvalidAddress);
require!(destination_address.starts_with("0x"), ErrorCode::InvalidAddress);
// Additional hex validation
```

## High: Excessive Storage Allocation Wastes User Funds

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Functions:** `WithdrawalReceipt::size()` (line 38) and `Configuration::size()` (line 69)

**Root Cause:**  
Both functions return a hardcoded 1024 bytes despite the actual data structures requiring far less space (approximately 8+32+8+1=49 bytes for `DepositReceipt`, and only 3 bytes for `Configuration`). The code includes "TODO: optimize here" comments acknowledging this issue.

**Impact:**  
Users pay approximately 20x more rent than necessary for withdrawal and configuration accounts. This represents a direct financial loss to users and makes the bridge unnecessarily expensive to use. At Solana's rent rates, this wastes significant lamports per transaction.

**Recommendation:**  
Calculate actual sizes:
```rust
impl WithdrawalReceipt {
    pub fn size() -> usize {
        8 + // discriminator
        8 + // withdrawal_nonce
        4 + 200 + // String with max 200 chars
        8 + // amount
        1 // bump
    }
}

impl Configuration {
    pub fn size() -> usize {
        8 + // discriminator
        1 + // bump
        1 + // deposits_paused
        1 // withdrawals_paused
    }
}
```

## High: Missing Access Control on Bump Parameters

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` and `withdraw.rs`  
**Functions:** `deposit()` (line 31) and `withdraw()` (line 36)

**Root Cause:**  
Both functions accept a `bump` parameter from the caller but do not validate it against the actual PDA bump seed derived by Anchor. A caller could provide an incorrect bump value that doesn't match the account's actual bump.

**Impact:**  
While Anchor's PDA derivation provides some protection, accepting and storing an unvalidated bump could lead to issues when the bump is later used for signing operations or account validation. This could potentially enable account confusion attacks or break assumptions in future code that relies on the stored bump value.

**Recommendation:**  
Validate the bump parameter:
```rust
let expected_bump = ctx.bumps.deposit_receipt;
require!(bump == expected_bump, ErrorCode::InvalidBump);
deposit_receipt.bump = bump;
```

## Medium: Front-Running Vulnerability in Withdrawal Nonce Selection

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw()` (lines 36-89)

**Root Cause:**  
Users select their own `withdrawal_nonce` value when initiating a withdrawal. The PDA derivation ensures uniqueness, but a malicious actor can observe pending withdrawal transactions in the mempool and attempt to front-run by using the same nonce.

**Impact:**  
An attacker monitoring the mempool could front-run a user's withdrawal with the same nonce but a different destination address. The attacker's transaction would succeed, and the victim's transaction would fail with an "account already exists" error. While the victim doesn't lose funds (their transaction fails), they experience a denial-of-service and must retry with a different nonce, wasting transaction fees.

**Recommendation:**  
Derive the nonce deterministically from the user's address and a counter:
```rust
seeds = [
    b"withdrawal",
    withdrawer.key().as_ref(),
    user_withdrawal_count.to_le_bytes().as_ref()
]
```
Maintain a counter per user to ensure uniqueness and prevent front-running.

## Medium: Treasury Emergency Withdraw Bypasses Pause State

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 52-58)

**Root Cause:**  
The `emergencyWithdraw` function only checks `onlyOwner` but does not respect the contract's `whenNotPaused` state. Funds can be withdrawn even when the contract is paused.

**Impact:**  
If the contract is paused due to a security incident or bug, the owner can still withdraw funds, potentially draining the treasury before the issue is resolved. This undermines the pause functionality as a safety mechanism and could enable an owner to exit scam even after pausing.

**Recommendation:**  
Add the `whenNotPaused` modifier or create a separate emergency unpause mechanism:
```solidity
function emergencyWithdraw(uint256 amount) external virtual override onlyOwner whenNotPaused nonReentrant {
    // ... existing code
}
```

## Medium: Inefficient Gas Usage Due to Late Module Validation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 196-212)

**Root Cause:**  
The function validates the security parameter nonce and stores it (lines 198-200) before checking if the destination module exists (line 203-204). If the module doesn't exist, the transaction reverts after already consuming gas for nonce validation and storage.

**Impact:**  
Invalid messages targeting non-existent modules waste gas by performing expensive storage operations before the validation that would cause a revert. This makes the trusted relayer more expensive to operate and could be exploited to drain the relayer's funds through repeated invalid messages.

**Recommendation:**  
Reorder the checks to validate module existence first:
```solidity
// Check module exists first
address module = $.modulesById[bytes32(sender_)];
require(module != address(0), "Module does not exist.");

// Then validate and store nonce
EclipseSecurityParam memory secParam = abi.decode(data_, (EclipseSecurityParam));
require($.receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");
$.receiveNonces[secParam.nonce] = true;
```

## Medium: Missing Event Emission in Critical Admin Functions

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Functions:** `addModule()` (lines 141-154) and `removeModule()` (lines 157-174)

**Root Cause:**  
The `addModule` and `removeModule` functions modify critical access control state (which contracts can send messages) but do not emit events documenting these changes.

**Impact:**  
Off-chain monitoring systems and users cannot track when modules are added or removed, making it difficult to detect unauthorized changes or build a complete audit trail. This reduces transparency and makes incident response more difficult if a malicious module is added.

**Recommendation:**  
Add events and emit them:
```solidity
event ModuleAdded(bytes32 indexed moduleId, address indexed module);
event ModuleRemoved(bytes32 indexed moduleId, address indexed module);

function addModule(bytes32 moduleId, address module) external ... {
    // ... existing code
    emit ModuleAdded(moduleId, module);
}
```

## Medium: Chain ID Duplication Not Prevented

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `initialize()` (lines 109-138)

**Root Cause:**  
The initialization function accepts `ethereumChainId` and `eclipseChainId` parameters but does not validate that they are different from each other.

**Impact:**  
If the same chain ID is accidentally used for both Ethereum and Eclipse during initialization, the chain ID validation in `ethereumChainIdValid` and `eclipseChainIdValid` modifiers becomes meaningless. Messages from Eclipse would be accepted as Ethereum messages and vice versa, completely breaking the cross-chain security model.

**Recommendation:**  
Add validation during initialization:
```solidity
bytes32 ethChainId = generateChainId(params.ethereumChainId);
bytes32 eclChainId = generateChainId(params.eclipseChainId);
require(ethChainId != eclChainId, "Chain IDs must be different");
```

## Medium: No Maximum Deposit Limit

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-128)

**Root Cause:**  
While there is a `MIN_DEPOSIT` check, there is no corresponding maximum deposit limit. Users can deposit arbitrarily large amounts in a single transaction.

**Impact:**  
Extremely large deposits could create several risks: (1) if there's a bug in the bridge logic, the potential loss is unbounded; (2) the relayer may not have sufficient funds to credit on the Eclipse side; (3) it increases the blast radius of any exploit. Additionally, very large deposits might exceed the maximum account size or balance limits on the Solana side.

**Recommendation:**  
Implement a configurable maximum deposit:
```solidity
uint256 public maxDeposit = 100 ether; // Configurable by admin

modifier validDepositAmount(uint256 amountWei) {
    require(msg.value == amountWei, "Deposit amount and msg.value must be equal");
    require(msg.value >= MIN_DEPOSIT, "Deposit amount too small");
    require(msg.value <= maxDeposit, "Deposit amount too large");
    // ... rest of checks
}
```

## Low: Missing Zero-Value Deposit Check

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (lines 101-128)

**Root Cause:**  
While the `MIN_DEPOSIT` constant indirectly prevents zero-value deposits, there is no explicit check that `amountWei > 0`. The validation relies on the minimum deposit calculation.

**Impact:**  
If `MIN_DEPOSIT` is ever misconfigured or set to zero, the contract would accept zero-value deposits. While this wouldn't result in loss of funds, it would create useless deposit records and waste gas for the relayer processing these empty deposits.

**Recommendation:**  
Add an explicit zero-value check:
```solidity
modifier validDepositAmount(uint256 amountWei) {
    require(amountWei > 0, "Deposit amount must be greater than zero");
    require(msg.value == amountWei, "Deposit amount and msg.value must be equal");
    // ... rest of checks
}
```

## Low: Potential Nonce Overflow Not Handled

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 244-251)

**Root Cause:**  
The `lastNonce` is stored as a `uint256` but cast to `uint64` when returned. If `lastNonce` exceeds `uint64` maximum value (2^64 - 1), the cast will silently truncate, potentially creating duplicate nonces.

**Impact:**  
After 2^64 nonces (an astronomically large number in practice), the system would start generating previously used nonces, enabling replay attacks. While extremely unlikely to occur in practice, it represents a theoretical unbounded state issue.

**Recommendation:**  
Store `lastNonce` as `uint64` directly or check for overflow:
```solidity
uint256 newNonce = uint256(keccak256(...));
require(newNonce <= type(uint64).max, "Nonce overflow");
return uint64(newNonce);
```

## Low: Missing Input Validation on Message Length

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 176-212)

**Root Cause:**  
The function validates that `message_` is initialized (non-empty) but doesn't check for maximum length. Extremely large messages could be submitted.

**Impact:**  
While the `bytesInitialized` modifier ensures the message is not empty, there's no upper bound. Maliciously large messages could cause excessive gas consumption during decoding and processing, or exceed the gas limit. This makes the relayer's operations unpredictable and potentially expensive.

**Recommendation:**  
Add a maximum message size check:
```solidity
uint256 constant MAX_MESSAGE_SIZE = 10000; // bytes

modifier validateMessageSize(bytes memory message_) {
    require(message_.length <= MAX_MESSAGE_SIZE, "Message too large");
    _;
}
```

## Low: Relayer Balance Not Verified Before Transfer

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit()` (lines 31-62)

**Root Cause:**  
The function creates a transfer instruction from the relayer to the recipient without first checking if the relayer has sufficient balance to cover the transfer amount.

**Impact:**  
If the relayer's balance is insufficient, the transfer will fail, but only after the deposit receipt has been created and rent paid. This wastes the user's (or relayer's) rent payment on a failed transaction. While not a security vulnerability per se, it represents poor UX and inefficient design.

**Recommendation:**  
Add a balance check before creating the transfer:
```rust
require!(
    from_account.lamports() >= amount,
    ErrorCode::InsufficientRelayerBalance
);
```

## Informational: Inconsistent Pause State Checks

**File:** `smart-contracts/src/v1/EtherBridge.sol` and `Treasury.sol`  
**Functions:** `deposit()` (line 106) and `receive()` (line 72)

**Root Cause:**  
The `EtherBridge.deposit()` function uses `whenNotPaused` modifier, and `Treasury.receive()` also uses `whenNotPaused`. However, if the Treasury is paused but EtherBridge is not, deposits would fail at the Treasury receive function rather than at the deposit entry point.

**Impact:**  
Inconsistent error messages and user experience. If Treasury is paused independently, users attempting deposits will get a less informative error message ("Unauthorized source" or pause error from Treasury) instead of a clear "deposits paused" message from EtherBridge.

**Recommendation:**  
Ensure pause states are synchronized or check Treasury pause state in EtherBridge:
```solidity
function deposit(...) external payable ... {
    require(!$.treasuryProxy.paused(), "Treasury is paused");
    // ... rest of function
}
```

## Informational: Redundant Balance Check in Emergency Withdraw

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 52-58)

**Root Cause:**  
The function checks `require(address(this).balance >= amount, "Insufficient funds")` before attempting the transfer. However, the low-level call would revert anyway if the balance is insufficient.

**Impact:**  
No security impact. The check provides a slightly better error message but is redundant from a security perspective. It does save a small amount of gas by reverting earlier with a custom message rather than letting the transfer fail.

**Recommendation:**  
This is acceptable as-is for better UX, but could be removed if gas optimization is a priority. Consider keeping it for the improved error message.

## Informational: Missing Documentation on Nonce Reuse Prevention

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` and `withdraw.rs`  
**Functions:** `deposit()` and `withdraw()`

**Root Cause:**  
The functions rely on PDA derivation (using nonces as seeds) to prevent duplicate transactions, but this mechanism is not documented in comments. Developers reviewing the code might not immediately understand how replay protection works.

**Impact:**  
No direct security impact, but lack of documentation makes the code harder to audit and maintain. Future developers might not understand the security properties and could inadvertently break the replay protection when modifying the code.

**Recommendation:**  
Add documentation:
```rust
/// Prevents replay attacks through PDA derivation:
/// - Seeds include the nonce, ensuring each nonce can only be used once
/// - Attempting to reuse a nonce will fail because the PDA already exists
pub fn deposit(ctx: Context<Deposit>, eth_deposit_nonce: u64, ...) -> Result<()> {
```
