# Security Audit Report

## Critical: Arbitrary Call Vulnerability in Mailbox.receiveMessage

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (lines 187-222)

**Root Cause:**  
The `receiveMessage` function performs an arbitrary call to a module contract using untrusted calldata provided by the trusted relayer:

```solidity
address module = $.modulesById[bytes32(sender_)];
require(module != address(0), "Module does not exist.");
(bool success,) = module.call(message_);
require(success, "External call to module failed.");
```

The `message_` parameter contains arbitrary calldata that is executed directly on the target module. This gives the trusted relayer complete control to call any function on any registered module with any parameters, including privileged functions.

**Impact:**  
A compromised or malicious trusted relayer can:
- Execute arbitrary functions on all registered modules
- Drain funds from modules that hold assets
- Change critical state variables
- Bypass access controls on module functions
- Completely compromise the cross-chain messaging system

**Recommendation:**  
1. Implement a whitelist of allowed function selectors per module
2. Validate the function signature against allowed operations
3. Consider using a more structured message format with explicit function routing
4. Add additional signature verification beyond just the trusted relayer role

---

## Critical: Weak Randomness in Nonce Generation

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce` (lines 257-264)

**Root Cause:**  
The nonce generation uses predictable and miner-manipulable block properties:

```solidity
$.lastNonce = uint256(
    keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
);
return uint64($.lastNonce);
```

All components are either known or manipulable:
- `$.lastNonce`: Observable on-chain
- `blockhash(block.number - 1)`: Returns 0 for blocks older than 256 blocks, and is predictable
- `block.timestamp`: Manipulable by miners within ~15 seconds
- `block.coinbase`: Known public information

**Impact:**  
1. **Nonce Prediction:** Attackers (especially miners) can predict future nonces and front-run or prepare attacks
2. **Nonce Collision DoS:** In `sendMessage`, if a predicted nonce already exists, the transaction reverts with "Nonce collision", causing denial of service for legitimate message sending
3. **Replay Preparation:** Attackers can calculate nonces in advance and prepare replay attacks

**Recommendation:**  
1. Use Chainlink VRF or similar oracle for true randomness
2. Include `msg.sender` and `tx.origin` in the entropy mix
3. Use a counter-based nonce system instead of random nonces (more predictable but safer)
4. Add user-provided entropy to the nonce generation

---

## High: Unsafe bytes to bytes32 Conversion

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (line 213)

**Root Cause:**  
The function converts `bytes memory sender_` to `bytes32` without proper length validation:

```solidity
address module = $.modulesById[bytes32(sender_)];
```

The `sender_` parameter is only validated to be non-empty (`bytesInitialized` modifier), but not for its length. When converting `bytes` to `bytes32`:
- If `sender_` is longer than 32 bytes, only the first 32 bytes are used
- If shorter, it may be padded, potentially creating collisions

**Impact:**  
1. **Module ID Collision:** Different `sender_` values could map to the same bytes32, allowing unauthorized access to modules
2. **Bypass Security:** An attacker could craft a sender value that collides with a legitimate module ID
3. **Unpredictable Behavior:** The conversion behavior may vary, leading to unexpected module resolution

**Recommendation:**  
1. Add `bytesLengthEq32(sender_)` modifier to enforce exact 32-byte length
2. Use explicit conversion: `abi.decode(sender_, (bytes32))`
3. Document the expected format of `sender_` parameter
4. Validate sender format in the trusted relayer before submission

---

## High: Centralization Risk from Single Trusted Relayer

**File:** `Mailbox.sol`  
**Functions:** `receiveMessage`, initialization

**Root Cause:**  
The entire cross-chain messaging system depends on a single trusted relayer address. Only this address can call `receiveMessage` to deliver messages from Eclipse to Ethereum:

```solidity
modifier onlyTrustedRelayer() {
    require(hasRole(TRUSTED_RELAYER_ROLE, msg.sender), "Only the trusted relayer can call this method.");
    _;
}
```

**Impact:**  
1. **Single Point of Failure:** If the relayer's private key is lost, all cross-chain message delivery stops permanently
2. **Compromise Risk:** If the relayer is compromised, the attacker gains complete control over message delivery
3. **Censorship:** The relayer can selectively censor messages
4. **No Redundancy:** System cannot operate if relayer is offline

**Recommendation:**  
1. Implement multi-signature or threshold signature scheme for relayer operations
2. Allow multiple relayer addresses with consensus mechanism
3. Add emergency governance procedures to rotate compromised relayers
4. Consider decentralized relayer network with stake-based incentives

---

## High: Ether Stuck in Mailbox Contract

**File:** `Mailbox.sol`  
**Functions:** `sendMessage` (line 225), `receiveMessage` (line 194)

**Root Cause:**  
Both `sendMessage` and `receiveMessage` are marked `payable` but neither function uses `msg.value`:

```solidity
function sendMessage(...) external payable virtual override onlyModule nonReentrant returns (bool)
function receiveMessage(...) external payable virtual override onlyTrustedRelayer ... returns (bool)
```

No ether is forwarded to module calls, and there's no withdrawal mechanism in the Mailbox contract.

**Impact:**  
1. **Permanent Loss:** Any ether sent to these functions is permanently stuck in the Mailbox contract
2. **User Error:** Users may accidentally send ether expecting it to be bridged
3. **Protocol Error:** Integration errors could result in locked funds
4. **No Recovery:** Without a withdrawal function, stuck ether cannot be recovered

**Recommendation:**  
1. Remove `payable` modifier from both functions if ether is not needed
2. If ether should be forwarded, explicitly forward it in the module call
3. Add a rescue function for accidentally sent ether (restricted to admin)
4. Add validation: `require(msg.value == 0, "Ether not accepted")`

---

## High: Module Role Revocation Flaw

**File:** `Mailbox.sol`  
**Function:** `removeModule` (lines 167-184)

**Root Cause:**  
When removing a module, the function revokes the `MODULE_ROLE` from the address without checking if other module IDs still map to the same address:

```solidity
delete $.modulesById[moduleId];
_revokeRole(MODULE_ROLE, module);
```

If multiple module IDs point to the same contract address (which `addModule` and `initialize` allow), removing one module ID will revoke the role for all of them.

**Impact:**  
1. **Service Disruption:** Removing one module ID breaks all module IDs that share the same address
2. **Unintended Access Revocation:** Legitimate module mappings become non-functional
3. **Inconsistent State:** `modulesById` mapping shows the module exists, but it lacks the role to function

**Recommendation:**  
1. Before revoking role, iterate through all module IDs to check if any other ID maps to the same address
2. Only revoke role if this is the last module ID using that address
3. Alternatively, prevent multiple module IDs from mapping to the same address
4. Emit events for both mapping deletion and role revocation

---

## High: Treasury Paused State Breaks EtherBridge Deposits

**File:** `EtherBridge.sol` (deposit function), `Treasury.sol` (receive function)  
**Lines:** EtherBridge.sol:115, Treasury.sol:83

**Root Cause:**  
The `EtherBridge.deposit` function sends ether to the Treasury contract:

```solidity
(success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");
require(success, "Transfer failed");
```

However, Treasury's `receive()` function has the `whenNotPaused` modifier:

```solidity
receive() external payable virtual whenNotPaused {
    ...
}
```

If the Treasury owner pauses the Treasury (line 71), all EtherBridge deposits will fail even though the EtherBridge itself is not paused.

**Impact:**  
1. **Bridge Inoperability:** Users cannot deposit through the bridge when Treasury is paused
2. **Inconsistent State:** Bridge appears operational but all deposits fail
3. **User Confusion:** Error message "Transfer failed" doesn't indicate Treasury is paused
4. **Emergency Response Conflict:** Pausing Treasury for emergency also stops all deposits

**Recommendation:**  
1. Coordinate pause states: pause both contracts together
2. Add specific error message when Treasury transfer fails: check if Treasury is paused
3. Allow Treasury to accept deposits even when paused (only restrict withdrawals)
4. Implement a withdrawal queue instead of full pause

---

## Medium: Unbounded Storage Growth in Nonce Mappings

**File:** `Mailbox.sol`  
**Storage:** `receiveNonces` and `sendNonces` mappings (lines 57-58)

**Root Cause:**  
The nonce tracking mappings only set values to `true` and never delete them:

```solidity
mapping(uint64 => bool) receiveNonces;
mapping(uint64 => bool) sendNonces;

// In receiveMessage:
$.receiveNonces[secParam.nonce] = true;

// In sendMessage:
$.sendNonces[outboundNonce] = true;
```

Every message sent or received permanently consumes one storage slot.

**Impact:**  
1. **Increasing Gas Costs:** As mappings grow, overall contract state grows
2. **Potential DoS:** After 2^64 messages, the entire uint64 space is exhausted
3. **Economic Attack:** Attacker could send many cheap messages to inflate storage costs
4. **Long-term Sustainability:** High-volume usage becomes economically unfeasible

**Recommendation:**  
1. Use a time-based nonce window: only track nonces from recent blocks
2. Implement nonce ranges with bitmap compression
3. Use nonce expiry: allow reuse of nonces after a timeout period
4. Consider a rolling window of valid nonces (e.g., last 10,000)
5. Add periodic cleanup mechanism for old nonces

---

## Medium: Missing Sender Length Validation

**File:** `Mailbox.sol`  
**Function:** `receiveMessage` (line 200)

**Root Cause:**  
The `sender_` parameter is validated with `bytesInitialized(sender_)` which only checks that length > 0:

```solidity
modifier bytesInitialized(bytes memory _data) {
    require(_data.length > 0, "CommonUtility: empty bytes");
    _;
}
```

However, `sender_` is later converted to `bytes32` (line 213), which expects exactly 32 bytes. No length validation ensures this.

**Impact:**  
1. **Unexpected Behavior:** Senders longer or shorter than 32 bytes may not work as intended
2. **Integration Issues:** Off-chain systems may send incorrectly sized sender IDs
3. **Gas Waste:** Invalid messages consume gas before failing at module lookup
4. **Mapping Collisions:** Improperly sized senders could collide after conversion

**Recommendation:**  
1. Add `bytesLengthEq32(sender_)` modifier to `receiveMessage`
2. Validate sender format matches expected Eclipse address encoding
3. Document the exact format requirements for sender parameter
4. Add explicit error message for invalid sender length

---

## Medium: No Events for Critical Module Management Operations

**File:** `Mailbox.sol`  
**Functions:** `addModule` (lines 151-164), `removeModule` (lines 167-184)

**Root Cause:**  
Neither `addModule` nor `removeModule` emit events when modifying the critical `modulesById` mapping:

```solidity
function addModule(bytes32 moduleId, address module) external ... {
    $.modulesById[moduleId] = module;
    _grantRole(MODULE_ROLE, module);
    // No event emission
}

function removeModule(bytes32 moduleId, address module) external ... {
    delete $.modulesById[moduleId];
    _revokeRole(MODULE_ROLE, module);
    // No event emission
}
```

**Impact:**  
1. **Lack of Transparency:** Off-chain systems cannot track module changes
2. **Audit Trail Missing:** No on-chain record of who added/removed modules when
3. **Security Monitoring:** Cannot detect unauthorized module changes in real-time
4. **Integration Issues:** DApps cannot react to module registry changes

**Recommendation:**  
1. Add `ModuleAdded(bytes32 indexed moduleId, address indexed module)` event
2. Add `ModuleRemoved(bytes32 indexed moduleId, address indexed module)` event
3. Emit events in both functions
4. Consider emitting admin address for additional accountability

---

## Medium: Redundant Module Role Grants

**File:** `Mailbox.sol`  
**Function:** `addModule` (lines 151-164)

**Root Cause:**  
The `addModule` function grants `MODULE_ROLE` to an address without checking if it already has the role:

```solidity
$.modulesById[moduleId] = module;
_grantRole(MODULE_ROLE, module);
```

If the same address is registered under multiple module IDs (allowed by the system), it receives `_grantRole` multiple times.

**Impact:**  
1. **Gas Waste:** Redundant role grants consume unnecessary gas
2. **Event Spam:** Multiple `RoleGranted` events for the same address
3. **Confusion:** Off-chain monitors see duplicate role grants
4. **State Inconsistency:** Role management state doesn't reflect actual unique roles

**Recommendation:**  
1. Check if address already has `MODULE_ROLE` before granting:
   ```solidity
   if (!hasRole(MODULE_ROLE, module)) {
       _grantRole(MODULE_ROLE, module);
   }
   ```
2. Document that multiple module IDs can share an address
3. Track reference count for addresses with multiple IDs

---

## Low: Blockhash Returns Zero for Old Blocks

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce` (line 261)

**Root Cause:**  
The function uses `blockhash(block.number - 1)`:

```solidity
keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
```

The `blockhash()` function returns `0` for block numbers more than 256 blocks in the past. If the contract is not called for 256 blocks, the blockhash becomes predictable.

**Impact:**  
1. **Reduced Entropy:** If blockhash is 0, nonce depends only on timestamp, coinbase, and lastNonce
2. **Predictability Increase:** Makes nonce generation even more predictable during low activity
3. **Edge Case Issues:** Unusual network conditions could trigger this

**Recommendation:**  
1. Add check: `require(blockhash(block.number - 1) != 0, "Blockhash unavailable")`
2. Use `block.prevrandao` (available in Solidity 0.8.18+) instead of blockhash
3. Consider using Chainlink VRF for true randomness
4. Fall back to alternative entropy source if blockhash is 0

---

## Low: Treasury Owner as Contract Risk

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 63-69)

**Root Cause:**  
The `emergencyWithdraw` function sends ether to `msg.sender` using a call:

```solidity
function emergencyWithdraw(uint256 amount) external virtual override onlyOwner nonReentrant {
    require(address(this).balance >= amount, "Insufficient funds");
    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "Failed to send Ether");
    emit EmergencyTreasuryWithdraw(msg.sender, amount);
}
```

If the owner is a contract (which is allowed), and that contract has a malicious or gas-intensive `receive`/`fallback` function, the withdrawal could fail or behave unexpectedly.

**Impact:**  
1. **Withdrawal Failure:** Owner contract could reject the transfer
2. **Gas Griefing:** Owner contract could consume all gas
3. **Ownership Transfer Risk:** If ownership is transferred to a problematic contract, funds become locked

**Recommendation:**  
1. Document that owner should be an EOA or a simple multisig
2. Add a pull-based withdrawal pattern as alternative
3. Consider using `transfer()` with a gas limit
4. Implement a two-step withdrawal: mark for withdrawal, then claim

---

## Low: Missing Zero Amount Check in EmergencyWithdraw

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 63-69)

**Root Cause:**  
The function doesn't validate that `amount > 0`:

```solidity
function emergencyWithdraw(uint256 amount) external virtual override onlyOwner nonReentrant {
    require(address(this).balance >= amount, "Insufficient funds");
    ...
}
```

Zero amount withdrawals are allowed, wasting gas and emitting useless events.

**Impact:**  
1. **Gas Waste:** Zero-amount withdrawals consume gas unnecessarily
2. **Event Spam:** Emits withdrawal events with zero value
3. **Log Pollution:** Off-chain systems must filter out meaningless events

**Recommendation:**  
Add validation at the beginning of the function:
```solidity
require(amount > 0, "Amount must be greater than zero");
```

---

## Low: Precision Loss Risk in Deposit Conversion

**File:** `EtherBridge.sol`  
**Function:** `deposit` (line 105)

**Root Cause:**  
The deposit amount is converted from wei to gwei:

```solidity
uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
```

While the `validDepositAmount` modifier ensures `msg.value % WEI_PER_LAMPORT == 0`, there's no guarantee that `amountWei` parameter matches this if called incorrectly.

**Impact:**  
1. **Silent Precision Loss:** If validation fails, users could lose fractional amounts
2. **Inconsistent State:** Message reports different amount than actually locked
3. **User Confusion:** Expected and actual amounts may differ

**Recommendation:**  
1. Add assertion: `assert(amountWei % WEI_PER_LAMPORT == 0)` after modifiers run
2. Revert with clear message if conversion would lose precision
3. Document the gwei requirement prominently in NatSpec

---

## Informational: Unnecessary Virtual Keywords

**File:** Multiple files  
**Functions:** Various

**Root Cause:**  
Several functions are marked `virtual` without clear inheritance design:
- `Treasury.emergencyWithdraw` (line 63)
- `Treasury.receive` (line 83)  
- `EtherBridge.deposit` (line 92)
- `Mailbox.receiveMessage` (line 195)
- `Mailbox.sendMessage` (line 225)

**Impact:**  
1. **Future Override Risk:** Functions can be overridden in derived contracts, potentially introducing vulnerabilities
2. **Code Clarity:** Unclear if overriding is intended behavior
3. **Upgrade Confusion:** Virtual functions in upgradeable contracts need careful handling

**Recommendation:**  
1. Remove `virtual` keyword if no inheritance is planned
2. If intended for future extension, document the override expectations
3. Add security notes about what overrides must preserve (invariants, security checks)

---

## Informational: Unused Function Parameters

**File:** `Mailbox.sol`  
**Function:** `sendMessage` (line 225)

**Root Cause:**  
The `sendMessage` function has unnamed parameters that are not used:

```solidity
function sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)
```

The first parameter (chainId) and fourth parameter (data) are not used in the implementation.

**Impact:**  
1. **Interface Compliance:** Required by IMailbox interface
2. **Gas Waste:** Unused calldata still costs gas to pass
3. **Code Clarity:** Unclear why parameters exist

**Recommendation:**  
1. Document in NatSpec that these parameters are for interface compliance
2. Consider using the chainId parameter for validation
3. If truly unused, use underscore prefix: `bytes memory _chainId`

---

## Informational: Missing Input Validation for Recipient

**File:** `EtherBridge.sol`  
**Function:** `deposit` (lines 92-119)

**Root Cause:**  
The `recipient` parameter is only validated to be non-zero using `bytes32Initialized(recipient)` modifier. There's no validation that it represents a valid Solana address format.

**Impact:**  
1. **User Error:** Users could send to invalid Solana addresses
2. **Permanent Loss:** Funds sent to invalid addresses may be unrecoverable
3. **No Early Validation:** Error only discovered on Eclipse side

**Recommendation:**  
1. Add validation for Solana address format if deterministic
2. Document the expected recipient format clearly
3. Provide off-chain tools to validate addresses before submission
4. Consider adding a checksum or validation step

---

## Informational: Initialize Functions Are Public

**File:** All contracts  
**Functions:** `initialize`

**Root Cause:**  
All `initialize` functions are marked `public` instead of `external`:

```solidity
function initialize(...) public ... initializer { }
```

Since they're called through proxies and only once, `external` would be more gas-efficient.

**Impact:**  
1. **Minor Gas Overhead:** `public` functions cost slightly more gas than `external`
2. **Code Convention:** OpenZeppelin patterns typically use `external` for initializers
3. **Best Practice:** External better represents "called from outside only"

**Recommendation:**  
Change `public` to `external` for all initialize functions to save gas and follow conventions.

---

## Informational: Missing NatSpec Documentation

**File:** Multiple files  
**Functions:** Various internal functions

**Root Cause:**  
Several internal/private functions lack NatSpec documentation:
- `_getStorageV1()` functions
- `_authorizeUpgrade()` functions
- Helper functions in CommonContainer

**Impact:**  
1. **Maintainability:** Harder for developers to understand code
2. **Audit Complexity:** Auditors must infer intent from implementation
3. **Integration Issues:** Users don't understand contract behavior

**Recommendation:**  
Add comprehensive NatSpec documentation including:
```solidity
/// @dev Retrieves the storage struct using ERC-7201 namespaced storage
/// @return $ The storage struct for this contract version
```

