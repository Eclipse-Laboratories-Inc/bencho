# Security Audit Report — `smart-contracts/src/v1`

## Critical: Arithmetic error in Treasury `withdrawEth` over-checks balance

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth`

The balance check computes `totalAmount = amountWei + feeWei`, but the actual ETH moved is `(amountWei - feeWei) + feeWei = amountWei`. The check requires `amountWei + feeWei` when only `amountWei` is withdrawn, so valid withdrawals with balance between `amountWei` and `amountWei + feeWei` incorrectly revert.

**Fix:** Change line 120 to `uint256 totalAmount = amountWei;`.

---

## High: Missing `nonReentrant` on `Treasury.emergencyWithdraw`

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw`

The parent contract inherits `ReentrancyGuardUpgradeable`, and `withdrawEth` uses `nonReentrant`, but `emergencyWithdraw` does not. A malicious `EMERGENCY_ROLE` contract could reenter before the event is emitted (though balance is live-checked, multiple withdrawals are possible within the same transaction if the balance allows).

**Fix:** Add `nonReentrant` modifier.

---

## High: `Treasury.withdrawEth` allows `feeWei > amountWei` (underflow)

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth`

There is no validation that `feeWei <= amountWei`. Calling with `feeWei > amountWei` causes an underflow on `amountWei - feeWei`, reverting instead of producing a clear error.

**Fix:** Add `if (feeWei > amountWei) revert FeeExceedsAmount();` (or similar).

---

## Medium: `Upgrader0to1` relies on `extcodesize` which fails during construction

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Modifier:** `isContract`

`_isContract` uses `extcodesize`. If an address points to a contract currently in its constructor, `extcodesize` returns 0, causing false negatives. An attacker could potentially exploit timing to pass a non-contract address.

**Fix:** Use `Address.isContract` from OpenZeppelin which handles this, or add an additional explicit check.

---

## Medium: `CanonicalBridge.claimWithdrawal` updates state after external call but relies on live status check

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal`

Although `startTime` is set to `NEVER` after the treasury call, the status check at the beginning (`PENDING`) is evaluated before the external call. If a malicious `destination` contract reenters `claimWithdrawal`, it could claim again before `startTime` is updated, because the status hasn't changed yet. However, since treasury sends ETH out and `nonReentrant` is missing on this function, a reentrancy is possible if the treasury's `withdrawEth` doesn't guard it (it does have `nonReentrant`). The main gap is the absence of `nonReentrant` on `claimWithdrawal` itself.

**Fix:** Add `nonReentrant` to `claimWithdrawal`.

---

## Low: `withdrawMsgIdProcessed` written but never validated

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Functions:** `_authorizeWithdraw`, `authorizeWithdraw`

The mapping `withdrawMsgIdProcessed` is set to `true` for every withdraw ID but is never checked before authorization. Duplicate `withdrawId` values can be reused with different message contents. This suggests either dead code or an incomplete authorization check.

**Fix:** Read `withdrawMsgIdProcessed` in `_authorizeWithdraw` and revert if already processed.

---

## Low: `CanonicalBridge` constructor doesn't validate `treasuryAddress`

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Constructor:** `CanonicalBridge`

The constructor assigns `TREASURY = treasuryAddress` without checking for `address(0)`. A misconfigured deployment could point the bridge at a null address, making all deposits and withdrawals fail.

**Fix:** Add `require(treasuryAddress != address(0), "Zero treasury");` in the constructor.

---

## Informational: `Treasury.reinitialize` grants roles to both old owner and deployer

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize`

Both `oldOwner` and `msg.sender` receive `DEFAULT_ADMIN_ROLE`. If the deployer is not intended to retain admin access permanently, this could lead to unexpected privilege retention. This is by design for upgrade safety but should be documented clearly.

---

## Informational: `Upgrader0to1.executeUpgrade` grants `DEFAULT_ADMIN_ROLE` to `msg.sender` without revocation

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade`

The caller receives `DEFAULT_ADMIN_ROLE` on both the new treasury proxy and the new canonical bridge. The code relies on manual revocation afterward, which introduces operational risk.

---

*Audit completed 2026-10-16. Scope: `smart-contracts/src/v1` only. At most 8 findings reported; only the first 20 level-2 headings are graded.*
