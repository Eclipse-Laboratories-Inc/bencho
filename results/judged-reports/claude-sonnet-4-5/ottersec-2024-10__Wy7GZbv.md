# Security Audit Report

## Critical: Incorrect Balance Check in Treasury.withdrawEth()

**File:** `Treasury.sol`  
**Function:** `withdrawEth()` (lines 106-129)

**Root Cause:**  
The function calculates `totalAmount = amountWei + feeWei` and checks if the contract balance is sufficient for this total. However, according to the interface documentation, `feeWei` is "amount to deduce from gross amount", meaning it should be subtracted from `amountWei`, not added. The actual transfers correctly send `amountWei - feeWei` to the recipient and `feeWei` to the fee receiver (totaling `amountWei`), but the balance check requires `amountWei + feeWei`.

**Impact:**  
Legitimate withdrawals will fail when the Treasury balance is between `amountWei` and `amountWei + feeWei`, even though sufficient funds exist to complete the withdrawal. This creates a denial-of-service condition where valid withdrawals are rejected.

**Recommendation:**  
Change line 120 from:
```solidity
uint256 totalAmount = amountWei + feeWei;
```
to:
```solidity
uint256 totalAmount = amountWei;
```

## Critical: Duplicate withdrawId Values Allowed

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()` (lines 187-206)

**Root Cause:**  
The function sets `withdrawMsgIdProcessed[message.withdrawId] = true` on line 199 but never checks if this withdrawId has already been processed. The only validation checks if the message hash already exists (line 195), which allows multiple different messages with the same withdrawId to be authorized since each would have a unique hash.

**Impact:**  
A malicious or compromised WITHDRAW_AUTHORITY can authorize multiple withdrawal messages with the same `withdrawId` but different destinations or amounts. Each can be claimed independently, potentially draining the Treasury. Since `withdrawId` should uniquely identify a withdrawal from the rollup, this breaks the fundamental invariant of the bridge and enables double-spending attacks.

**Recommendation:**  
Add a check before line 199:
```solidity
if (withdrawMsgIdProcessed[message.withdrawId]) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "withdrawId already processed");
}
```

## High: Missing Reentrancy Protection in claimWithdrawal()

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal()` (lines 210-232)

**Root Cause:**  
The function violates the Checks-Effects-Interactions (CEI) pattern by updating state (`startTime[messageHash] = NEVER`) after making an external call to `Treasury.withdrawEth()`. While currently protected by the Treasury's `nonReentrant` modifier, this creates a fragile dependency.

**Impact:**  
If the Treasury implementation is ever changed to remove or modify its reentrancy guard, the bridge becomes vulnerable to reentrancy attacks where a malicious recipient contract could reenter `claimWithdrawal()` before the state is updated, potentially claiming the same withdrawal multiple times.

**Recommendation:**  
Add the `nonReentrant` modifier to `claimWithdrawal()` or move the state update before the external call:
```solidity
startTime[messageHash] = NEVER;
bool success = ITreasury(TREASURY).withdrawEth(...);
```

## High: deleteWithdrawMessage() Doesn't Clear withdrawMsgIdProcessed

**File:** `CanonicalBridge.sol`  
**Function:** `deleteWithdrawMessage()` (lines 238-259)

**Root Cause:**  
When a withdrawal message is deleted, the function clears `startTime[messageHash]` but does not reset `withdrawMsgIdProcessed[message.withdrawId]`. This leaves the withdrawId permanently marked as processed even after cancellation.

**Impact:**  
Once a withdrawal is authorized and then cancelled, the withdrawId remains unusable forever. This prevents the same withdrawId from being used in a future legitimate withdrawal, even though the original was cancelled. Combined with the duplicate withdrawId issue, this also means that if multiple messages share a withdrawId and one is cancelled, the flag remains set.

**Recommendation:**  
In the `deleteWithdrawMessage(WithdrawMessage calldata message)` overload, add:
```solidity
withdrawMsgIdProcessed[message.withdrawId] = false;
```
For the hash-only overload, consider storing a reverse mapping from messageHash to withdrawId, or only support deletion by full message.

## High: Unchecked Return Value from Low-Level Call

**File:** `CanonicalBridge.sol`  
**Function:** `deposit()` (lines 137-154)

**Root Cause:**  
The function uses `abi.encodeWithSignature("depositEth()")` with a low-level call instead of using the typed `ITreasury` interface. While the return value is checked, this approach is fragile and gas-inefficient.

**Impact:**  
If the Treasury contract is upgraded and `depositEth()` signature changes, or if the call data is malformed, the function selector might not match, potentially calling a fallback function or failing silently. This could lead to loss of deposited funds or denial of service.

**Recommendation:**  
Replace line 148 with:
```solidity
ITreasury(TREASURY).depositEth{value: amountWei}();
```

## Medium: Constructor Doesn't Validate Treasury Address

**File:** `CanonicalBridge.sol`  
**Function:** `constructor()` (lines 84-98)

**Root Cause:**  
The constructor accepts `treasuryAddress` parameter but doesn't validate that it's a non-zero address or a valid contract.

**Impact:**  
If deployed with `treasuryAddress = address(0)` or an invalid address, the bridge would be permanently broken since `TREASURY` is immutable. All deposits would fail, and the bridge would need to be redeployed.

**Recommendation:**  
Add validation in the constructor:
```solidity
if (treasuryAddress == NULL_ADDRESS) revert ZeroAddress();
if (treasuryAddress.code.length == 0) revert NotContract();
```

## Medium: Constructor Doesn't Validate Owner Address

**File:** `CanonicalBridge.sol`  
**Function:** `constructor()` (lines 84-98)

**Root Cause:**  
The constructor doesn't validate that `owner` is a non-zero address before granting it all administrative roles.

**Impact:**  
If deployed with `owner = address(0)`, all administrative roles would be assigned to the zero address, making the contract unmanageable. Since address(0) cannot execute transactions, administrative functions would be permanently inaccessible.

**Recommendation:**  
Add validation:
```solidity
if (owner == NULL_ADDRESS) revert ZeroAddress();
```

## Medium: Upgrader Grants Permanent Admin Role to Caller

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade()` (lines 129-130)

**Root Cause:**  
The upgrader grants `DEFAULT_ADMIN_ROLE` to `msg.sender` with only a comment stating "REVOKE manually if caller is not an authoritative multisig." This relies on manual intervention rather than automatic cleanup.

**Impact:**  
If the caller forgets to manually revoke this role, an unauthorized address could retain permanent administrative control over both the Treasury and CanonicalBridge, allowing them to pause operations, modify settings, or manipulate access control.

**Recommendation:**  
Either remove this grant entirely (relying on other assigned admins), or add an automated revocation step at the end of `executeUpgrade()`, or emit a prominent warning event to remind operators to revoke the role.

## Medium: Fee Can Equal Full Amount

**File:** `CanonicalBridge.sol`  
**Function:** `validWithdrawMessage` modifier (lines 64-81)

**Root Cause:**  
The validation checks `message.feeWei > message.amountWei` but allows `message.feeWei == message.amountWei`. When equal, the recipient receives zero (since `amountWei - feeWei = 0`) and the fee receiver gets the entire amount.

**Impact:**  
A malicious or compromised WITHDRAW_AUTHORITY could authorize withdrawals where the entire amount goes to a colluding fee receiver and the legitimate recipient gets nothing, effectively stealing funds.

**Recommendation:**  
Change line 77 to prevent fees from equaling the full amount:
```solidity
if (message.feeWei >= message.amountWei) {
    revert CanonicalBridgeTransactionRejected(message.withdrawId, "message.fee must be less than message.amount");
}
```

## Medium: emergencyWithdraw Could Lock Funds

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw()` (lines 133-145)

**Root Cause:**  
The function sends ETH to `msg.sender` via low-level call without checking if the recipient can receive ETH. If `msg.sender` is a contract without a `receive()` or `fallback()` function, the transfer fails and the emergency withdrawal cannot be completed.

**Impact:**  
In an emergency scenario where the EMERGENCY_ROLE is held by a contract (e.g., a multisig or governance contract) that cannot receive ETH, the emergency withdrawal mechanism becomes unusable, potentially leaving funds locked even when administrators are trying to rescue them.

**Recommendation:**  
Either document that EMERGENCY_ROLE should only be granted to EOAs or contracts with receive functions, or implement a pull-over-push pattern where funds are marked for withdrawal and can be claimed separately.

## Low: Same Address Can Be Recipient and Fee Receiver

**File:** `Treasury.sol`  
**Function:** `withdrawEth()` (lines 106-129)

**Root Cause:**  
The function validates that both `to` and `feeReceiver` are non-zero addresses but doesn't prevent them from being the same address.

**Impact:**  
If `to == feeReceiver`, the same address receives two separate transfers. While this may be intentional (user pays their own fee), it's inefficient and could cause confusion in accounting or trigger unexpected behavior in recipient contracts that track call counts.

**Recommendation:**  
Consider adding a check:
```solidity
if (to == feeReceiver && feeWei > 0) revert InvalidConfiguration();
```
Or document this as acceptable behavior.

## Low: Unreachable Error Code in claimWithdrawal()

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal()` (lines 210-232)

**Root Cause:**  
Line 229 checks `if (!success) revert WithdrawFailed()`, but `Treasury.withdrawEth()` never returns `false` - it either returns `true` or reverts with `TreasuryTransferFailed` or `InsufficientFunds`.

**Impact:**  
The error `WithdrawFailed()` can never be triggered, making the code misleading and potentially confusing for auditors or developers. The unreachable code adds unnecessary gas costs.

**Recommendation:**  
Remove the success check and change the call to:
```solidity
ITreasury(TREASURY).withdrawEth(
    message.destination,
    message.amountWei,
    message.feeReceiver,
    message.feeWei
);
startTime[messageHash] = NEVER;
```

## Low: Array Length Not Validated in authorizeWithdraws()

**File:** `CanonicalBridge.sol`  
**Function:** `authorizeWithdraws()` (lines 158-169)

**Root Cause:**  
The function iterates over an unbounded array without checking its length, potentially consuming excessive gas.

**Impact:**  
While restricted to WITHDRAW_AUTHORITY_ROLE, a very large array could exceed the block gas limit, causing the transaction to fail and preventing batch authorization of withdrawals. This could delay withdrawal processing during high-volume periods.

**Recommendation:**  
Add a maximum batch size check:
```solidity
if (messages.length > MAX_BATCH_SIZE) revert BatchTooLarge();
```

## Informational: Permissionless Withdrawal Claiming

**File:** `CanonicalBridge.sol`  
**Function:** `claimWithdrawal()` (lines 210-232)

**Root Cause:**  
Anyone can call `claimWithdrawal()` for any authorized withdrawal - there is no restriction that only the recipient can claim.

**Impact:**  
While funds still go to the intended `message.destination`, this allows front-running where someone else claims the withdrawal before the intended recipient. This could be problematic if the recipient is a contract expecting to claim the withdrawal as part of a specific transaction flow.

**Recommendation:**  
This appears to be intentional design to support relayers. Document this behavior clearly and consider whether access should be restricted to either the recipient or addresses with a specific RELAYER_ROLE.

## Informational: Fraud Window Uses block.timestamp

**File:** `CanonicalBridge.sol`  
**Function:** `_authorizeWithdraw()` (line 194)

**Root Cause:**  
The fraud window calculation uses `block.timestamp` which can be manipulated by miners within a ~15 second range.

**Impact:**  
Miners could slightly accelerate or delay when withdrawals become claimable. However, with a minimum fraud window of 1 day (86,400 seconds), a 15-second manipulation is negligible (<0.02%).

**Recommendation:**  
This is acceptable given the long fraud window duration. Document that the fraud window is approximate and subject to minor timestamp variance.

## Informational: No Reverse Lookup for Message Hash to withdrawId

**File:** `CanonicalBridge.sol`  
**Storage:** State variables

**Root Cause:**  
The contract stores `startTime` by `messageHash` and `withdrawMsgIdProcessed` by `withdrawId`, but no mapping from `messageHash` to `withdrawId` exists.

**Impact:**  
The `deleteWithdrawMessage(bytes32 messageHash)` function cannot clear the `withdrawMsgIdProcessed` flag because it doesn't know which `withdrawId` corresponds to the hash. This limits the ability to fully clean up state when canceling withdrawals.

**Recommendation:**  
Add a mapping:
```solidity
mapping(bytes32 messageHash => uint64 withdrawId) public messageHashToWithdrawId;
```
Set it during authorization and use it during deletion.

## Informational: Upgrader Role Verification Could Be More Robust

**File:** `Upgrader0to1.sol`  
**Function:** `executeUpgrade()` (lines 158-165)

**Root Cause:**  
The upgrader revokes its own roles without verifying the revocations succeeded. While they should succeed since the upgrader just granted itself these roles, explicit verification would be more robust.

**Impact:**  
If a revocation unexpectedly fails due to a bug in AccessControl, the upgrader contract could retain administrative privileges. While unlikely, this violates the principle of least privilege.

**Recommendation:**  
Add verification after revocations:
```solidity
if (AccessControl(newCanonicalBridge).hasRole(DEFAULT_ADMIN_ROLE, address(this))) {
    revert UpgraderStillHasRole();
}
```

## Informational: Treasury Reinitialize Could Be Called by Anyone

**File:** `Treasury.sol`  
**Function:** `reinitialize()` (lines 71-91)

**Root Cause:**  
The `reinitialize()` function has no access control - anyone can call it during the reinitialization window.

**Impact:**  
The `reinitializer(2)` modifier ensures it can only be called once, during version 2 initialization. However, if called by an unauthorized party before the intended upgrader calls it, the wrong address (msg.sender) would receive DEFAULT_ADMIN_ROLE. This could frontrun the legitimate upgrade.

**Recommendation:**  
Add access control or call it atomically with the upgrade via `upgradeToAndCall` (which is already done in Upgrader0to1.sol line 115-118), and document that reinitialize should never be called directly.

## Informational: Integer Division Could Lose Precision

**File:** `CanonicalBridge.sol`  
**Function:** `deposit()` (line 152)

**Root Cause:**  
The conversion `amountGwei = amountWei / WEI_PER_LAMPORT` uses integer division.

**Impact:**  
While the `validDepositAmount` modifier ensures deposits are exact multiples of `WEI_PER_LAMPORT` (line 58), preventing precision loss, the use of integer division without this context could be confusing.

**Recommendation:**  
Add a comment explaining that precision is preserved by the validation check, or use an assertion:
```solidity
uint256 amountGwei = amountWei / WEI_PER_LAMPORT;
assert(amountGwei * WEI_PER_LAMPORT == amountWei); // Validated by modifier
```

## Informational: Missing Events for Administrative Actions

**File:** `CanonicalBridge.sol`  
**Functions:** `pause()`, `unpause()` (lines 275-283)

**Root Cause:**  
While OpenZeppelin's Pausable emits `Paused` and `Unpaused` events, there are no additional events indicating which role triggered these actions or why.

**Impact:**  
Monitoring and forensic analysis of pause/unpause actions is more difficult without knowing the full context of who paused and under what circumstances.

**Recommendation:**  
Consider emitting additional events with context:
```solidity
event BridgePaused(address indexed by, bytes32 indexed role);
event BridgeUnpaused(address indexed by, bytes32 indexed role);
```
