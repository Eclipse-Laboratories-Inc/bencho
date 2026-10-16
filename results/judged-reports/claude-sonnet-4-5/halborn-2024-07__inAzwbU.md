# Security Audit Report

## Critical: Predictable Nonce Generation Enables Replay and DoS Attacks

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 257-264)

**Root Cause:**  
The nonce generation mechanism relies on predictable block properties including `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase`. These values are either known in advance or can be influenced by miners/validators, making the "random" nonces predictable.

**Impact:**  
1. An attacker (especially a block proposer) can predict future nonces and preemptively mark them as used in either `receiveNonces` or `sendNonces` mappings
2. This enables denial-of-service by causing all future `sendMessage` calls to revert with "Nonce collision" (line 238)
3. Predictable nonces undermine the replay protection mechanism
4. The 64-bit nonce space combined with predictability increases collision probability

**Recommendation:**  
Use a counter-based nonce system instead of pseudo-random generation. Simply increment a `uint256` counter for each message sent/received. This is deterministic, collision-free, and gas-efficient.

---

## High: sender_ Parameter Not Validated for Length in receiveMessage

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 213)

**Root Cause:**  
The `sender_` parameter is cast to `bytes32` without verifying its length is exactly 32 bytes. The modifier `bytesInitialized(sender_)` only checks that length > 0, not that length == 32.

```solidity
address module = $.modulesById[bytes32(sender_)];
```

**Impact:**  
1. If `sender_` is shorter than 32 bytes, the cast will right-pad with zeros, potentially routing to the wrong module
2. If `sender_` is longer than 32 bytes, the cast will truncate, also causing incorrect routing
3. An attacker controlling the relayer could exploit this to route messages to unintended modules or bypass module authentication

**Recommendation:**  
Add the `bytesLengthEq32(sender_)` modifier to `receiveMessage`, similar to how it's applied to `eclipseChainId_`.

---

## High: Arbitrary External Call Allows Unrestricted Function Execution

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 215)

**Root Cause:**  
The message content is passed directly to an external call without any validation:

```solidity
(bool success,) = module.call(message_);
require(success, "External call to module failed.");
```

**Impact:**  
1. The trusted relayer can invoke ANY function on ANY registered module with arbitrary parameters
2. Modules must implement comprehensive authentication and validation since the mailbox provides none
3. A compromised relayer could drain funds, manipulate state, or brick modules
4. The security model places complete trust in the relayer with no protocol-level safeguards

**Recommendation:**  
1. Define a strict interface that modules must implement (e.g., `receiveMessage(bytes calldata)`)
2. Use interface calls instead of low-level `call`
3. Consider adding message type validation or a whitelist of allowed function selectors
4. Implement additional authentication beyond relayer trust

---

## High: No Withdrawal Mechanism Creates Permanent Fund Lock Risk

**File:** `EtherBridge.sol`  
**Function:** N/A (missing functionality)

**Root Cause:**  
The `EtherBridge` contract only implements `deposit()` with no corresponding withdrawal function. Users depend entirely on the trusted relayer to process their deposits on Eclipse. If the relayer fails, goes offline, or acts maliciously, user funds are permanently locked in the Treasury.

**Impact:**  
1. No escape hatch for users if relayer stops operating
2. No timeout mechanism to reclaim funds from failed deposits
3. Single point of failure creates existential risk for all deposited funds
4. Users have no recourse if their deposit message is never processed on Eclipse

**Recommendation:**  
Implement a time-delayed withdrawal mechanism where users can reclaim their deposits if not processed within a timeout period (e.g., 7 days). This requires tracking individual deposits and their timestamps.

---

## High: MODULE_ROLE and modulesById Mapping Can Desynchronize

**File:** `Mailbox.sol`  
**Functions:** `addModule()`, `removeModule()`, `sendMessage()`, `receiveMessage()`

**Root Cause:**  
The contract maintains two separate access control mechanisms:
1. `MODULE_ROLE` from OpenZeppelin's AccessControl (checked in `sendMessage` via `onlyModule` modifier)
2. `modulesById` mapping (checked in `receiveMessage` at line 213)

Administrators can call OpenZeppelin's `grantRole()` or `revokeRole()` directly, bypassing `addModule()`/`removeModule()`, causing desynchronization.

**Impact:**  
1. A module granted `MODULE_ROLE` directly can call `sendMessage` but won't receive messages (not in `modulesById`)
2. A module added to `modulesById` but without `MODULE_ROLE` can receive messages but can't send them
3. Inconsistent authorization creates security gaps and operational failures
4. The `receiveMessage` function never checks `MODULE_ROLE`, only `modulesById`

**Recommendation:**  
1. Override `grantRole()` and `revokeRole()` to prevent direct role manipulation for `MODULE_ROLE`
2. Make `addModule()` and `removeModule()` the only way to manage module access
3. Alternatively, use only `modulesById` for all authorization checks and remove `MODULE_ROLE` dependency

---

## Medium: Reentrancy Guard Prevents Legitimate Message Response Pattern

**File:** `Mailbox.sol`  
**Functions:** `receiveMessage()`, `sendMessage()`

**Root Cause:**  
Both `receiveMessage` and `sendMessage` use the `nonReentrant` modifier, which shares the same storage slot in OpenZeppelin's ReentrancyGuard. When `receiveMessage` calls a module (line 215), the reentrancy guard is active. If that module attempts to call `sendMessage` to respond, it will revert because the guard is still set.

**Impact:**  
1. Modules cannot send response messages within the same transaction that processes received messages
2. Common cross-chain messaging patterns (request-response) are blocked
3. Modules must defer sending to a separate transaction, complicating the protocol
4. This limitation may not be immediately apparent to module developers

**Recommendation:**  
1. Use separate reentrancy guards for `sendMessage` and `receiveMessage` if they need different protection
2. Allow `sendMessage` during `receiveMessage` execution if the calling pattern is safe
3. Document this limitation prominently if it's intentional
4. Consider using a checks-effects-interactions pattern instead of reentrancy guards where possible

---

## Medium: Single Trusted Relayer Is Immutable Single Point of Failure

**File:** `Mailbox.sol`  
**Function:** `initialize()` (line 135)

**Root Cause:**  
The trusted relayer is granted `TRUSTED_RELAYER_ROLE` during initialization with no function to update or change it. The only way to change the relayer is to upgrade the entire contract.

**Impact:**  
1. If the relayer's private key is compromised, the entire system is compromised until an upgrade is deployed
2. If the relayer goes offline or loses its key, cross-chain messaging halts
3. No ability to rotate credentials or perform emergency relayer changes
4. Upgrade process may be slow, leaving the system vulnerable during incident response

**Recommendation:**  
Add an admin function to update the trusted relayer:
```solidity
function setTrustedRelayer(address newRelayer) external onlyAuthority {
    _revokeRole(TRUSTED_RELAYER_ROLE, <current_relayer>);
    _grantRole(TRUSTED_RELAYER_ROLE, newRelayer);
    emit TrustedRelayerUpdated(newRelayer);
}
```

---

## Medium: Treasury Pause Causes Complete Bridge Denial of Service

**File:** `Treasury.sol` (line 83), `EtherBridge.sol` (line 115)  
**Functions:** `Treasury.receive()`, `EtherBridge.deposit()`

**Root Cause:**  
The Treasury's `receive()` function has a `whenNotPaused` modifier. When paused, it rejects all incoming ETH transfers. The `EtherBridge.deposit()` function transfers ETH to the Treasury (line 115), which will fail if the Treasury is paused.

**Impact:**  
1. Pausing the Treasury bricks the entire EtherBridge deposit functionality
2. The pause states are not synchronized between contracts
3. Users attempting to deposit will have transactions fail with no clear error message
4. Creates a cascading failure mode across contract boundaries

**Recommendation:**  
1. Coordinate pause states: if Treasury is paused, automatically pause EtherBridge
2. Add explicit checks in `EtherBridge.deposit()` to verify Treasury can accept funds
3. Consider whether Treasury pause should affect deposits differently than emergency withdrawals
4. Emit clear events when cross-contract dependencies cause failures

---

## Medium: Nonce Collision Causes Transaction Failure and User Frustration

**File:** `Mailbox.sol`  
**Function:** `sendMessage()` (lines 237-239)

**Root Cause:**  
When `generateRandomNonce()` produces a previously used nonce (stored in `sendNonces`), the transaction reverts:

```solidity
if ($.sendNonces[outboundNonce] == true) {
    revert("Nonce collision");
}
```

Combined with the weak randomness described in Critical finding #1, collisions are more likely than with true randomness.

**Impact:**  
1. User transactions fail through no fault of their own
2. Must retry with different block conditions, wasting gas
3. In high-traffic scenarios, collision probability increases
4. Attackers can deliberately cause collisions to DoS specific users

**Recommendation:**  
Replace pseudo-random nonce generation with a deterministic counter to completely eliminate collision risk.

---

## Medium: Unbounded Storage Growth From Never-Cleared Nonce Mappings

**File:** `Mailbox.sol`  
**Storage:** `receiveNonces`, `sendNonces` mappings (lines 57-58)

**Root Cause:**  
Every message sent or received adds a permanent entry to the respective nonce mapping. These mappings grow indefinitely with no mechanism for cleanup or archival.

**Impact:**  
1. Ever-increasing storage costs as the protocol scales
2. After approximately 2^64 messages, the entire 64-bit nonce space is exhausted
3. At scale, storage costs could exceed the gas limit for contract operations
4. No way to prune old, no-longer-relevant nonces

**Recommendation:**  
1. Use a counter-based nonce system where only the highest used nonce needs to be stored
2. If random nonces are required for security, implement a time-windowed nonce system where old nonces expire
3. Consider using a bitmap for nonce tracking to reduce storage costs
4. Add administrative functions to archive or compress historical nonce data

---

## Low: Modules Receive Unrestricted External Calls Without Protocol-Level Validation

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 215)

**Root Cause:**  
The Mailbox forwards messages to modules with no validation of the message content, function selector, or parameters. All security is delegated to individual module implementations.

**Impact:**  
1. Each module must implement comprehensive security checks
2. No shared security infrastructure across modules
3. A vulnerability in one module's validation could be catastrophic
4. Module developers may not understand the security model

**Recommendation:**  
1. Document the security requirements for modules extensively
2. Provide a base module contract with built-in security patterns
3. Consider requiring modules to implement a standard interface with authentication
4. Add optional protocol-level validation hooks (e.g., message size limits, rate limiting)

---

## Low: Centralization Risks From Unchecked Administrative Powers

**Files:** `Treasury.sol`, `Mailbox.sol`, `EtherBridge.sol`  
**Functions:** Multiple admin-controlled functions

**Root Cause:**  
Administrators have extensive unilateral control:
- Treasury owner can drain all funds via `emergencyWithdraw`
- Mailbox admin can add/remove modules and upgrade the contract
- EtherBridge admin can pause deposits and upgrade the contract

No multi-sig, timelock, or governance mechanism constrains these powers.

**Impact:**  
1. Compromised admin keys lead to total loss of funds
2. Malicious or coerced admin can steal all deposited ETH
3. Users must trust administrators completely
4. No community recourse if admins act maliciously

**Recommendation:**  
1. Require multi-signature approval for critical operations
2. Add timelock delays for sensitive actions like upgrades and withdrawals
3. Implement on-chain governance for parameter changes
4. Consider making emergency functions pausable by a security council

---

## Low: No Slippage Protection or Deadline for Deposits

**File:** `EtherBridge.sol`  
**Function:** `deposit()` (lines 92-119)

**Root Cause:**  
The deposit function has no deadline parameter or slippage protection. A user signs a transaction that can be delayed in the mempool indefinitely and executed under different conditions than expected.

**Impact:**  
1. Transactions can be delayed by validators/miners for MEV extraction
2. Network conditions (gas prices, exchange rates) may change between signing and execution
3. No protection against sandwich attacks or front-running
4. Users expect immediate execution but may get delayed processing

**Recommendation:**  
Add deadline and slippage parameters:
```solidity
function deposit(bytes32 recipient, uint256 amountWei, uint256 deadline) external payable {
    require(block.timestamp <= deadline, "Deposit deadline expired");
    // ... rest of function
}
```

---

## Low: Emergency Withdraw Has No Timelock or Delay

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 63-69)

**Root Cause:**  
The owner can immediately withdraw any amount from the Treasury with no delay or multi-signature requirement:

```solidity
function emergencyWithdraw(uint256 amount) external virtual override onlyOwner nonReentrant {
    require(address(this).balance >= amount, "Insufficient funds");
    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "Failed to send Ether");
    emit EmergencyTreasuryWithdraw(msg.sender, amount);
}
```

**Impact:**  
1. Compromised owner key leads to instant fund theft
2. No time for users or community to react to suspicious withdrawals
3. No multi-party authorization for large withdrawals
4. Emergency function can be misused for rugpull

**Recommendation:**  
1. Implement a timelock delay (e.g., 24-48 hours) between withdrawal initiation and execution
2. Require multi-signature approval for withdrawals
3. Add withdrawal amount limits per time period
4. Emit advance notice events that monitoring systems can catch

---

## Low: sendMessage Cannot Verify Calling Module Identity

**File:** `Mailbox.sol`  
**Function:** `sendMessage()` (lines 225-247)

**Root Cause:**  
The function uses `onlyModule` modifier to verify the caller has `MODULE_ROLE`, but doesn't validate that the calling module's identity matches what should be sent in the message. The `receiver_` parameter is provided by the caller without verification.

**Impact:**  
1. One module could potentially impersonate another by claiming to send to a different receiver
2. No cryptographic binding between caller identity and message content
3. Message authenticity relies on module cooperation rather than protocol enforcement
4. Eclipse-side recipient has no way to verify message origin through the protocol

**Recommendation:**  
1. Derive the sender identity from `msg.sender` rather than trusting parameters
2. Include the sender module's ID in the emitted event and message data
3. Consider requiring modules to sign messages for end-to-end authentication

---

## Informational: Unused Parameters in sendMessage Interface

**File:** `Mailbox.sol`  
**Function:** `sendMessage()` (line 225)

**Root Cause:**  
The first parameter (`chainId_`) and fourth parameter (`data_`) are declared but never used in the function body:

```solidity
function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
```

**Impact:**  
1. Confusing interface that doesn't match documentation
2. Callers may expect these parameters to be validated or used
3. Gas wasted passing unused data
4. Interface doesn't match the actual behavior

**Recommendation:**  
1. Remove unused parameters from the interface if not needed
2. If they're required by the IMailbox interface, add validation or document why they're unused
3. Consider using the `chainId_` for cross-chain validation
4. Use `data_` for future extensibility or remove it

---

## Informational: addModule and removeModule Don't Emit Events

**File:** `Mailbox.sol`  
**Functions:** `addModule()` (lines 151-164), `removeModule()` (lines 167-184)

**Root Cause:**  
These critical state-changing functions modify `modulesById` and grant/revoke `MODULE_ROLE` but don't emit events for off-chain monitoring.

**Impact:**  
1. No way to track module changes through event logs
2. Monitoring systems can't detect unauthorized module additions
3. Difficult to audit module lifecycle
4. Off-chain indexers can't maintain accurate module state

**Recommendation:**  
Add events:
```solidity
event ModuleAdded(bytes32 indexed moduleId, address indexed moduleAddress);
event ModuleRemoved(bytes32 indexed moduleId, address indexed moduleAddress);
```

---

## Informational: No Maximum Deposit Limit

**File:** `EtherBridge.sol`  
**Function:** `deposit()` (lines 92-119)

**Root Cause:**  
The contract enforces a minimum deposit (`MIN_DEPOSIT`) but no maximum limit. Users can deposit arbitrarily large amounts in a single transaction.

**Impact:**  
1. Single large deposit could strain Treasury capacity
2. Large deposits create MEV opportunities
3. No circuit breaker for unusual activity
4. Potential for flash loan attacks or manipulation

**Recommendation:**  
1. Consider adding a per-transaction maximum deposit limit
2. Implement rate limiting (e.g., maximum volume per time period)
3. Add circuit breakers that pause deposits if unusual patterns detected
4. Document expected deposit ranges for risk management

---

## Informational: receiveMessage Uses Unlimited Gas Forwarding

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 215)

**Root Cause:**  
The low-level call forwards all remaining gas to the module:

```solidity
(bool success,) = module.call(message_);
```

**Impact:**  
1. Malicious module can consume all available gas
2. Gas griefing attacks possible where module wastes gas without useful work
3. No protection for relayer against expensive module operations
4. Unpredictable gas costs for relayer

**Recommendation:**  
1. Add a gas limit parameter or constant for module calls
2. Charge modules a gas fee or require gas payment
3. Implement gas metering to detect abusive modules
4. Document gas expectations for module developers

---

## Informational: No Module Authorization Per Receiver

**File:** `Mailbox.sol`  
**Function:** `sendMessage()` (lines 225-247)

**Root Cause:**  
Any module with `MODULE_ROLE` can send messages to any `receiver_` on Eclipse. There's no restriction on which modules can communicate with which receivers.

**Impact:**  
1. No capability-based security model
2. Can't restrict a module to only communicate with specific Eclipse contracts
3. Compromised module has full sending privileges
4. No principle of least privilege enforcement

**Recommendation:**  
1. Implement per-module receiver allowlists
2. Require modules to register authorized receivers during setup
3. Add admin function to grant module-receiver pairs
4. Consider capability tokens for more granular access control

---

## Summary Statistics

- **Critical:** 1
- **High:** 4  
- **Medium:** 5
- **Low:** 5
- **Informational:** 5

**Total Findings:** 20

The most critical issues are the predictable nonce generation and lack of withdrawal mechanism, which pose existential risks to the protocol. The multiple high-severity findings around access control and validation gaps require immediate attention before production deployment.
