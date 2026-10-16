# Security Audit Report

## Critical: Unbounded External Call to Module Contract

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage` (line 205-206)

**Root Cause:**  
The `receiveMessage` function performs an unbounded external call to a module contract without specifying a gas limit. The code executes:
```solidity
(bool success,) = module.call(message_);
require(success, "External call to module failed.");
```

This allows the called module to consume all available gas, potentially causing the transaction to fail. More critically, if a module is compromised or malicious, it can execute arbitrary code with all remaining gas, potentially performing reentrancy attacks on other contracts or manipulating state in unexpected ways.

**Impact:**  
- Denial of service: A malicious or buggy module can consume all gas
- Reentrancy vulnerability: The module can call back into Mailbox or other contracts
- Unpredictable behavior: No control over what the module executes

**Recommendation:**  
Specify a reasonable gas limit for the external call and validate the return data:
```solidity
(bool success,) = module.call{gas: 100000}(message_);
```

## Critical: Missing Signer Seeds in Solana Transfers

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (lines 51-59)

**Root Cause:**  
The `invoke_signed` function is called with empty signer seeds (`&[]`) when transferring tokens:
```rust
anchor_lang::solana_program::program::invoke_signed(
    &transfer_instruction,
    &[...],
    &[],  // Empty signer seeds!
)?;
```

The same issue exists in `withdraw.rs` at lines 60-68. The transfer instruction is created with the relayer as the `from_account`, but when `invoke_signed` is called with empty seeds, the program is not actually signing the transaction. This means the transfer relies solely on the relayer's signature from the transaction itself, not the program's authority.

**Impact:**  
- Authorization bypass: The program doesn't properly authorize transfers using PDAs
- The relayer must sign the transaction, creating unnecessary centralization
- Violates the intended design of using program-derived addresses for security

**Recommendation:**  
If the program should control the funds via a PDA, derive proper signer seeds and use them:
```rust
let seeds = &[b"authority".as_ref(), &[bump]];
anchor_lang::solana_program::program::invoke_signed(
    &transfer_instruction,
    &[...],
    &[seeds],
)?;
```

## High: Weak Randomness for Nonce Generation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce` (lines 244-251)

**Root Cause:**  
The function generates nonces using predictable blockchain state:
```solidity
$.lastNonce = uint256(
    keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
);
```

While this appears random, all these values are publicly known or predictable:
- `lastNonce` is stored in contract state
- `blockhash(block.number - 1)` is public
- `block.timestamp` is controlled by miners within bounds
- `block.coinbase` is the miner's address

Miners/validators can predict or manipulate these values to influence nonce generation, potentially enabling replay attacks or nonce collision.

**Impact:**  
- Predictable nonces allow attackers to anticipate future values
- Miners can manipulate `block.timestamp` and `block.coinbase` to some degree
- Could enable nonce collision attacks if an attacker can predict the same nonce

**Recommendation:**  
Use a combination of user-provided entropy and chain VRF (if available), or implement a simple counter-based nonce system with user-specific salts to ensure uniqueness without requiring unpredictability.

## High: Unvalidated Bump Seeds in Solana PDAs

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (line 36)

**Root Cause:**  
The `bump` parameter is accepted as a function argument and stored without validation against the actual canonical bump seed for the PDA:
```rust
pub fn deposit(ctx: Context<Deposit>, eth_deposit_nonce: u64, amount: u64, bump: u8) -> Result<()> {
    // ...
    deposit_receipt.bump = bump; // Stored without validation
}
```

The same issue exists in `withdraw.rs`. While Anchor validates the PDA derivation in the `#[account(...)]` macro using `seeds` and `bump`, the bump value passed as a parameter could theoretically differ from the canonical bump if the account was initialized incorrectly or if there's a mismatch.

**Impact:**  
- Using non-canonical bump seeds could lead to PDA derivation issues
- Future operations depending on the stored bump may fail or use wrong addresses
- Potential for using PDAs that don't match the intended seeds

**Recommendation:**  
Use the bump value from `ctx.bumps` which Anchor validates:
```rust
deposit_receipt.bump = ctx.bumps.deposit_receipt;
```

## High: Missing Withdrawal Mechanism from Ethereum

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** N/A (missing functionality)

**Root Cause:**  
The `EtherBridge` contract implements a `deposit` function to lock ETH in the Treasury (line 101-128), but there is no corresponding `withdraw` function to allow users to retrieve their ETH from Ethereum after bridging back from Eclipse. The only withdrawal mechanism is `Treasury.emergencyWithdraw` (line 52), which is restricted to the contract owner.

**Impact:**  
- Funds are one-way locked: Users can deposit but cannot withdraw through normal operations
- All bridged ETH remains permanently locked in the Treasury unless the owner performs emergency withdrawals
- Users bridging from Eclipse back to Ethereum have no on-chain mechanism to claim their funds
- Creates centralization risk and dependency on the owner for fund recovery

**Recommendation:**  
Implement a `withdraw` function that:
1. Receives withdrawal messages from the Mailbox (relayed from Eclipse)
2. Validates the withdrawal request (amount, recipient, nonce)
3. Transfers ETH from Treasury to the recipient
4. Prevents replay attacks using nonces

## Medium: Trusted Relayer Can Replay Messages with Controlled Nonces

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage` (lines 196-212)

**Root Cause:**  
The trusted relayer controls which messages get relayed and provides the nonce in the security parameters:
```solidity
EclipseSecurityParam memory secParam = abi.decode(data_, (EclipseSecurityParam));
require($.receiveNonces[secParam.nonce] == false, "Message with this nonce already received.");
```

While the nonce check prevents replaying the same nonce twice, the trusted relayer has complete control over:
- Which messages to relay and which to drop
- The order of message relay
- The nonce values used (as long as they're unique)

**Impact:**  
- Censorship: The relayer can selectively drop messages
- Reordering attacks: Messages can be delivered out of order
- Single point of failure: If the relayer is compromised, all cross-chain messaging is compromised
- No fraud proofs or verification mechanism for relayer behavior

**Recommendation:**  
Implement additional verification mechanisms:
1. Add message commitment proofs from Eclipse chain state
2. Implement a challenge period for disputed messages
3. Consider multi-signature or threshold relay mechanisms
4. Add monitoring and alerting for suspicious relayer behavior

## Medium: No Validation of Nonce Uniqueness in Solana Withdrawals

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw` (lines 36-89)

**Root Cause:**  
The withdrawal function creates a PDA using the `withdrawal_nonce` as a seed:
```rust
seeds = [
    b"withdrawal",
    withdrawal_nonce.to_le_bytes().as_ref()
],
```

While Anchor's `init` constraint will fail if the account already exists, there's no explicit validation that the nonce is sequential, monotonically increasing, or follows any pattern. A user could theoretically skip nonces or choose specific values.

**Impact:**  
- Non-sequential nonces make tracking and verification difficult
- Users could potentially front-run others by choosing strategic nonce values
- Off-chain indexers may struggle to track all withdrawals if nonces are sparse
- No guarantee that withdrawal nonces match any expected sequence

**Recommendation:**  
Implement a global withdrawal counter in the Configuration account and enforce sequential nonce assignment:
```rust
pub struct Configuration {
    pub bump: u8,
    pub deposits_paused: bool,
    pub withdrawals_paused: bool,
    pub next_withdrawal_nonce: u64, // Add this
}
```

## Medium: Deposits Not Validated Against Eclipse Nonce Uniqueness

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (lines 31-62)

**Root Cause:**  
The deposit function uses `eth_deposit_nonce` provided by the relayer as a seed for the PDA, but doesn't validate this nonce against any on-chain record of used nonces from Ethereum:
```rust
seeds = [b"deposit", eth_deposit_nonce.to_le_bytes().as_ref()],
```

While the `init` constraint prevents duplicate PDAs, there's no validation that:
1. This nonce corresponds to an actual Ethereum deposit event
2. The nonce is the next expected sequential value
3. The amount matches what was deposited on Ethereum

**Impact:**  
- Relayer could skip nonces, leaving deposits unprocessed
- No on-chain verification that deposits match Ethereum events
- Reliance on relayer honesty for nonce assignment
- Potential for deposits to be processed out of order

**Recommendation:**  
Add verification that deposit nonces are sequential or implement a mapping to track which Ethereum deposit nonces have been processed. Consider adding message commitment verification from Ethereum.

## Medium: Insufficient Access Control on Module Management

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Functions:** `addModule` (lines 141-154), `removeModule` (lines 157-174)

**Root Cause:**  
The `addModule` and `removeModule` functions are marked as `NOT UNIT TESTED` and allow the admin to add or remove modules at any time. While restricted to admin-only, there are several issues:

1. No event emission when modules are added/removed (makes tracking difficult)
2. No timelock or governance delay for critical operations
3. `removeModule` requires providing both `moduleId` and `module` address but only checks if they match (line 168)
4. No validation that the module address is a contract

**Impact:**  
- Admin can instantly add malicious modules that steal funds
- No transparency or warning period for module changes
- Difficult to audit module changes without events
- Could add EOA addresses as modules (though they would fail when called)

**Recommendation:**  
1. Add events for `ModuleAdded` and `ModuleRemoved`
2. Implement a timelock delay for adding new modules
3. Consider requiring only `moduleId` for removal (derive address from storage)
4. Add contract existence check for new modules

## Medium: Treasury Receive Function Can Be Bypassed

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `receive` (lines 72-76)

**Root Cause:**  
The `receive` function enforces that only the EtherBridge or owner can send ETH:
```solidity
receive() external payable virtual whenNotPaused {
    StorageV1 storage $ = _getStorageV1();
    require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
}
```

However, this validation can be bypassed using `selfdestruct`. An attacker can deploy a contract with ETH and call `selfdestruct(treasuryAddress)`, forcibly sending ETH to the Treasury without triggering the `receive` function. While this doesn't directly steal funds, it can cause accounting issues.

**Impact:**  
- ETH balance can be artificially inflated through selfdestruct
- Accounting mismatches between deposited amounts and actual balance
- Emergency withdrawal could withdraw more than was legitimately deposited
- Though unlikely to be exploitable for profit, creates accounting complexity

**Recommendation:**  
Document this behavior and ensure that emergency withdrawal logic doesn't rely on balance accounting. Consider implementing a separate `totalDeposited` tracker that only increments through the `receive` function. Note: After EIP-6049, selfdestruct behavior is changing, so verify current chain compatibility.

## Low: Inefficient Storage Allocation in Solana State

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`  
**Functions:** `WithdrawalReceipt::size()` (lines 38-40), `Configuration::size()` (lines 69-71)

**Root Cause:**  
Both functions return hardcoded 1024 bytes with TODO comments:
```rust
pub fn size() -> usize {
    1024  // TODO: optimize here
}
```

For `WithdrawalReceipt`, the actual size needed is approximately:
- 8 (discriminator) + 8 (u64 nonce) + 4-32 (String with address) + 8 (u64 amount) + 1 (u8 bump) = ~61 bytes minimum

For `Configuration`:
- 8 (discriminator) + 1 (bump) + 1 (deposits_paused) + 1 (withdrawals_paused) = 11 bytes

**Impact:**  
- Users pay significantly more rent than necessary
- Wasted on-chain storage space
- Increased cost for every deposit and withdrawal
- 1024 bytes when ~100 bytes needed is 10x overhead

**Recommendation:**  
Calculate exact sizes needed:
```rust
impl WithdrawalReceipt {
    pub fn size() -> usize {
        8 + // discriminator
        8 + // withdrawal_nonce
        4 + 64 + // String with max Ethereum address length
        8 + // amount
        1   // bump
    }
}

impl Configuration {
    pub fn size() -> usize {
        8 + // discriminator
        1 + // bump
        1 + // deposits_paused  
        1   // withdrawals_paused
    }
}
```

## Low: Unused ChainId Parameter in sendMessage

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage` (line 215)

**Root Cause:**  
The `sendMessage` function signature includes a `chainId_` parameter but it's not used in the function body:
```solidity
function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
```

The first parameter (unnamed `bytes memory`) is passed in but never referenced. Instead, the function uses the stored `ethereumChainId` from storage (line 231). Looking at `EtherBridge.deposit` (line 120), empty bytes `""` are passed for this parameter.

**Impact:**  
- Confusing interface: callers might expect to specify destination chain
- Gas waste: passing bytes that are never used
- Misleading documentation: interface suggests cross-chain flexibility that doesn't exist
- No actual security impact, but poor design

**Recommendation:**  
Either remove the unused parameter or use it to validate the destination chain:
```solidity
function sendMessage(bytes memory receiver_, bytes memory message_)
    external
    payable
    virtual
    override
    onlyModule
    nonReentrant
    returns (bool)
```

## Low: Missing Event Emission in Deposit Function

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`  
**Function:** `deposit` (lines 31-62)

**Root Cause:**  
The deposit function successfully creates a deposit receipt and transfers funds but doesn't emit a Solana event/log. While it's a critical operation that should be observable by off-chain systems, there's no programmatic event emission. The only logging is a debug message for the paused status (line 37).

**Impact:**  
- Difficult for off-chain indexers to track deposits
- No standardized event for monitoring deposit activity
- Reduced transparency and auditability
- Must rely on account change tracking instead of events

**Recommendation:**  
Emit a proper event after successful deposit:
```rust
emit!(DepositCompleted {
    eth_deposit_nonce,
    recipient: to_account.key(),
    amount,
});
```

## Low: Mailbox sendMessage Returns True Without Validation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage` (lines 215-234)

**Root Cause:**  
The `sendMessage` function always returns `true` at the end (line 233) without any validation that the message was actually sent or that the event emission succeeded:
```solidity
emit MessageSent(receiver_, encodeChainId($.ethereumChainId), message_, param);
return true;
```

Event emission cannot fail in Solidity, but the function gives the impression that message sending could fail when it cannot. The calling contract (`EtherBridge.deposit` line 120-121) checks this return value:
```solidity
bool success = $.mailboxProxy.sendMessage(...);
require(success, "Unable to forward deposit message to Mailbox");
```

**Impact:**  
- Misleading return value suggests validation that doesn't exist
- False sense of security for calling contracts
- Cannot actually detect any failure conditions
- No practical security impact since events always succeed

**Recommendation:**  
Either make the function `returns (bool)` meaningful by adding validation checks, or change it to not return a value and update calling contracts accordingly.

## Informational: Hardcoded Authority Addresses in Solana Program

**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`  
**Lines:** 14-23

**Root Cause:**  
The relayer and bridge authority public keys are hardcoded in the program with feature flags:
```rust
#[cfg(feature = "use_test_authority")]
pub const RELAYER_PUBKEY: Pubkey = pubkey!("T3STfZppYxqPCYS9fLoitN7RiADdRBsJ1c7rN3gNKTc");

#[cfg(not(feature = "use_test_authority"))]
pub const RELAYER_PUBKEY: Pubkey = pubkey!("ec1vCnQKsQSnTbcTyc3SH2azcDXZquiFB3QqtRvm3Px");
```

**Impact:**  
- Centralization: Single relayer and authority control
- If private keys are compromised, cannot update without program upgrade
- No multi-sig or distributed authority
- Feature flag configuration must be correct during build

**Recommendation:**  
Consider storing these addresses in the Configuration account to allow updates without program upgrades:
```rust
pub struct Configuration {
    pub bump: u8,
    pub deposits_paused: bool,
    pub withdrawals_paused: bool,
    pub relayer: Pubkey,
    pub authority: Pubkey,
}
```

## Informational: Missing Input Validation for Ethereum Address

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`  
**Function:** `withdraw` (line 38)

**Root Cause:**  
The `destination_address` parameter is accepted as a String without validation:
```rust
destination_address: String,
```

There's no check that:
1. The string is a valid Ethereum address format (0x + 40 hex characters)
2. The string length is reasonable (could be very large)
3. It's not empty or contains special characters

**Impact:**  
- Users could accidentally provide invalid addresses
- Could store arbitrarily long strings, wasting space
- Withdrawal message sent to Ethereum might be malformed
- Funds could be lost if an invalid address is used

**Recommendation:**  
Add validation for Ethereum address format:
```rust
require!(
    destination_address.starts_with("0x") && destination_address.len() == 42,
    ErrorCode::InvalidEthereumAddress
);
```

## Informational: Missing Pausable Check in Mailbox receiveMessage

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage` (lines 177-212)

**Root Cause:**  
While `EtherBridge` and `Treasury` both inherit `PausableUpgradeable` and use `whenNotPaused` modifiers, the `Mailbox` contract does not implement any pause functionality. This means messages can continue to be received even during emergency situations where deposits and withdrawals are paused.

**Impact:**  
- No emergency stop mechanism for cross-chain messaging
- Messages continue flowing even when bridge components are paused
- Inconsistent emergency response capabilities across contracts
- Could complicate emergency responses if message processing needs to stop

**Recommendation:**  
Consider adding `PausableUpgradeable` to Mailbox and using `whenNotPaused` on critical functions, or document why message flow should continue even during emergencies.

## Informational: Missing Zero Amount Check in Deposit and Withdraw

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` and `withdraw.rs`  
**Functions:** `deposit` (line 31), `withdraw` (line 36)

**Root Cause:**  
Neither the deposit nor withdraw functions validate that the `amount` parameter is greater than zero:
```rust
pub fn deposit(ctx: Context<Deposit>, eth_deposit_nonce: u64, amount: u64, bump: u8)
```

While Solana's `system_instruction::transfer` would fail for zero-amount transfers, it's better to fail early with a clear error message.

**Impact:**  
- Wasted gas/compute for transactions that will fail
- Less clear error messages for users
- Unnecessary PDA creation for invalid operations (deposit receipt created before transfer)
- Could create deposit/withdrawal records for zero amounts

**Recommendation:**  
Add validation:
```rust
require!(amount > 0, ErrorCode::InvalidAmount);
```
