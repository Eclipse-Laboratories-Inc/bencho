# Security Audit Report — smart-contracts/src/v1

## Critical: Incorrect balance check and underflow in Treasury.withdrawEth
**File:** `Treasury.sol` — `withdrawEth`
**Root cause:** `totalAmount` is computed as `amountWei + feeWei`, but the actual ether transferred is `amountWei - feeWei` (to recipient) plus `feeWei` (to fee receiver) = `amountWei`. This makes the balance check too strict, causing legitimate withdrawals to be wrongly rejected. Additionally, there is no `feeWei <= amountWei` guard; if `feeWei > amountWei`, `amountWei - feeWei` underflows (reverts in Solidity 0.8, but with no clear error message).
**Impact:** Withdrawals fail incorrectly; potential unexpected revert behavior for large fees.
**Fix:** Change `totalAmount` to `amountWei`. Add an explicit `require(feeWei <= amountWei, ...)` check before subtraction.

## Critical: Missing uniqueness check on withdrawId in CanonicalBridge
**File:** `CanonicalBridge.sol` — `_authorizeWithdraw`
**Root cause:** The mapping `withdrawMsgIdProcessed` is set to `true` but never read in `authorizeWithdraw` or `authorizeWithdraws`. This allows the same `withdrawId` to be reused with different message fields (different hash), defeating replay protection intended by the mapping.
**Impact:** Duplicate withdraw IDs can be authorized and claimed independently, risking replay or double-spend scenarios.
**Fix:** Before authorizing, check `if (withdrawMsgIdProcessed[message.withdrawId]) revert ...`.

## High: deleteWithdrawMessage does not clear withdrawMsgIdProcessed
**File:** `CanonicalBridge.sol` — `deleteWithdrawMessage(bytes32)` and `deleteWithdrawMessage(WithdrawMessage)`
**Root cause:** When a withdraw message is cancelled, `startTime[messageHash]` is reset but `withdrawMsgIdProcessed[message.withdrawId]` remains `true`. After cancellation, the same `withdrawId` could still not be reused if the uniqueness check is added; but currently it allows reuse. Even after fixing the uniqueness check, failing to clear the mapping would permanently block reuse of that ID after cancellation.
**Impact:** Prevents legitimate re-authorization of a cancelled withdraw with the same ID.
**Fix:** Set `withdrawMsgIdProcessed[message.withdrawId] = false;` in both delete functions.

## High: No minimum fee or fee validation beyond simple comparison in withdrawEth
**File:** `Treasury.sol` — `withdrawEth`
**Root cause:** The only fee validation is implicit via the subtraction; there is no explicit `feeWei > 0` or maximum fee check. A malicious or misconfigured authority could set a fee that consumes almost all of the gross amount, leaving the recipient with almost nothing, and the code would not reject it clearly.
**Impact:** Unexpected economic behavior; recipient receives near-zero value.
**Fix:** Add `require(feeWei > 0 && feeWei <= amountWei / 2, ...)` or similar explicit bounds based on protocol requirements.

## Medium: reinitialize grants admin roles without revoking deployer's previous authority properly
**File:** `Treasury.sol` — `reinitialize`
**Root cause:** `reinitialize` grants `DEFAULT_ADMIN_ROLE` to `msg.sender` but does not revoke it from the deployer or previous admin. If the deployer retains the role inadvertently, control could be split unexpectedly. Additionally, base upgradeable initializers (`__ReentrancyGuard_init`, `__Pausable_init`) are not explicitly re-invoked, though the default state may be acceptable.
**Impact:** Potential split authority after upgrade; unclear initialization state.
**Fix:** Revoke `DEFAULT_ADMIN_ROLE` from any previous holder if intended; explicitly initialize base modules if needed.

## Medium: CanonicalBridge.deposit uses low-level call without fallback protection
**File:** `CanonicalBridge.sol` — `deposit`
**Root cause:** Funds are forwarded via `.call{value: amountWei}(abi.encodeWithSignature("depositEth()"))`. If `TREASURY` points to a contract that lacks `depositEth` or has a malicious fallback, the call may return `true` unexpectedly (if the target has a payable fallback) or fail. The contract relies solely on `success` boolean.
**Impact:** Funds could be locked in a wrong contract or lost if the treasury is misconfigured.
**Fix:** Use the interface directly (`ITreasury(TREASURY).depositEth{value: amountWei}()`) rather than raw `call`, ensuring type-safe invocation and proper revert propagation.

## Low: Missing event emission for failed authorization attempts
**File:** `CanonicalBridge.sol` — `_authorizeWithdraw`
**Root cause:** No event is emitted when a duplicate authorization is attempted. While the revert provides information, an event would help off-chain monitoring.
**Impact:** Off-chain systems may miss repeated authorization attempts.
**Fix:** Emit an event or rely on revert logs; not critical.

## Low: withdrawMessageStatus applies validWithdrawMessage modifier to view call
**File:** `CanonicalBridge.sol` — `withdrawMessageStatus(WithdrawMessage)`
**Root cause:** The `validWithdrawMessage` modifier performs state-independent checks (non-zero fields) but is applied to a `view` function. This is unconventional and could cause unexpected revert behavior for external callers querying status of incomplete messages.
**Impact:** View queries for invalid messages revert instead of returning `UNKNOWN`.
**Fix:** Separate validation from status query; only apply validation where it is needed for state changes, or handle invalid messages gracefully in the view function.

## Low: Fraud window duration can be reduced abruptly without transition period
**File:** `CanonicalBridge.sol` — `setFraudWindowDuration`
**Root cause:** The fraud window can be changed to any value above the minimum immediately. A rapid reduction could make previously authorized withdrawals claimable much sooner than expected, reducing the security window.
**Impact:** Reduced fraud-detection time.
**Fix:** Consider enforcing a maximum change rate or requiring a delay for large reductions.

## Low: No zero-address check for TREASURY in constructor
**File:** `CanonicalBridge.sol` — constructor
**Root cause:** The constructor accepts `treasuryAddress` without validating it is non-zero. A misconfigured deployment could set the treasury to `address(0)`, making deposits permanently unrecoverable.
**Impact:** Complete loss of deposited funds if treasury is zero.
**Fix:** Add `require(treasuryAddress != address(0), ...)` in the constructor.

## Informational: Upgrader0to1 does not revoke all roles from the upgrade contract after execution
**File:** `Upgrader0to1.sol` — `executeUpgrade`
**Root cause:** Several roles assigned to `address(this)` are revoked, but any additional roles granted by future modifications may not be cleaned up. The contract relies on manual revocation.
**Impact:** Minimal direct risk if the upgrade completes correctly.
**Fix:** Ensure a comprehensive revocation list or use a self-destruct mechanism after upgrade.

## Informational: CanonicalBridge event naming inconsistency
**File:** `CanonicalBridge.sol`
**Root cause:** Some event names use "Withdraw" while others use "Withdrawl" (e.g., `WithdrawAuthorized`, `WithdrawClaimed`, `WithdrawMessageDeleted`). This inconsistency can confuse integrators.
**Fix:** Standardize naming.

## Informational: Treasury interface mentions fallback for ether bridge only but no fallback/receive implemented
**File:** `Treasury.sol`
**Root cause:** The spec mentions a fallback to receive deposits, but the contract does not implement `receive()` or `fallback()`. The `depositEth()` function must be called explicitly. This is acceptable if the bridge always uses the function selector, but it differs from the spec.
**Fix:** Either implement `receive()` with appropriate access control or update the spec.

## Low: No upper bound on deposit amount
**File:** `CanonicalBridge.sol` — `deposit`
**Root cause:** There is no maximum deposit limit. Extremely large deposits could strain the treasury or withdrawal processing.
**Impact:** Potential DoS or operational strain.
**Fix:** Consider adding a `MAX_DEPOSIT` if required by protocol design.

## Low: withdrawMessageStatus returns PROCESSING when startTime is in the future
**File:** `CanonicalBridge.sol` — `withdrawMessageStatus(bytes32)`
**Root cause:** This behavior is correct per spec, but the naming could be confusing (`PROCESSING` vs `PENDING`). Not a security issue.
**Fix:** None required; document clearly.

## Low: AccessControl roles are not rotated after upgrade
**File:** `Upgrader0to1.sol`
**Root cause:** The upgrade grants `DEFAULT_ADMIN_ROLE` to the caller but does not enforce multi-sig or time-lock for critical role assignments.
**Fix:** Consider adding a time-lock or requiring a second confirmation for role grants.
