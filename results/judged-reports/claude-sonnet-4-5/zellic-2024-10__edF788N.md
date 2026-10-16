# Smart Contract Security Audit Report

## Critical: Missing WITHDRAW_AUTHORITY_ROLE in Deployment Script

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run()`  
**Lines:** 43-50

**Root Cause:**  
The deployment script grants the `DEPOSITOR_ROLE` to the CanonicalBridge (line 50) but fails to grant the `WITHDRAW_AUTHORITY_ROLE` to the bridge contract itself. When users call `CanonicalBridge.claimWithdrawal()`, the bridge internally calls `ITreasury(TREASURY).withdrawEth()` (line 234 in CanonicalBridge.sol), which requires the caller to have the `WITHDRAW_AUTHORITY_ROLE`. Without this role, all withdrawal claims will fail.

**Impact:**  
Complete denial of service for the withdrawal functionality. Users will be unable to claim their withdrawals from the bridge, effectively locking all funds in the Treasury that should be withdrawable. This breaks the core functionality of the bridge.

**Recommendation:**  
Add the following line after line 50 in DeployV1.s.sol:
```solidity
_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));
```

Note: The Upgrader0to1.sol contract correctly grants this role at line 130, so only the deployment script is affected.

---

## High: Missing Fee Validation in Treasury Withdrawal

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()`  
**Lines:** 106-128

**Root Cause:**  
The function does not validate that `feeWei <= amountWei` before performing the calculation `amountWei - feeWei` at line 123. While Solidity 0.8.21's automatic overflow protection will cause a revert if `feeWei > amountWei`, there is no explicit validation or informative error message. This differs from the CanonicalBridge which validates this condition at line 76-77.

**Impact:**  
If called directly by an entity with `WITHDRAW_AUTHORITY_ROLE` (not through the bridge), passing `feeWei > amountWei` will cause an uninformative revert. More critically, the insufficient balance check at line 120 only verifies `balance >= amountWei`, not `balance >= amountWei` where the full amount is actually sent (though split between recipient and fee receiver). While the current check is mathematically sufficient when `feeWei <= amountWei`, the lack of explicit fee validation creates a logical gap.

**Recommendation:**  
Add explicit validation at the beginning of the function:
```solidity
if (feeWei > amountWei) revert InvalidFee();
```

---

## High: Withdraw ID Reuse After Message Deletion

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage()`  
**Lines:** 261-262

**Root Cause:**  
When a withdraw message is deleted, both `startTime[messageHash]` and `withdrawMsgIdProcessed[message.withdrawId]` are reset to zero. This allows the same `withdrawId` to be reused in a subsequent authorization with potentially different message parameters (different amount, destination, etc.).

**Impact:**  
An attacker could exploit this by:
1. Getting a malicious withdrawal message authorized with a specific withdrawId
2. Having it detected and deleted by the `WITHDRAW_CANCELLER_ROLE` 
3. Immediately submitting a new authorization with the same withdrawId but different (valid-looking) parameters
4. The check at line 202-204 in `_authorizeWithdraw` would pass since `withdrawMsgIdProcessed[withdrawId]` was reset to 0

This breaks the invariant that each withdrawId should be used exactly once, enabling potential replay attacks or confusion in off-chain tracking systems.

**Recommendation:**  
Do not reset `withdrawMsgIdProcessed` when deleting a message. Modify line 262:
```solidity
// Remove this line:
// withdrawMsgIdProcessed[message.withdrawId] = 0;

// Or use a tombstone value to mark as deleted but prevent reuse:
withdrawMsgIdProcessed[message.withdrawId] = type(uint256).max;
```

---

## High: Privileged Role Retention in Upgrader

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade()`  
**Lines:** 124-126, 155-161

**Root Cause:**  
The upgrader grants `DEFAULT_ADMIN_ROLE` to `msg.sender` on both the Treasury and CanonicalBridge contracts (lines 125-126) but never revokes these roles. While the upgrader revokes its own roles (lines 155-161), the caller retains permanent administrative access. The code includes a comment at line 124 stating "REVOKE manually if caller is not an authoritative multisig," which places critical security responsibility on manual post-deployment actions.

**Impact:**  
If the upgrade is executed by an EOA or compromised account, that account retains permanent admin control over both the Treasury and Bridge, including the ability to:
- Pause/unpause contracts
- Grant/revoke roles from other accounts  
- Upgrade the Treasury to malicious implementations
- Cancel pending withdrawals
- Modify the fraud window

This creates a centralization risk and violates the principle of least privilege.

**Recommendation:**  
Either:
1. Remove the grants to msg.sender entirely (lines 125-126) if not needed
2. Add explicit revocation at the end of the function:
```solidity
AccessControl(p.treasuryProxy).revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
AccessControl(newCanonicalBridge).revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
```
3. Add a boolean parameter to the function allowing the caller to opt-in to role retention only when necessary

---

## Medium: Inconsistent Reentrancy Protection

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()`  
**Lines:** 132-144

**Root Cause:**  
The `emergencyWithdraw()` function makes an external call to `msg.sender` at line 141 but lacks the `nonReentrant` modifier, while the standard `withdrawEth()` function includes this protection at line 113. Although the current implementation doesn't update state after the external call (following CEI pattern), the inconsistency creates maintenance risk.

**Impact:**  
While not immediately exploitable in the current code, if future modifications add state changes after the external call, reentrancy vulnerabilities could be introduced. The inconsistency also makes security reviews more difficult and may indicate incomplete threat modeling.

**Recommendation:**  
Add the `nonReentrant` modifier to `emergencyWithdraw()`:
```solidity
function emergencyWithdraw(uint256 amount) 
    external
    virtual 
    override 
    nonReentrant  // Add this
    onlyRole(EMERGENCY_ROLE)
```

---

## Medium: Low-Level Call for Treasury Deposit

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit()`  
**Lines:** 150

**Root Cause:**  
The function uses a low-level call with `abi.encodeWithSignature("depositEth()")` instead of using the ITreasury interface directly. This bypasses compile-time type checking and could mask interface mismatches.

**Impact:**  
If the Treasury implementation changes or doesn't implement `depositEth()` with the expected signature, the call will fail silently (returning false) rather than failing at compile time. This creates maintenance burden and increases the risk of runtime failures. Additionally, using string-based function signatures is more gas-expensive and error-prone than interface calls.

**Recommendation:**  
Replace the low-level call with a proper interface call:
```solidity
ITreasury(TREASURY).depositEth{value: amountWei}();
```

This provides compile-time type safety and clearer intent.

---

## Medium: Block Timestamp Manipulation in Fraud Window

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()`  
**Lines:** 196

**Root Cause:**  
The fraud window calculation uses `block.timestamp + fraudWindowDuration` where `block.timestamp` can be manipulated by miners within approximately 15 seconds. This affects when withdrawals become eligible for claiming.

**Impact:**  
A malicious miner could potentially manipulate the timestamp to:
- Slightly reduce the fraud window duration by setting an earlier timestamp
- Slightly extend the window by setting a later timestamp

Given the default fraud window is 7 days (604,800 seconds), a 15-second manipulation represents only 0.0025% deviation, making practical exploitation unlikely. However, if the fraud window is reduced to the minimum of 1 day, the relative impact increases to 0.017%.

**Recommendation:**  
Document this limitation in the contract comments. For critical security-sensitive timing:
```solidity
// Note: Uses block.timestamp which can be manipulated by miners within ~15 seconds
// This is acceptable given the multi-day fraud window duration
uint256 messageStartTime = block.timestamp + fraudWindowDuration;
```

Consider using block numbers instead of timestamps for more precise timing, or ensure the minimum fraud window duration is large enough to make timestamp manipulation negligible.

---

## Medium: Centralization Risk in Treasury Reinitialization

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize()`  
**Lines:** 71-91

**Root Cause:**  
The reinitialize function grants `DEFAULT_ADMIN_ROLE` to both the old owner (line 83) and the deployer/caller (line 90). This creates a situation where two entities have full administrative control over all roles.

**Impact:**  
Having multiple admin role holders increases the attack surface. If either account is compromised, the attacker gains full control. Additionally, if these accounts have conflicting interests, they could engage in role manipulation conflicts. The dual admin setup makes it unclear which account is the intended primary administrator.

**Recommendation:**  
Consider granting `DEFAULT_ADMIN_ROLE` to only one entity, preferably the old owner for continuity:
```solidity
function reinitialize() external virtual override reinitializer(2) {
    address oldOwner = _getOwnableStorage()._owner;
    if (oldOwner == NULL_ADDRESS) {
        revert InvalidInitialization();
    }
    emit TreasuryReinitialized(msg.sender, oldOwner);
    
    // Only grant to oldOwner
    _grantRole(DEFAULT_ADMIN_ROLE, oldOwner);
    _grantRole(PAUSER_ROLE, oldOwner);
    _grantRole(STARTER_ROLE, oldOwner);
    _grantRole(UPGRADER_ROLE, oldOwner);
    _grantRole(EMERGENCY_ROLE, oldOwner);
    
    // Remove this line:
    // _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
}
```

Alternatively, if the deployer needs temporary access, emit a warning event indicating manual revocation is required.

---

## Medium: Insufficient Balance Check Logic Gap

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()`  
**Lines:** 120-127

**Root Cause:**  
The balance check at line 120 verifies `address(this).balance < amountWei`, but the function actually sends `amountWei - feeWei` to one address and `feeWei` to another. While mathematically the total sent equals `amountWei` (making the check sufficient), the logic doesn't clearly express that two separate transfers are being validated.

**Impact:**  
Low practical risk since the math is correct, but creates code clarity issues. If a developer later modifies the fee calculation or adds additional transfers without understanding the implicit relationship, they might introduce bugs. The check also doesn't account for potential rounding errors or unexpected fee structures.

**Recommendation:**  
Add an explicit comment clarifying the logic:
```solidity
// Ensure balance covers both transfers: (amountWei - feeWei) + feeWei = amountWei
if (address(this).balance < amountWei) {
    revert InsufficientFunds();
}
```

Or make the check more explicit about the two transfers:
```solidity
if (address(this).balance < (amountWei - feeWei) + feeWei) {
    revert InsufficientFunds();
}
```

---

## Low: Upgrade Execution Order Dependency

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run()`  
**Lines:** 37-50

**Root Cause:**  
The deployment script performs the Treasury upgrade (lines 37-40) before deploying the CanonicalBridge (line 33). If the upgrade fails, the bridge will still be deployed and configured, potentially pointing to an incorrectly upgraded Treasury.

**Impact:**  
Limited impact since the entire transaction will revert on failure. However, in a multi-step deployment process or if operations are split across transactions, this ordering could lead to inconsistent states. The code also doesn't verify the upgrade succeeded before proceeding.

**Recommendation:**  
Add explicit success verification:
```solidity
// After upgradeToAndCall
require(
    _treasuryV1.getVersionComponents().major == 2,
    "Treasury upgrade failed"
);
```

Consider reordering to deploy contracts first, then configure/upgrade, or use a deployment pattern that atomically reverts all changes on any failure.

---

## Low: Missing Zero-Value Transfer Check

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth()`  
**Lines:** 106-128

**Root Cause:**  
The function allows `amountWei` to be any value greater than the balance, but doesn't explicitly prevent zero-value transfers when `amountWei == feeWei`, meaning the recipient gets 0 wei.

**Impact:**  
Wastes gas on no-op transfers and emits potentially confusing events. While not a security vulnerability, it represents inefficient operation and could mask errors in calling code.

**Recommendation:**  
Add validation:
```solidity
if (amountWei - feeWei == 0) revert InvalidAmount();
```

Or more generally:
```solidity
if (amountWei == 0) revert InvalidAmount();
```

---

## Low: Fraud Window Boundary Condition

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `withdrawMessageStatus()`  
**Lines:** 120

**Root Cause:**  
The status check uses `startTime_ > block.timestamp` to determine PROCESSING state. At the exact timestamp where `startTime_ == block.timestamp`, the function returns PENDING, making the withdrawal immediately claimable at that precise block.

**Impact:**  
Minimal practical impact as this is a single-block edge case. However, it means withdrawals become claimable slightly earlier than intended (at the boundary rather than after). For most use cases with multi-day fraud windows, this is negligible, but for precision-critical applications it may matter.

**Recommendation:**  
If the intent is for withdrawals to be claimable only AFTER the fraud window expires, change line 120:
```solidity
if (startTime_ >= block.timestamp) return WithdrawStatus.PROCESSING;
```

Otherwise, document that withdrawals are claimable AT the fraud window expiry time.

---

## Informational: Inconsistent Import Style

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Lines:** 4-10

**Root Cause:**  
The contract mixes import styles, using `openzeppelin-contracts-upgradeable` (line 6, 8-9) and `@openzeppelin/contracts` (line 7, 10). This inconsistency suggests potential dependency confusion.

**Impact:**  
No immediate security impact, but could cause issues if the two import paths resolve to different versions of OpenZeppelin libraries. May also indicate incomplete refactoring.

**Recommendation:**  
Standardize imports to use either `openzeppelin-contracts-upgradeable` or `@openzeppelin/contracts` consistently. Verify that both paths resolve to the same version.

---

## Informational: Missing Events for Critical State Changes

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `pause()` and `unpause()`  
**Lines:** 148-156

**Root Cause:**  
The pause/unpause functions call internal `_pause()` and `_unpause()` which emit events, but there are no additional events indicating WHO triggered these critical operations beyond the inherited OpenZeppelin events.

**Impact:**  
Reduced observability for monitoring systems. While OpenZeppelin's Pausable contract emits `Paused(address)` and `Unpaused(address)` events, having explicit Treasury-specific events would improve auditability.

**Recommendation:**  
Consider adding custom events:
```solidity
event TreasuryPaused(address indexed by);
event TreasuryUnpaused(address indexed by);
```

---

## Informational: Unbounded Loop in Batch Authorization

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `authorizeWithdraws()`  
**Lines:** 168-170

**Root Cause:**  
The function iterates over an unbounded array of withdraw messages without any limit on the array size.

**Impact:**  
If too many messages are submitted in a single transaction, the gas cost could exceed block gas limits, causing the transaction to fail. This could be used to DoS the batch authorization functionality, though single authorizations would still work.

**Recommendation:**  
Add a maximum batch size:
```solidity
uint256 constant MAX_BATCH_SIZE = 100;

function authorizeWithdraws(WithdrawMessage[] calldata messages) external {
    if (messages.length > MAX_BATCH_SIZE) revert BatchTooLarge();
    for (uint256 i = 0; i < messages.length; i++) {
        _authorizeWithdraw(messages[i]);
    }
}
```

---

## Informational: Floating Pragma Should Be Avoided

**File:** All files in scope use fixed pragma `0.8.21`

**Root Cause:**  
The contracts correctly use fixed pragma versions (`pragma solidity 0.8.21`), which is good practice.

**Impact:**  
Positive - this prevents compilation with different compiler versions that might have different behaviors or bugs.

**Recommendation:**  
No changes needed. This is noted as a positive finding.

---

## Informational: Missing NatSpec Documentation

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()`  
**Lines:** 189-214

**Root Cause:**  
Internal functions like `_authorizeWithdraw` have minimal documentation. Complex internal logic should be well-documented for maintainability.

**Impact:**  
No security impact, but reduces code maintainability and makes security reviews more difficult.

**Recommendation:**  
Add comprehensive NatSpec comments explaining the function's purpose, parameters, state changes, and any invariants it maintains.

---

## Informational: Consider Using Custom Errors Throughout

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Lines:** Various

**Root Cause:**  
The contract uses custom errors (like `CanonicalBridgeTransactionRejected`) which is good, but some functions use string error messages in require statements, creating inconsistency.

**Impact:**  
String errors are more gas-expensive than custom errors. Mixed usage creates inconsistency.

**Recommendation:**  
Convert all error cases to use custom errors for gas efficiency and consistency:
```solidity
error CannotCancel();
error DurationTooShort();
// etc.
```

---

## Informational: Immutable Treasury Address Prevents Migration

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Lines:** 39

**Root Cause:**  
The `TREASURY` address is declared as immutable, meaning it cannot be changed after contract deployment. If the Treasury needs to be upgraded to a different proxy address or if there's a critical issue requiring Treasury migration, the entire CanonicalBridge would need to be redeployed.

**Impact:**  
Reduces flexibility in emergency scenarios. If the Treasury contract has a critical vulnerability requiring a full redeployment (not just an upgrade), the bridge cannot be redirected to a new Treasury. All authorized but unclaimed withdrawals would need complex migration logic.

**Recommendation:**  
Consider making TREASURY a mutable storage variable with appropriate access controls:
```solidity
address public treasury;

function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (newTreasury == address(0)) revert ZeroAddress();
    emit TreasuryUpdated(treasury, newTreasury);
    treasury = newTreasury;
}
```

Alternatively, if immutability is desired for security, document this limitation clearly and ensure the Treasury upgrade mechanisms are robust.

---

## Informational: No Rate Limiting on Emergency Withdrawals

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw()`  
**Lines:** 132-144

**Root Cause:**  
The emergency withdrawal function has no rate limiting, cooldown period, or maximum withdrawal amount per transaction/time period. An account with `EMERGENCY_ROLE` can withdraw the entire Treasury balance in a single transaction.

**Impact:**  
While emergency functions are intentionally powerful for crisis response, the lack of any rate limiting means a compromised `EMERGENCY_ROLE` account can instantly drain all funds. There's no time-delay mechanism to detect and respond to unauthorized emergency withdrawals.

**Recommendation:**  
Consider implementing a time-delay mechanism for large emergency withdrawals:
```solidity
mapping(uint256 => uint256) public emergencyWithdrawalScheduled;
uint256 public constant EMERGENCY_DELAY = 24 hours;
uint256 public constant INSTANT_WITHDRAWAL_LIMIT = 100 ether;

function scheduleEmergencyWithdrawal(uint256 amount) external onlyRole(EMERGENCY_ROLE) {
    if (amount <= INSTANT_WITHDRAWAL_LIMIT) {
        _executeEmergencyWithdrawal(amount);
    } else {
        uint256 withdrawalId = uint256(keccak256(abi.encode(msg.sender, amount, block.timestamp)));
        emergencyWithdrawalScheduled[withdrawalId] = block.timestamp + EMERGENCY_DELAY;
        emit EmergencyWithdrawalScheduled(withdrawalId, amount, block.timestamp + EMERGENCY_DELAY);
    }
}
```

This provides a window for detecting and responding to unauthorized emergency actions while maintaining the ability to quickly withdraw smaller amounts.
