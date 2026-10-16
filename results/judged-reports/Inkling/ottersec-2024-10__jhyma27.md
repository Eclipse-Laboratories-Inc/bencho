# Smart Contract Security Audit Report

## Critical: Incorrect arithmetic in Treasury withdrawEth
**File:** `src/v1/Treasury.sol`, `function withdrawEth`
**Root cause:** The balance check uses `amountWei + feeWei` (`totalAmount`), but the contract only transfers `(amountWei - feeWei)` to `to` plus `feeWei` to `feeReceiver`, which equals `amountWei`. As a result the check overestimates required balance by `feeWei`. More importantly, the intended logic is that `feeWei` is deducted from the gross `amountWei`, so total outflow is `amountWei`; the check should be `address(this).balance < amountWei`. Additionally, the `to` call sends `amountWei - feeWei`, which may underpay if `feeWei` is intended separately. Recommend aligning check with intended transfer logic (`amountWei`) and ensuring documentation matches.
**Fix:** Change `if (address(this).balance < totalAmount)` to `if (address(this).balance < amountWei)`.

## Critical: CanonicalBridge deposit uses low-level call without reentrancy guard on treasury interaction
**File:** `src/v1/CanonicalBridge.sol`, `function deposit`
**Root cause:** The deposit sends ETH to `TREASURY` via `call` inside a `nonReentrant` function, but `TREASURY` is an external address; if `TREASURY` is malicious or a reentrant contract, reentrancy on the bridge is prevented but the treasury call could trigger unexpected behavior. More importantly, there is no check that the treasury actually received the funds; it relies on the call succeeding. Recommend ensuring treasury contract validates value and emits properly.
**Fix:** Ensure `TREASURY` is a trusted contract; consider adding an event verification or requiring a receipt.

## High: Treasury withdrawEth underpays recipient when feeWei > 0
**File:** `src/v1/Treasury.sol`, `function withdrawEth`
**Root cause:** `payable(to).call{value: amountWei - feeWei}("")` deducts fee from the gross `amountWei`, but if the interface specifies `amountWei` as the amount the user should receive (with fee added), this is wrong. Based on event docs (`feeWei` is deducted from gross amount), the current deduction is actually correct for gross/fee model, but the balance check is wrong. Reported together with critical arithmetic above.
**Fix:** Align balance check and transfer amounts per design spec.

## High: Missing replay protection on withdrawMsgIdProcessed in claim flow
**File:** `src/v1/CanonicalBridge.sol`
**Root cause:** While `withdrawMsgIdProcessed` is set on authorization and `startTime` is set to `NEVER` on claim, there is no direct mapping check in `claimWithdrawal` that prevents re-claiming the same `withdrawId`. It relies solely on `startTime[messageHash]`. If the same `WithdrawMessage` is re-authorized with a different hash but same `withdrawId`, `withdrawMsgIdProcessed` blocks it, but a hash collision or changed field could bypass. Ensure duplicate `withdrawId` is blocked via mapping check in claim.
**Fix:** Add check in `claimWithdrawal`: `if (withdrawMsgIdProcessed[message.withdrawId]) revert ...`.

## High: CanonicalBridge does not enforce `feeWei` deduction consistency with treasury
**File:** `src/v1/CanonicalBridge.sol`, `claimWithdrawal`
**Root cause:** The bridge calls `ITreasury(TREASURY).withdrawEth(message.destination, message.amountWei, message.feeReceiver, message.feeWei)`. There is no check that `message.amountWei >= message.feeWei`. The `validWithdrawMessage` modifier ensures `feeWei > amountWei` is rejected, but does not prevent `feeWei == amountWei`, which would send zero to destination. This could be used to drain fees only. Recommend enforcing `feeWei < amountWei`.
**Fix:** Change check to `message.feeWei >= message.amountWei` revert.

## High: Upgrade contract does not revoke EMERGENCY_ROLE for this contract
**File:** `src/v1/upgrader/Upgrader0to1.sol`, `executeUpgrade`
**Root cause:** The upgrade revokes `PAUSER_ROLE`, `STARTER_ROLE`, `WITHDRAW_AUTHORITY_ROLE`, `WITHDRAW_CANCELLER_ROLE`, `FRAUD_WINDOW_SETTER_ROLE`, and `DEFAULT_ADMIN_ROLE` for `address(this)`, but leaves `EMERGENCY_ROLE` assigned. If the upgrader retains emergency role, it could call emergency withdraw after upgrade.
**Fix:** Revoke `EMERGENCY_ROLE` for `address(this)` after upgrade.

## Medium: CanonicalBridge `deleteWithdrawMessage` does not reset `withdrawMsgIdProcessed`
**File:** `src/v1/CanonicalBridge.sol`, `deleteWithdrawMessage`
**Root cause:** When a withdraw message is deleted, `startTime[messageHash]` is reset to 0, but `withdrawMsgIdProcessed[message.withdrawId]` remains `true`. This permanently prevents any future withdraw with the same `withdrawId`, even if the message is re-authorized with different parameters. This is a denial-of-service for that withdraw ID.
**Fix:** Reset `withdrawMsgIdProcessed[message.withdrawId] = false` in delete functions.

## Medium: Treasury reinitialize does not check `reinitializer(2)` properly for future versions
**File:** `src/v1/Treasury.sol`, `reinitialize`
**Root cause:** `reinitializer(2)` locks to version 2, which is fine, but there is no version increment mechanism. If a future upgrade needs a new initializer version, this contract must be changed. Not a critical issue but limits upgradeability.
**Fix:** Document versioning policy; not urgent.

## Medium: Missing zero-address checks for `recipient` in deposit not applied to `msg.sender`
**File:** `src/v1/CanonicalBridge.sol`
**Root cause:** The `bytes32Initialized` modifier checks recipient is not zero, but does not validate `msg.sender` is non-zero (impossible) or that treasury is non-zero. The treasury is immutable, so fine.
**Fix:** Not needed.

## Medium: Treasury `depositEth` does not enforce deposit value equals expected amount
**File:** `src/v1/Treasury.sol`, `depositEth`
**Root cause:** `depositEth` accepts any `msg.value` from the depositor role, without comparing it to an expected amount. The bridge sends exact value via call, but an authorized depositor can deposit arbitrary amounts. This is by design but could lead to reconciliation errors.
**Fix:** Not required if design allows arbitrary deposits.

## Low: `CanonicalBridge` uses `abi.encode` for hash instead of `encodePacked`
**File:** `src/v1/CanonicalBridge.sol`, `withdrawMessageHash`
**Root cause:** `abi.encode(message)` includes padding and length info, which is fine for uniqueness but may not match off-chain hashing using `encodePacked`. Ensure off-chain signer uses same encoding.
**Fix:** Document hash method clearly.

## Low: `Upgrader0to1.sol` uses `Ownable2StepUpgradeable` but does not handle pending owner correctly if step is interrupted
**File:** `src/v1/upgrader/Upgrader0to1.sol`
**Root cause:** The upgrade relies on `pendingOwner() == address(this)`. If the previous owner accepts ownership prematurely or the process is interrupted, the upgrade could fail or proceed incorrectly. Not exploitable but operational risk.
**Fix:** Ensure upgrade procedure is documented and followed.

## Informational: Unused imports in `Upgrader0to1.sol`
**File:** `src/v1/upgrader/Upgrader0to1.sol`
**Root cause:** Several standard OZ imports may be unused; clean up.
**Fix:** Remove unused imports.
