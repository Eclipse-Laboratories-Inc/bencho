# Smart Contract Audit Report — v1

## Critical: Incorrect balance check in Treasury.withdrawEth over-charges balance

- **File:** `src/v1/Treasury.sol`
- **Function:** `withdrawEth`
- **Root cause:** `uint256 totalAmount = amountWei + feeWei;` requires the treasury to hold `amountWei + feeWei`, but the contract only sends out `amountWei - feeWei` (to `to`) plus `feeWei` (to `feeReceiver`), i.e. exactly `amountWei`. The check is off by `feeWei`.
- **Impact:** A legitimate withdrawal will revert with `InsufficientFunds()` whenever the treasury balance equals the requested gross amount (`amountWei`) but is less than `amountWei + feeWei`.
- **Fix:** Change the balance check to `if (address(this).balance < amountWei) revert InsufficientFunds();`.

## High: withdrawMsgIdProcessed is never validated during authorization

- **File:** `src/v1/CanonicalBridge.sol`
- **Function:** `_authorizeWithdraw`
- **Root cause:** The mapping `withdrawMsgIdProcessed` is written on authorization (`withdrawMsgIdProcessed[message.withdrawId] = true;`) but is never read or checked. A malicious or buggy relayer could reuse the same `withdrawId` with a different payload (different `from`, `destination`, or `amountWei`), producing a different `messageHash` and bypassing the duplicate-check (`messageHash` only checks the hash).
- **Impact:** Replay / reuse of withdraw message IDs, undermining the idempotency guarantee.
- **Fix:** In `_authorizeWithdraw`, add `if (withdrawMsgIdProcessed[message.withdrawId]) revert CanonicalBridgeTransactionRejected(message.withdrawId, "Withdraw id already processed");` before recording.

## High: deleteWithdrawMessage does not reset withdrawMsgIdProcessed

- **File:** `src/v1/CanonicalBridge.sol`
- **Function:** `deleteWithdrawMessage` (both overloads)
- **Root cause:** When a withdraw message is deleted, `startTime[messageHash]` is reset to `0`, but `withdrawMsgIdProcessed[message.withdrawId]` remains `true`. If the check from the previous finding is added, this would permanently block re-use of a valid `withdrawId` even after cancellation.
- **Impact:** After fixing the previous issue, a cancelled withdraw could never be re-authorized with the same ID.
- **Fix:** In both `deleteWithdrawMessage` overloads, also set `withdrawMsgIdProcessed[message.withdrawId] = false;`.

## Medium: Treasury.reinitialize lacks direct access control

- **File:** `src/v1/Treasury.sol`
- **Function:** `reinitialize`
- **Root cause:** The function relies solely on `reinitializer(2)` to prevent replay, but has no `onlyRole` or `onlyOwner` guard. If called via a proxy upgrade by an attacker who controls the upgrade mechanism, roles could be reassigned.
- **Impact:** If the proxy upgrade path is compromised, an attacker could call `reinitialize` and seize roles.
- **Fix:** Add an access-control modifier (e.g., `onlyRole(UPGRADER_ROLE)`) to `reinitialize`, or at minimum verify the caller is the expected deployer / upgradder.

## Medium: Arithmetic bug prevents exact-balance withdrawals in Treasury

- **File:** `src/v1/Treasury.sol`
- **Function:** `withdrawEth`
- **Root cause:** As noted in the Critical finding, `totalAmount = amountWei + feeWei` causes an unnecessary revert when the contract holds exactly the gross amount.
- **Impact:** Operational failure; users cannot withdraw when the treasury balance exactly matches the gross withdrawal amount.
- **Fix:** Use `amountWei` for the balance check.

## Low: CanonicalBridge.deleteWithdrawMessage(bytes32) allows zero hash

- **File:** `src/v1/CanonicalBridge.sol`
- **Function:** `deleteWithdrawMessage(bytes32 messageHash)`
- **Root cause:** The overload does not apply the `bytes32Initialized` modifier, allowing `messageHash = bytes32(0)` to be passed. Although `withdrawMessageStatus(bytes32(0))` returns `UNKNOWN`, the status check (`PENDING` or `PROCESSING`) would revert, so the practical impact is limited.
- **Impact:** Minor inconsistency; no direct exploit.
- **Fix:** Add `bytes32Initialized(messageHash)` modifier to the overload.

## Low: Upgrader0to1 grants DEFAULT_ADMIN_ROLE to msg.sender without revocation mechanism

- **File:** `src/v1/upgrader/Upgrader0to1.sol`
- **Function:** `executeUpgrade`
- **Root cause:** Line `AccessControl(p.treasuryProxy).grantRole(DEFAULT_ADMIN_ROLE, msg.sender);` and the same for `newCanonicalBridge` gives the caller a permanent admin role. There is no documented revocation mechanism.
- **Impact:** If the upgrade is executed by a temporary operator or a compromised account, that account retains privileged access indefinitely.
- **Fix:** Document the need for manual revocation or add an automatic revocation step after successful upgrade confirmation.

## Informational: Unused roles in Upgrader0to1

- **File:** `src/v1/upgrader/Upgrader0to1.sol`
- **Root cause:** `TRUSTED_RELAYER_ROLE`, `MODULE_ROLE`, and `ADMIN_AUTHORITY_ROLE` are defined but never granted, revoked, or checked.
- **Impact:** Dead code; does not affect security directly.
- **Fix:** Remove unused role definitions or implement the intended authorization logic.
