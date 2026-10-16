# Smart Contract Security Audit Report

## Critical: Predictable Nonce Generation Enables Front-Running and Denial of Service

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (lines 257-264)

**Root Cause:**  
The nonce generation mechanism uses predictable on-chain values including `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase`, and the stored `lastNonce` value. All of these inputs are either publicly visible in contract storage or deterministically available to any observer before transaction execution.

```solidity
$.lastNonce = uint256(
    keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))
);
```

**Impact:**  
- An attacker can predict future nonces by simulating the `generateRandomNonce()` function off-chain
- Predicted nonces can be used to front-run legitimate `sendMessage()` calls at line 236-240
- Since nonce collision causes a revert (line 238), attackers can DOS the message sending functionality
- The nonce collision check permanently prevents message transmission with that nonce, causing permanent DOS until a different nonce is generated

**Recommendation:**  
Use a monotonically increasing counter instead of pseudo-random generation, or incorporate user-supplied entropy. Example:
```solidity
function generateSequentialNonce() internal returns (uint64) {
    StorageV1 storage $ = _getStorageV1();
    $.lastNonce += 1;
    return uint64($.lastNonce);
}
```

## Critical: ETH Permanently Locked in Mailbox Contract

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 187-222)

**Root Cause:**  
The `receiveMessage()` function is marked `payable` (line 194) but does not forward `msg.value` to the module being called (line 215), nor does the Mailbox contract have any withdrawal mechanism to recover sent ETH.

```solidity
function receiveMessage(...) external payable virtual override ... {
    ...
    (bool success,) = module.call(message_);  // No {value: msg.value}
    ...
}
```

**Impact:**  
- Any ETH sent with `receiveMessage()` calls becomes permanently locked in the Mailbox contract
- No `receive()` or `fallback()` function exists to reject plain ETH transfers
- No administrative function exists to recover accidentally sent funds
- Loss of user funds

**Recommendation:**  
Either remove the `payable` modifier if ETH transfers are not intended, or forward the value to the module and add a recovery function:
```solidity
(bool success,) = module.call{value: msg.value}(message_);
```

## Critical: Unbounded Gas Consumption in External Module Call

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 215)

**Root Cause:**  
The external call to the module does not specify a gas limit, forwarding all available gas to an untrusted contract.

```solidity
(bool success,) = module.call(message_);
```

**Impact:**  
- A malicious or buggy module can consume all available gas, causing the entire `receiveMessage()` transaction to fail
- Griefing attack vector where module operators can DOS message reception
- Unpredictable gas costs make it difficult to estimate transaction costs for relayers
- All gas could be consumed even if module intentionally runs expensive operations

**Recommendation:**  
Implement a reasonable gas limit for module calls:
```solidity
(bool success,) = module.call{gas: 100000}(message_);
```

## High: Missing Input Validation for Sender Parameter

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 213)

**Root Cause:**  
The `sender_` parameter is only validated by `bytesInitialized` modifier (checking `length > 0`), but not validated to be exactly 32 bytes before being cast to `bytes32`. The `eclipseChainId_` parameter has `bytesLengthEq32` validation (line 198), but `sender_` does not.

```solidity
address module = $.modulesById[bytes32(sender_)];  // Line 213
```

**Impact:**  
- If `sender_` is shorter than 32 bytes, it will be right-padded with zeros when cast to `bytes32`
- If `sender_` is longer than 32 bytes, only the first 32 bytes are used
- This creates unexpected behavior where invalid sender formats may incorrectly match (or fail to match) module IDs
- Potential for message routing failures or bypassing sender validation

**Recommendation:**  
Add length validation consistent with `eclipseChainId_`:
```solidity
function receiveMessage(
    bytes memory eclipseChainId_,
    bytes memory sender_,
    ...
)
    external
    ...
    bytesLengthEq32(sender_)  // Add this modifier
```

## High: Missing Withdrawal Functionality in Bridge System

**File:** `smart-contracts/src/v1/EtherBridge.sol`

**Root Cause:**  
The EtherBridge contract only implements `deposit()` functionality (lines 92-119) but has no corresponding withdrawal function to return ETH from Eclipse to Ethereum. The EtherBridge is registered as a MODULE in Mailbox but has no function to receive and process withdrawal messages.

**Impact:**  
- Users can deposit ETH to Eclipse but have no on-chain mechanism to withdraw
- The bridge is functionally one-way unless withdrawal is handled by an external system not in scope
- Funds may be trapped if the withdrawal mechanism is incomplete
- Critical functionality gap in the bridge design

**Recommendation:**  
Implement a withdrawal function that can be called by the Mailbox when receiving withdrawal messages from Eclipse:
```solidity
function processWithdrawal(bytes calldata message) external {
    require(msg.sender == address(mailboxProxy), "Only mailbox");
    WithdrawalMessage memory withdrawal = abi.decode(message, (WithdrawalMessage));
    treasuryProxy.emergencyWithdraw(withdrawal.amount);
    // Transfer to recipient
}
```

## High: Cross-Contract Pause Dependency Creates Unexpected Failures

**File:** `smart-contracts/src/v1/EtherBridge.sol` and `smart-contracts/src/v1/Treasury.sol`  
**Functions:** `EtherBridge.deposit()` (line 115) and `Treasury.receive()` (line 83)

**Root Cause:**  
The EtherBridge sends ETH to Treasury via a low-level call (line 115-116), which triggers Treasury's `receive()` function. Treasury's `receive()` has a `whenNotPaused` modifier (line 83), but EtherBridge is unaware of Treasury's pause state.

```solidity
// EtherBridge.sol
(success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");

// Treasury.sol
receive() external payable virtual whenNotPaused {
    ...
}
```

**Impact:**  
- If Treasury is paused, all EtherBridge deposits fail even when EtherBridge is not paused
- Users attempting deposits while Treasury is paused will have transactions revert with "Pausable: paused"
- The EtherBridge pause mechanism does not provide full control over deposit functionality
- Unclear operational semantics - which contract should control the pause state?

**Recommendation:**  
Either:
1. Synchronize pause states between contracts, or
2. Check Treasury pause state before attempting deposit:
```solidity
require(!treasuryProxy.paused(), "Treasury is paused");
```

## High: Nonce Mappings Grow Without Bounds

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Storage:** `receiveNonces` and `sendNonces` mappings (lines 57-58)

**Root Cause:**  
Both `receiveNonces` and `sendNonces` mappings are written to on every message sent/received (lines 210, 240) but never cleaned up. Every nonce value is permanently stored in the mapping as `true`.

```solidity
mapping(uint64 => bool) receiveNonces;
mapping(uint64 => bool) sendNonces;
```

**Impact:**  
- Unbounded storage growth as more messages are processed
- Increased gas costs over time as storage becomes more populated
- Potential for storage exhaustion in extreme long-term scenarios
- No mechanism to archive or clean old nonces

**Recommendation:**  
Consider implementing a nonce window or cleanup mechanism:
```solidity
uint64 public minValidNonce;

function updateMinNonce(uint64 newMin) external onlyAuthority {
    require(newMin > minValidNonce, "Can only increase");
    minValidNonce = newMin;
}

// In receiveMessage:
require(secParam.nonce >= minValidNonce, "Nonce too old");
```

## Medium: Module Call Failure Causes Permanent Message Loss

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (lines 215-216)

**Root Cause:**  
When the external call to a module fails, the entire `receiveMessage()` transaction reverts (line 216). However, the nonce has already been marked as used (line 210), preventing retry with the same message.

```solidity
$.receiveNonces[secParam.nonce] = true;  // Line 210
...
(bool success,) = module.call(message_);
require(success, "External call to module failed.");  // Line 216
```

**Impact:**  
- If a module is temporarily unavailable, buggy, or reverts, the message is permanently lost
- The nonce is consumed, so the message cannot be retried
- DOS vector where a malicious module can permanently block message reception
- No recovery mechanism for failed message delivery

**Recommendation:**  
Consider a two-phase delivery pattern or allow nonce reuse on failure:
```solidity
(bool success,) = module.call(message_);
if (!success) {
    delete $.receiveNonces[secParam.nonce];  // Allow retry
    emit MessageFailed(sender_, message_);
    return false;
}
```

## Medium: Centralized Trust in Single Relayer Creates Single Point of Failure

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()` (line 197)

**Root Cause:**  
Only addresses with `TRUSTED_RELAYER_ROLE` can call `receiveMessage()`. This role is granted to a single address during initialization (line 135), creating a centralized dependency.

```solidity
modifier onlyTrustedRelayer() {
    require(hasRole(TRUSTED_RELAYER_ROLE, msg.sender), "Only the trusted relayer can call this method.");
    _;
}
```

**Impact:**  
- If the relayer's private key is lost, no messages can be received from Eclipse
- If the relayer is compromised, arbitrary malicious messages can be injected
- Single point of failure for the entire cross-chain messaging system
- No redundancy or fallback mechanism

**Recommendation:**  
Support multiple relayers with quorum requirements:
```solidity
mapping(bytes32 => mapping(address => bool)) messageApprovals;
uint256 public requiredRelayers = 2;

function approveMessage(bytes32 msgHash) external onlyTrustedRelayer {
    messageApprovals[msgHash][msg.sender] = true;
}

function receiveMessage(...) external {
    bytes32 msgHash = keccak256(abi.encode(chainId_, sender_, message_, data_));
    uint256 approvals = countApprovals(msgHash);
    require(approvals >= requiredRelayers, "Insufficient approvals");
    ...
}
```

## Medium: No Atomic Module Update Mechanism

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Functions:** `addModule()` and `removeModule()` (lines 151-184)

**Root Cause:**  
To update a module address for an existing module ID, an admin must call `removeModule()` then `addModule()` in separate transactions. There is no atomic update function.

```solidity
function addModule(bytes32 moduleId, address module) external ... {
    if ($.modulesById[moduleId] != address(0)) {
        revert("Module address for module id already set");
    }
    ...
}
```

**Impact:**  
- During the gap between `removeModule()` and `addModule()` transactions, the module is unavailable
- Messages sent to that module ID during the gap will fail (line 214 check)
- Race condition if multiple admins attempt updates simultaneously
- No guarantee of atomic state transition

**Recommendation:**  
Add an atomic update function:
```solidity
function updateModule(bytes32 moduleId, address oldModule, address newModule) 
    external 
    bytes32Initialized(moduleId)
    addressInitialized(newModule)
    onlyAuthority 
{
    require($.modulesById[moduleId] == oldModule, "Module mismatch");
    _revokeRole(MODULE_ROLE, oldModule);
    _grantRole(MODULE_ROLE, newModule);
    $.modulesById[moduleId] = newModule;
}
```

## Medium: Nonce Collision Check Inefficiency

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage()` (lines 237-240)

**Root Cause:**  
When a nonce collision is detected, the function reverts, forcing the entire transaction to be retried with a new nonce generation. This wastes gas and creates unpredictable behavior.

```solidity
uint64 outboundNonce = generateRandomNonce();
if ($.sendNonces[outboundNonce] == true) {
    revert("Nonce collision");
}
```

**Impact:**  
- Gas inefficiency when collisions occur (though rare with 64-bit space)
- User transactions fail unpredictably
- No automatic retry mechanism
- Poor user experience

**Recommendation:**  
Implement a retry loop with a maximum iteration count:
```solidity
uint64 outboundNonce;
for (uint i = 0; i < 3; i++) {
    outboundNonce = generateRandomNonce();
    if (!$.sendNonces[outboundNonce]) break;
    if (i == 2) revert("Nonce collision after retries");
}
```

## Low: Treasury Owner Can Send ETH Without Clear Purpose

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `receive()` (line 83-87)

**Root Cause:**  
The `receive()` function allows both the `etherBridgeAddress` and the `owner()` to send ETH to the Treasury. The purpose of allowing the owner to deposit is unclear from the code and comments.

```solidity
require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), "Unauthorized source");
```

**Impact:**  
- Unclear accounting - deposits from owner vs bridge are indistinguishable in events
- Potential for confusion about Treasury balance sources
- May enable unintended behaviors if owner sends ETH accidentally
- Violates principle of least privilege

**Recommendation:**  
If owner deposits are intentional, add a separate function with explicit purpose:
```solidity
function ownerDeposit() external payable onlyOwner whenNotPaused {
    emit OwnerDeposit(msg.sender, msg.value);
}

receive() external payable virtual whenNotPaused {
    require(msg.sender == $.etherBridgeAddress, "Only bridge");
    emit TreasuryDeposit(msg.sender, msg.value);
}
```

## Low: Empty Parameters Passed to Mailbox Send Message

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()` (line 111)

**Root Cause:**  
The call to `mailbox.sendMessage()` passes empty bytes for the first parameter (chainId) and fourth parameter (data/security param).

```solidity
bool success = $.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "");
```

**Impact:**  
- The `sendMessage()` function expects chain ID and security parameters
- Empty chain ID may cause issues on the receiving end
- Missing security parameters (nonce is generated internally, so empty param is ignored)
- Inconsistent with the interface expectations

**Recommendation:**  
Pass the proper Eclipse chain ID:
```solidity
bytes memory eclipseChainId = // retrieve from storage or parameter
bool success = $.mailboxProxy.sendMessage(eclipseChainId, $.etherBridgeId, encodedMessage, "");
```

## Low: Missing Events for Critical Module Management Operations

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Functions:** `addModule()` and `removeModule()` (lines 151-184)

**Root Cause:**  
The `addModule()` and `removeModule()` functions modify critical state (module registry) but do not emit events, making off-chain monitoring difficult.

**Impact:**  
- Difficult to track module changes in off-chain systems
- No audit trail for module additions/removals
- Harder to detect unauthorized changes
- Poor observability

**Recommendation:**  
Add events:
```solidity
event ModuleAdded(bytes32 indexed moduleId, address indexed module);
event ModuleRemoved(bytes32 indexed moduleId, address indexed module);

function addModule(bytes32 moduleId, address module) external ... {
    ...
    emit ModuleAdded(moduleId, module);
}

function removeModule(bytes32 moduleId, address module) external ... {
    ...
    emit ModuleRemoved(moduleId, module);
}
```

## Informational: Integer Downcasting in Nonce Generation

**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 263)

**Root Cause:**  
The function stores a full `uint256` value in `lastNonce` but returns only the least significant 64 bits as `uint64`. This discards 192 bits of entropy.

```solidity
$.lastNonce = uint256(keccak256(...));
return uint64($.lastNonce);
```

**Impact:**  
- Reduced entropy in nonce values (64 bits instead of 256 bits)
- Still sufficient for nonce uniqueness in realistic scenarios
- Wastes storage by keeping full 256-bit value

**Recommendation:**  
Store as uint64 directly if only 64 bits are needed:
```solidity
$.lastNonce = uint64(uint256(keccak256(...)));
```

## Informational: Potential Re-initialization of Inherited Contracts

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `initialize()` (lines 45-59)

**Root Cause:**  
Both `__Ownable_init(owner_)` (line 51) and `__Ownable2Step_init()` (line 52) are called during initialization. The second call may re-initialize some state already set by the first.

**Impact:**  
- Redundant initialization calls
- Potential for unexpected state if initialization order matters
- Gas inefficiency
- Code clarity issue

**Recommendation:**  
Review OpenZeppelin documentation to determine if both calls are necessary, or use only:
```solidity
__Ownable2Step_init();
_transferOwnership(owner_);
```

## Informational: Use of Magic Numbers

**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Lines:** 27-29

**Root Cause:**  
Constants `MIN_DEPOSIT_LAMPORTS` and `WEI_PER_LAMPORT` are defined but the relationship to Solana's lamport denomination is not documented in comments.

```solidity
uint256 private constant MIN_DEPOSIT_LAMPORTS = 2_000_000;
uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;
```

**Impact:**  
- Reduced code readability
- Difficult to verify correctness of conversion rate
- May cause confusion during audits or maintenance

**Recommendation:**  
Add documentation:
```solidity
// 1 lamport = 1 gwei = 1e9 wei (Solana's smallest unit)
uint256 private constant WEI_PER_LAMPORT = 1_000_000_000;
// Minimum 2M lamports (0.002 SOL equivalent) to prevent dust
uint256 private constant MIN_DEPOSIT_LAMPORTS = 2_000_000;
```

## Informational: Redundant Balance Check in Emergency Withdraw

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()` (line 64)

**Root Cause:**  
The function checks if balance is sufficient before attempting to send, but the low-level `.call` will fail anyway if insufficient funds exist.

```solidity
require(address(this).balance >= amount, "Insufficient funds");
(bool success,) = msg.sender.call{value: amount}("");
```

**Impact:**  
- Minimal - provides clearer error message
- Slight gas overhead for redundant check
- Code clarity vs efficiency tradeoff

**Recommendation:**  
The check is reasonable for better error messages, but could be removed for gas optimization if error clarity is not critical.

## Informational: Floating Pragma vs Locked Version

**File:** All contract files use locked pragma

**Root Cause:**  
All contracts use `pragma solidity 0.8.21;` (locked version), which is good practice.

**Impact:**  
- Positive finding - prevents compilation with untested compiler versions
- Ensures consistent behavior across deployments

**Recommendation:**  
Continue using locked pragma versions for production contracts.

## Informational: Missing NatSpec Documentation

**File:** Multiple contracts

**Root Cause:**  
Several internal functions and modifiers lack complete NatSpec documentation, making code review and maintenance more difficult.

**Impact:**  
- Reduced code readability
- More difficult onboarding for new developers
- Harder to generate documentation

**Recommendation:**  
Add complete NatSpec comments for all public and external functions:
```solidity
/// @notice Generates a sequential nonce for message tracking
/// @dev Uses block properties as entropy source (not cryptographically secure)
/// @return A unique 64-bit nonce value
function generateRandomNonce() internal returns (uint64) {
    ...
}
```
