# Security Audit Report

## Critical: Incorrect balance check in Treasury.withdrawEth causes withdrawal DoS

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The function incorrectly calculates the required balance as `amountWei + feeWei` (line 120), when it should be just `amountWei`. According to the interface documentation, `amountWei` represents the gross amount to withdraw, and `feeWei` is deducted from this gross amount, not added to it.

**Impact:**  
All withdrawals with fees will fail when the Treasury balance exactly matches the deposited amounts. For example:
- User deposits 100 wei
- User withdraws 90 wei with 10 wei fee
- Bridge calls `withdrawEth(user, 100, feeReceiver, 10)`
- Check fails: `100 >= 110` is false
- Transaction reverts, funds are stuck

**Recommended Fix:**  
Change line 120 from:
```solidity
uint256 totalAmount = amountWei + feeWei;
```
to:
```solidity
uint256 totalAmount = amountWei;
```

## High: Missing withdrawMsgIdProcessed check allows duplicate withdraw IDs

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (lines 187-206)

**Root Cause:**  
The function sets `withdrawMsgIdProcessed[message.withdrawId] = true` at line 199 but never checks this mapping before authorization. The only duplicate check is for the message hash at line 195, which doesn't prevent the same `withdrawId` from being used in different messages.

**Impact:**  
An attacker with WITHDRAW_AUTHORITY_ROLE can authorize multiple different withdrawal messages using the same `withdrawId` but with different destinations or amounts. This violates the uniqueness constraint that withdraw IDs should only be used once, potentially allowing:
- Same rollup withdrawal to be claimed multiple times with different recipients
- Accounting inconsistencies between L2 and L1
- Theft of funds if the same withdrawId processes different amounts

**Recommended Fix:**  
Add a check before line 198:
```solidity
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Withdraw ID already used");
}
```

## High: Missing feeReceiver validation allows unclaimed withdrawals

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 64-81)

**Root Cause:**  
The `validWithdrawMessage` modifier validates `message.destination` is not zero (line 68) but doesn't validate `message.feeReceiver`. However, `Treasury.withdrawEth` requires both addresses to be non-zero (lines 115-116).

**Impact:**  
Withdraw messages with `feeReceiver = address(0)` can be authorized successfully but will always fail when claimed, effectively creating a DoS condition:
- Legitimate withdrawals with zero address as feeReceiver are authorized
- Users attempt to claim but transactions revert in Treasury
- Withdrawals remain stuck in PENDING state
- Requires WITHDRAW_CANCELLER_ROLE intervention to delete and re-authorize

**Recommended Fix:**  
Add validation in the `validWithdrawMessage` modifier after line 69:
```solidity
if (message.feeReceiver == NULL_ADDRESS) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Null message.feeReceiver");
}
```

## High: deleteWithdrawMessage doesn't clear withdrawMsgIdProcessed mapping

**File:** `CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage` (lines 252-258)

**Root Cause:**  
When a withdraw message is deleted/cancelled, the function only clears the `startTime` mapping (line 257) but doesn't clear the `withdrawMsgIdProcessed` mapping. This means the withdrawId remains marked as "processed" even after cancellation.

**Impact:**  
After a withdrawal is cancelled:
- The same withdrawId cannot be reused for a new withdrawal authorization
- If the rollup needs to retry the same withdrawal, it must use a new withdrawId
- This could cause synchronization issues between L1 and L2 state
- Wastes withdraw ID space

**Recommended Fix:**  
The function should also clear the processed mapping. However, this requires tracking the withdrawId from the message hash, which isn't currently stored. Consider either:
1. Adding a reverse mapping from messageHash to withdrawId
2. Only accepting the full WithdrawMessage for deletion (not the hash variant)
3. Documenting that cancelled withdrawIds cannot be reused

## High: Upgrader grants unrestricted admin access to msg.sender

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
Lines 129-130 unconditionally grant `DEFAULT_ADMIN_ROLE` to `msg.sender` on both the Treasury and new CanonicalBridge with only a comment stating "REVOKE manually if caller is not an authoritative multisig."

**Impact:**  
- Manual post-upgrade steps are error-prone and may be forgotten
- If msg.sender is compromised or malicious, they gain permanent admin access
- Creates a critical security window between upgrade and manual revocation
- Violates principle of least privilege
- If msg.sender is a contract or multisig that later becomes compromised, the admin access persists

**Recommended Fix:**  
Either:
1. Remove the automatic grant and require explicit role assignment via separate function calls
2. Add a parameter to specify whether msg.sender should receive admin roles
3. Add explicit documentation requiring immediate role revocation

## Medium: Treasury.emergencyWithdraw lacks reentrancy protection

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (lines 133-145)

**Root Cause:**  
Unlike `withdrawEth` which has the `nonReentrant` modifier (line 113), `emergencyWithdraw` performs an external call at line 142 without reentrancy protection.

**Impact:**  
If `msg.sender` is a malicious contract with EMERGENCY_ROLE, it could:
- Reenter the function during the ETH transfer
- Potentially drain more funds than intended
- Though limited by the access control, it still violates defense-in-depth principles

**Recommended Fix:**  
Add `nonReentrant` modifier:
```solidity
function emergencyWithdraw(
    uint256 amount
) 
    external
    virtual 
    override 
    nonReentrant  // Add this
    onlyRole(EMERGENCY_ROLE)
```

## Medium: Use of abi.encodeWithSignature instead of type-safe encoding

**File:** `CanonicalBridge.sol`  
**Function:** `deposit` (line 148)

**Root Cause:**  
The function uses `abi.encodeWithSignature("depositEth()")` to call the Treasury's depositEth function. This is a string-based encoding which is:
- More gas expensive than using proper interface calls
- Error-prone (typos won't be caught at compile time)
- Doesn't benefit from compiler type checking

**Impact:**  
- If the function signature changes in Treasury, this call will fail at runtime
- Wastes gas on every deposit
- Increases maintenance burden
- Silent failures if function signature is misspelled

**Recommended Fix:**  
Use a type-safe interface call:
```solidity
(success,) = payable(address(TREASURY)).call{value: amountWei}(
    abi.encodeCall(ITreasury.depositEth, ())
);
```

## Medium: Missing storage gap in upgradeable Treasury contract

**File:** `Treasury.sol`  
**Lines:** 13-23 (contract definition)

**Root Cause:**  
The Treasury contract is upgradeable (inherits from UUPSUpgradeable) but doesn't include a storage gap. Storage gaps are critical for upgradeable contracts to reserve space for future storage variables.

**Impact:**  
- Future upgrades that add new storage variables could conflict with child contract storage
- Storage collisions could corrupt contract state
- Makes safe upgradeability difficult without careful storage layout analysis
- Industry best practice (OpenZeppelin) recommends always including gaps

**Recommended Fix:**  
Add a storage gap at the end of the contract:
```solidity
uint256[50] private __gap;
```

## Medium: Unbounded loop in authorizeWithdraws can hit gas limit

**File:** `CanonicalBridge.sol`  
**Function:** `authorizeWithdraws` (lines 158-169)

**Root Cause:**  
The function iterates over an unbounded array of messages without any length check:
```solidity
for (uint256 i = 0; i < messages.length; i++) {
    _authorizeWithdraw(messages[i]);
}
```

**Impact:**  
- Large batches could exceed block gas limit
- Transaction reverts, wasting gas
- DoS if WITHDRAW_AUTHORITY_ROLE submits excessively large batches
- All-or-nothing: if one message fails, entire batch reverts

**Recommended Fix:**  
Add a maximum batch size check:
```solidity
uint256 constant MAX_BATCH_SIZE = 100;
if (messages.length > MAX_BATCH_SIZE) {
    revert CanonicalBridgeTransactionRejected(0, "Batch too large");
}
```

## Medium: No validation of upgrade implementation contracts

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
The upgrader accepts `newTreasuryImplementation` address as a parameter but doesn't verify:
- It's actually a Treasury implementation
- It has the expected version
- It has the expected interface
- It's not malicious

**Impact:**  
- Wrong implementation could be deployed during upgrade
- Malicious implementation could be used if parameters are incorrect
- No verification that the new implementation matches expected code
- Human error in specifying addresses could brick the system

**Recommended Fix:**  
Add implementation validation:
```solidity
// Verify implementation version
ITreasury.Version memory version = ITreasury(p.newTreasuryImplementation).getVersionComponents();
if (version.major != 2 || version.minor != 0 || version.patch != 0) {
    revert InvalidImplementationVersion();
}
```

## Medium: Integer overflow risk in startTime calculation

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (line 194)

**Root Cause:**  
The calculation `block.timestamp + fraudWindowDuration` could theoretically overflow if fraudWindowDuration is extremely large:
```solidity
uint256 messageStartTime = block.timestamp + fraudWindowDuration;
```

**Impact:**  
- If overflow occurs, `messageStartTime` wraps to a small value
- Withdrawal becomes immediately claimable instead of delayed
- Bypasses fraud window protection
- Though unlikely in practice (requires fraudWindow > 2^256 - current_timestamp), it's a theoretical risk

**Recommended Fix:**  
Use checked arithmetic or add validation:
```solidity
uint256 messageStartTime;
unchecked {
    messageStartTime = block.timestamp + fraudWindowDuration;
    if (messageStartTime < block.timestamp) revert OverflowDetected();
}
```

## Low: emergencyWithdraw may fail for contract msg.sender

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw` (line 142)

**Root Cause:**  
The function sends ETH directly to `msg.sender` without checking if it can receive ETH:
```solidity
(bool success,) = payable(msg.sender).call{value: amount}("");
```

**Impact:**  
- If msg.sender is a contract without a receive/fallback function, transfer fails
- Emergency withdrawal becomes impossible for contract-based admin
- Particularly problematic since this is the "emergency" function

**Recommended Fix:**  
Either:
1. Add a `recipient` parameter to specify where funds should go
2. Document that EMERGENCY_ROLE must only be granted to EOAs or contracts that can receive ETH
3. Use a pull-payment pattern instead

## Low: Allows feeWei to equal amountWei causing zero transfer to recipient

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 77-79)

**Root Cause:**  
The validation allows `feeWei == amountWei`:
```solidity
if (message.feeWei > message.amountWei) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee exceeds message.amount");
}
```

**Impact:**  
- When `feeWei == amountWei`, the recipient receives 0 wei
- The entire withdrawal amount goes to the fee receiver
- While technically valid, this seems like an edge case that should be prevented
- Users might not intend to send their entire withdrawal as a fee

**Recommended Fix:**  
Consider requiring feeWei < amountWei (strict inequality):
```solidity
if (message.feeWei >= message.amountWei) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee must be less than amount");
}
```

## Low: Block timestamp dependence in fraud window

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (line 194), `withdrawMessageStatus` (line 118)

**Root Cause:**  
The contract relies on `block.timestamp` for fraud window timing:
```solidity
uint256 messageStartTime = block.timestamp + fraudWindowDuration;
if (startTime_ > block.timestamp) return WithdrawStatus.PROCESSING;
```

**Impact:**  
- Miners/validators can manipulate block.timestamp within a small range (~15 seconds)
- Could slightly accelerate when withdrawals become claimable
- Low impact since fraud window is typically days long
- Still worth noting for completeness

**Recommended Fix:**  
Use `block.number` instead of `block.timestamp` for more predictable timing, or accept the risk as negligible given the fraud window duration (minimum 1 day).

## Low: Missing zero-value deposit check

**File:** `CanonicalBridge.sol`  
**Function:** `deposit` (lines 137-154)

**Root Cause:**  
While the `validDepositAmount` modifier checks for minimum deposit (line 59), it doesn't explicitly check for zero deposits. The minimum check covers this case, but explicit validation would be clearer.

**Impact:**  
- Zero deposits are prevented by MIN_DEPOSIT check
- However, error message "Deposit less than minimum" is misleading for zero deposits
- Code clarity issue rather than security issue

**Recommended Fix:**  
Add explicit zero check with clear error message:
```solidity
if (amountWei == 0) revert CanonicalBridgeTransactionRejected(0, "Zero deposit not allowed");
if (amountWei < MIN_DEPOSIT) revert CanonicalBridgeTransactionRejected(0, "Deposit less than minimum");
```

## Informational: Fraud window changes don't affect existing authorizations

**File:** `CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration` (line 263)

**Root Cause:**  
When the fraud window duration is changed via `setFraudWindowDuration`, it only affects new authorizations. Existing authorized withdrawals maintain their original `startTime` based on the fraud window at authorization time.

**Impact:**  
- Expected behavior, but could be surprising to users
- If fraud window is reduced, old withdrawals don't become claimable sooner
- If fraud window is increased, old withdrawals aren't delayed further
- This is likely intentional but should be documented

**Recommended Fix:**  
Add documentation in the function's NatSpec:
```solidity
/// @notice Changes only affect newly authorized withdrawals, not existing ones
```

## Informational: Centralization risk with powerful roles

**File:** `CanonicalBridge.sol`, `Treasury.sol`  
**Multiple functions**

**Root Cause:**  
The contracts use multiple powerful roles:
- WITHDRAW_AUTHORITY_ROLE can authorize arbitrary withdrawals
- WITHDRAW_CANCELLER_ROLE can delete pending withdrawals
- EMERGENCY_ROLE can withdraw all Treasury funds
- DEFAULT_ADMIN_ROLE can grant/revoke all roles

**Impact:**  
- Single compromised role can cause significant damage
- Requires strong operational security
- Need for multisig or timelocks on critical roles
- Users must trust role holders

**Recommended Fix:**  
- Document that critical roles should use multisig wallets
- Consider adding timelocks for critical operations
- Consider splitting EMERGENCY_ROLE from DEFAULT_ADMIN_ROLE
- Add monitoring and alerts for role usage

## Informational: Missing events for withdrawMsgIdProcessed

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (line 199)

**Root Cause:**  
When `withdrawMsgIdProcessed` is set to true, there's no dedicated event. The information is part of `WithdrawAuthorized` event but not explicitly surfaced.

**Impact:**  
- Harder to track which withdrawIds have been used
- Off-chain indexers need to decode the full WithdrawMessage to find withdrawId
- Not a security issue but affects observability

**Recommended Fix:**  
Add explicit event or include withdrawId as indexed parameter in WithdrawAuthorized.

## Informational: Race condition between claimWithdrawal and deleteWithdrawMessage

**File:** `CanonicalBridge.sol`  
**Functions:** `claimWithdrawal` (line 210), `deleteWithdrawMessage` (line 252)

**Root Cause:**  
When a withdrawal is in PENDING state, both `claimWithdrawal` and `deleteWithdrawMessage` can be called. Whichever transaction is mined first succeeds, the other reverts.

**Impact:**  
- Normal behavior for concurrent operations
- One transaction will fail and waste gas
- Users/relayers should check status before claiming
- Not exploitable, just inconvenient

**Recommended Fix:**  
Document expected behavior and recommend status checks before claiming.

## Informational: Front-running opportunities on claimWithdrawal

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 210-232)

**Root Cause:**  
Anyone can call `claimWithdrawal` for any valid withdrawal message. The funds go to `message.destination` regardless of who calls the function.

**Impact:**  
- MEV bots can front-run legitimate claim transactions
- Bots claim on behalf of users to extract fee revenue
- Not a security issue since funds still go to correct recipient
- Users may not have control over when/how their withdrawal is claimed

**Recommended Fix:**  
This is intended behavior for permissionless claiming. Document that relayers can claim on behalf of users and earn fees.
