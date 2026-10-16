# Security Audit Report

## Critical: Incorrect Fee Accounting in Treasury.withdrawEth Causes Fund Locking

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The function calculates `totalAmount = amountWei + feeWei` (line 120) and checks if the contract balance is sufficient for this amount. However, it only sends out a total of `amountWei` (split as `amountWei - feeWei` to the recipient and `feeWei` to the fee receiver). This means on every withdrawal, `feeWei` worth of ETH remains locked in the contract.

According to the interface documentation, `amountWei` is "the gross amount of Eth to withdraw" and `feeWei` is the "amount to deduce from gross amount." The correct check should be `totalAmount = amountWei`.

**Impact:**  
Every withdrawal permanently locks `feeWei` amount of ETH in the Treasury contract. Over time, this accumulates and cannot be withdrawn through normal means, leading to fund loss. Only emergency withdrawal can recover these locked funds.

**Proof:**
- Line 120: `uint256 totalAmount = amountWei + feeWei;`
- Line 124: Sends `amountWei - feeWei` to recipient
- Line 126: Sends `feeWei` to fee receiver
- Total sent: `(amountWei - feeWei) + feeWei = amountWei`
- Balance check requires: `amountWei + feeWei`
- Leftover per withdrawal: `feeWei`

**Recommendation:**  
Change line 120 to:
```solidity
uint256 totalAmount = amountWei;
```

## Critical: Duplicate WithdrawId Vulnerability Allows Fund Draining

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw` (lines 187-206)

**Root Cause:**  
The contract maintains a `withdrawMsgIdProcessed` mapping (line 44) that is set to `true` when a withdrawal is authorized (line 199), but this mapping is never checked before authorizing a new withdrawal. This allows the same `withdrawId` to be used in multiple different withdraw messages as long as the message hashes differ.

**Impact:**  
A malicious or compromised withdraw authority can authorize multiple different withdraw messages with the same `withdrawId` by varying other fields (e.g., `feeReceiver`, `feeWei`). Each unique message hash will be authorized, allowing the same withdrawal to be claimed multiple times, draining the treasury.

**Attack Scenario:**
1. Attacker with WITHDRAW_AUTHORITY_ROLE creates WithdrawMessage A: `{..., withdrawId: 1, amountWei: 100 ETH, feeReceiver: Alice, feeWei: 0}`
2. Authorizes it → `withdrawMsgIdProcessed[1] = true`, `startTime[hash(A)] = now + fraud_window`
3. Creates WithdrawMessage B: `{..., withdrawId: 1, amountWei: 100 ETH, feeReceiver: Bob, feeWei: 1}` (different hash)
4. Authorizes it → No check prevents this! `startTime[hash(B)] = now + fraud_window`
5. After fraud window, claims both → drains 200 ETH instead of 100 ETH

**Recommendation:**  
Add a check before line 199:
```solidity
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Withdraw ID already processed");
}
```

## High: Missing Reentrancy Protection on claimWithdrawal

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal` (lines 210-232)

**Root Cause:**  
The `claimWithdrawal` function calls an external contract (Treasury) at line 222-227 before updating the state at line 230. While the contract inherits `ReentrancyGuard`, the `claimWithdrawal` function does not use the `nonReentrant` modifier. The function relies entirely on the Treasury's reentrancy protection.

**Impact:**  
If the Treasury implementation is ever changed to remove reentrancy protection, or if a different treasury is used, the Bridge becomes vulnerable to reentrancy attacks where an attacker could claim the same withdrawal multiple times before the state is updated.

**Recommendation:**  
Add the `nonReentrant` modifier to the `claimWithdrawal` function:
```solidity
function claimWithdrawal(
    WithdrawMessage calldata message
)
    external
    override
    whenNotPaused
    validWithdrawMessage(message)
    nonReentrant  // ADD THIS
{
    // ... existing code
}
```

## High: Missing feeReceiver Validation in Bridge

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 64-81)

**Root Cause:**  
The `validWithdrawMessage` modifier checks that `message.destination` is not the zero address (line 68-70) but does not perform the same check for `message.feeReceiver`. The Treasury's `withdrawEth` function will revert if `feeReceiver` is the zero address (line 116), but failing at the Treasury level instead of the Bridge level provides poor user experience and wastes gas.

**Impact:**  
Withdraw messages with `feeReceiver = address(0)` will be authorized successfully but will always fail when claimed, wasting gas and creating confusion. Additionally, if `feeReceiver` is set to a contract that always reverts, all withdrawals with that fee receiver will be permanently stuck.

**Recommendation:**  
Add a check in the `validWithdrawMessage` modifier after line 69:
```solidity
if (message.feeReceiver == NULL_ADDRESS) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "Null message.feeReceiver");
}
```

## Medium: Upgrader Grants Permanent Admin Role to Transaction Executor

**File:** `upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade` (lines 90-204)

**Root Cause:**  
The upgrade function grants `DEFAULT_ADMIN_ROLE` to `msg.sender` (the transaction executor) at lines 129-130 and never revokes it. While there is a comment (line 128) stating to "REVOKE manually if caller is not an authoritative multisig," relying on manual post-deployment steps is error-prone and creates a security risk.

**Impact:**  
If the upgrade is executed by a compromised account, externally owned account (EOA), or non-multisig wallet, that account retains permanent administrative control over both the Treasury and CanonicalBridge contracts. This creates a centralization risk and potential attack vector.

**Recommendation:**  
Either:
1. Remove the role grant to `msg.sender` entirely if not needed, or
2. Add explicit checks that `msg.sender` is the intended admin address passed as a parameter, or
3. Implement an automatic revocation mechanism after a time delay

## Medium: Treasury Missing receive/fallback Function

**File:** `Treasury.sol`  
**Lines:** Entire contract (1-162)

**Root Cause:**  
The Treasury contract does not implement a `receive()` or `fallback()` function to accept direct ETH transfers. The interface comment (ITreasury.sol line 6) states "This interface assumes the implementation will provide a fallback function to receive ether," but the implementation lacks this functionality.

**Impact:**  
Direct ETH transfers to the Treasury will fail. While this may be intentional to ensure all deposits go through the `depositEth` function and emit proper events, it contradicts the interface documentation and could cause unexpected failures if someone attempts to send ETH directly to the Treasury.

**Recommendation:**  
Either:
1. Add a `receive()` function that calls `depositEth()` with proper access control:
```solidity
receive() external payable {
    if (!hasRole(DEPOSITOR_ROLE, msg.sender)) {
        revert AccessControlUnauthorizedAccount(msg.sender, DEPOSITOR_ROLE);
    }
    emit TreasuryDeposit(msg.sender, msg.value);
}
```
2. Or update the interface documentation to clarify that direct ETH transfers are not supported

## Medium: Fraud Window Can Be Set Arbitrarily High

**File:** `CanonicalBridge.sol`  
**Function:** `setFraudWindowDuration` (line 263)

**Root Cause:**  
The function checks that the fraud window duration is not less than `MIN_FRAUD_WINDOW_DURATION` (1 day) but does not enforce a maximum value. An account with `FRAUD_WINDOW_SETTER_ROLE` could set the duration to an extremely large value (e.g., `type(uint256).max` or thousands of years).

**Impact:**  
If the fraud window is set to an unreasonably large value, all future withdrawals would be delayed by that amount, effectively freezing the bridge and causing a denial of service. Users would not be able to claim their withdrawals for an impractically long time.

**Recommendation:**  
Add a maximum fraud window duration check:
```solidity
uint256 private constant MAX_FRAUD_WINDOW_DURATION = 30 days;

function setFraudWindowDuration(uint256 durationSeconds) public onlyRole(FRAUD_WINDOW_SETTER_ROLE) {
    if (durationSeconds < MIN_FRAUD_WINDOW_DURATION) revert DurationTooShort();
    if (durationSeconds > MAX_FRAUD_WINDOW_DURATION) revert DurationTooLong();
    _setFraudWindowDuration(durationSeconds);
}
```

## Low: Malicious feeReceiver Can Deny Service to Withdrawals

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The function sends ETH to both `to` and `feeReceiver` addresses using low-level calls. If `feeReceiver` is a contract that reverts on receiving ETH, the entire withdrawal transaction will fail. While the `feeReceiver` is specified by the withdraw authority (a trusted role), a compromised withdraw authority account could set all withdrawals to use a reverting contract as the fee receiver.

**Impact:**  
A compromised or malicious withdraw authority could create a denial-of-service condition by setting `feeReceiver` to a contract that always reverts, preventing all withdrawals from being claimed.

**Recommendation:**  
Consider implementing a pull-based payment system for fees, or add a try-catch mechanism to handle fee receiver failures gracefully:
```solidity
(bool feeSuccess,) = payable(feeReceiver).call{value: feeWei}("");
if (!feeSuccess) {
    // Log failure and hold fee in contract for manual recovery
    emit FeeTransferFailed(feeReceiver, feeWei);
}
```

## Low: deleteWithdrawMessage Does Not Clear withdrawMsgIdProcessed Flag

**File:** `CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage` (lines 252-258)

**Root Cause:**  
When a withdrawal message is cancelled via `deleteWithdrawMessage`, the function resets `startTime[messageHash]` to 0 but does not clear the `withdrawMsgIdProcessed[message.withdrawId]` flag. This means once a `withdrawId` is used (even if later cancelled), it cannot be reused.

**Impact:**  
While unlikely to cause issues in practice (uint64 provides 2^64 possible IDs), this prevents `withdrawId` reuse even after cancellation. If the off-chain system attempts to reuse a cancelled `withdrawId`, it will be blocked (assuming the Critical finding above is fixed).

**Recommendation:**  
If `withdrawId` reuse after cancellation is desired, clear the flag when deleting:
```solidity
function deleteWithdrawMessage(bytes32 messageHash) public onlyRole(WITHDRAW_CANCELLER_ROLE) {
    WithdrawStatus status = withdrawMessageStatus(messageHash);
    if (status != WithdrawStatus.PENDING && status != WithdrawStatus.PROCESSING) {
        revert CannotCancel();
    }
    // Clear both the message and the withdrawId flag
    uint64 withdrawId = /* extract from message */;  // Note: Need to store withdrawId mapping
    withdrawMsgIdProcessed[withdrawId] = false;
    startTime[messageHash] = 0;
    emit WithdrawMessageHashDeleted(msg.sender, messageHash);
}
```

However, this would require storing a reverse mapping from messageHash to withdrawId, which adds complexity.

## Informational: Unused PRECISION Constant

**File:** `CanonicalBridge.sol`  
**Line:** 28

**Root Cause:**  
The contract defines `uint256 private constant PRECISION = 1e18;` but never uses it.

**Impact:**  
No security impact. This is likely dead code from earlier development.

**Recommendation:**  
Remove the unused constant to reduce code clutter.

## Informational: Treasury.withdrawEth Never Returns False

**File:** `Treasury.sol`  
**Function:** `withdrawEth` (lines 106-129)

**Root Cause:**  
The function signature returns `bool success`, but due to the revert checks at lines 125 and 127, the function will either return `true` or revert. It can never return `false`.

**Impact:**  
No security impact. The CanonicalBridge checks the return value and reverts if false (line 229), but this check is unreachable since the Treasury will revert first.

**Recommendation:**  
For clarity, either:
1. Remove the return value and make the function return nothing (rely on reverts), or
2. Keep the current implementation (it's defensive programming by the Bridge)

## Summary

This audit identified **2 Critical**, **2 High**, **3 Medium**, **2 Low**, and **2 Informational** severity findings. The most severe issues are:

1. **Treasury fee accounting bug** - Causes permanent fund locking on every withdrawal
2. **WithdrawId reuse vulnerability** - Allows draining the treasury through duplicate withdrawals

These critical issues should be addressed immediately before deployment.
