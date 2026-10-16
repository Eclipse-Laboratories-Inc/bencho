# Security Audit Report — smart-contracts/src/v1

## Critical: Treasury withdrawEth over-checks balance and blocks valid withdrawals
**File:** `Treasury.sol`, function `withdrawEth`
**Root cause:** `totalAmount = amountWei + feeWei` treats `amountWei` as net rather than gross. The contract sends `amountWei - feeWei` to `to` and `feeWei` to `feeReceiver`, so total outflow is exactly `amountWei`. The balance check demands `amountWei + feeWei`, which is too high.
**Impact:** Legitimate withdrawals that exactly match the treasury balance will revert with `InsufficientFunds`.
**Fix:** Change `uint256 totalAmount = amountWei + feeWei;` to `uint256 totalAmount = amountWei;`.

## Critical: Treasury withdrawEth sends incorrect net amount when feeWei equals amountWei
**File:** `Treasury.sol`, function `withdrawEth`
**Root cause:** If `feeWei == amountWei`, the call to `to` sends `amountWei - feeWei = 0`, but the fee receiver still gets `feeWei`. The interface intends `feeWei` to be deducted from `amountWei`, but there's no guard preventing `feeWei > amountWei` beyond the interface level. The bridge does check `feeWei > amountWei` in `validWithdrawMessage`, but a direct call to Treasury bypasses it.
**Impact:** A misconfigured or malicious authority could drain the treasury by setting `feeWei` high, sending zero to the user but full fee out.
**Fix:** Add `if (feeWei > amountWei) revert InsufficientFunds();` (or a dedicated error) inside `withdrawEth`.

## High: CanonicalBridge deposit uses low-level `.call` without restricting gas
**File:** `CanonicalBridge.sol`, function `deposit`
**Root cause:** `payable(address(TREASURY)).call{value: amountWei}(...)` forwards all available gas to the treasury. If the treasury (or a malicious replacement) has a fallback/reentrancy path, it can consume the rest of the execution.
**Impact:** Potential reentrancy or unexpected control-flow change on deposit.
**Fix:** Limit forwarded gas, or prefer a pull-over-push pattern with a dedicated deposit interface and `transfer` (though `transfer` is discouraged). At minimum document and restrict.

## High: Treasury emergencyWithdraw lacks nonReentrant
**File:** `Treasury.sol`, function `emergencyWithdraw`
**Root cause:** `emergencyWithdraw` does an external `.call` but does not apply `nonReentrant`. If the recipient is a contract with a reentrant fallback, it could call back into `emergencyWithdraw` before state updates complete.
**Impact:** Potential double-spend or state corruption on emergency withdrawals.
**Fix:** Add `nonReentrant` modifier to `emergencyWithdraw`.

## High: Upgrader0to1 does not verify new bridge version / compatibility
**File:** `Upgrader0to1.sol`, function `executeUpgrade`
**Root cause:** The upgrade deploys a new `CanonicalBridge` with the current constructor but never checks that the new implementation is a valid version or that its interface matches expectations.
**Impact:** A malicious or incompatible implementation could be deployed, breaking bridge-treasury trust.
**Fix:** Add a version/checksum verification step before deploying.

## High: CanonicalBridge `deleteWithdrawMessage` does not reset `withdrawMsgIdProcessed`
**File:** `CanonicalBridge.sol`, function `deleteWithdrawMessage(bytes32)`
**Root cause:** Deleting a withdraw message resets `startTime` to 0 but leaves `withdrawMsgIdProcessed[message.withdrawId]` as `true`. Re-authorization of the same `withdrawId` is therefore blocked even though the message is deleted.
**Impact:** Once a withdraw message is canceled, it can never be re-authorized with the same ID, which may violate intended protocol behavior.
**Fix:** Also reset `withdrawMsgIdProcessed[message.withdrawId] = false` (or delete it) when deleting the message.

## Medium: CanonicalBridge `authorizeWithdraws` allows duplicate authorization of same message
**File:** `CanonicalBridge.sol`, function `_authorizeWithdraw`
**Root cause:** The check `withdrawMessageStatus(messageHash) != WithdrawStatus.UNKNOWN` prevents duplicate messages by hash, but the mapping `withdrawMsgIdProcessed` is set to `true` without first checking whether the same `withdrawId` was already used with a different message content (e.g., same ID, different amount/destination).
**Impact:** A malicious or buggy relayer could replay a `withdrawId` with modified content if the hash is different, since only the hash is checked for uniqueness.
**Fix:** Also verify that `!withdrawMsgIdProcessed[message.withdrawId]` before authorizing.

## Medium: Treasury `reinitialize` grants roles without validating caller authority
**File:** `Treasury.sol`, function `reinitialize`
**Root cause:** `reinitialize` grants `DEFAULT_ADMIN_ROLE` and operational roles to `oldOwner` and `msg.sender` without confirming that `msg.sender` is an authorized upgrader. The contract is called via `upgradeToAndCall` by the `Upgrader0to1`, but a direct malicious call (if the proxy is exposed) could reinitialize and seize roles.
**Impact:** Unauthorized role acquisition if `reinitialize` is callable outside the intended upgrade path.
**Fix:** Add an `onlyRole` or `onlyUpgrader` check, or restrict `reinitialize` to be callable only by the upgrade mechanism.

## Medium: CanonicalBridge `deposit` does not emit recipient correctly for zero-value checks
**File:** `CanonicalBridge.sol`, modifier `bytes32Initialized`
**Root cause:** The modifier checks `if(_data == NULL_BYTES32)` but uses `bytes32(0)` as the null value. Any non-zero bytes32 passes, which is fine, but there's no length or format check for the recipient encoding. A malformed recipient could propagate off-chain errors.
**Impact:** Off-chain indexing issues or invalid rollup state.
**Fix:** Consider adding an encoding/length validation for the recipient bytes32.

## Low: CanonicalBridge `deposit` event parameter named `amountLamports` but records Gwei
**File:** `CanonicalBridge.sol`, line 153
**Root cause:** `uint256 amountGwei = amountWei / WEI_PER_LAMPORT; emit Deposited(msg.sender, recipient, amountWei, amountGwei);` The event parameter is named `amountLamports` in `ICanonicalBridge.sol` but the value emitted is Gwei.
**Impact:** Off-chain confusion and potential miscalculation of lamport amounts.
**Fix:** Either rename the event parameter or convert to lamports (`amountWei / WEI_PER_LAMPORT / 1e9`).

## Low: Treasury `withdrawEth` does not emit event on failure
**File:** `Treasury.sol`, function `withdrawEth`
**Root cause:** If either `.call` fails, the function reverts but does not emit any event describing which transfer failed.
**Impact:** Harder debugging and less transparent audit trail.
**Fix:** Emit an event before each call, or include failure details in the revert message.

## Low: CanonicalBridge `startTime` exposes `NEVER` as `type(uint256).max`
**File:** `CanonicalBridge.sol`, constant `NEVER`
**Root cause:** Using `type(uint256).max` as a sentinel is fine but may overflow in arithmetic elsewhere if accidentally used in computations.
**Impact:** Low direct impact, but increases risk of arithmetic bugs in future modifications.
**Fix:** Consider using a dedicated boolean `claimed` mapping alongside `startTime`.

## Informational: CanonicalBridge `deposit` uses `abi.encodeWithSignature` with no input validation on treasury
**File:** `CanonicalBridge.sol`, function `deposit`
**Root cause:** The call to treasury is hardcoded but there's no runtime check that `TREASURY` is a contract or that it implements the expected interface.
**Impact:** Funds could be lost if `TREASURY` points to an EOA or wrong contract.
**Fix:** Add a constructor or initialization check that verifies `TREASURY` is a contract.

## Informational: Upgrader0to1 `executeUpgrade` grants `TRUSTED_RELAYER_ROLE` without defining it in interface
**File:** `Upgrader0to1.sol`
**Root cause:** `TRUSTED_RELAYER_ROLE` is used but not declared in any interface shown (`ICanonicalBridge`).
**Impact:** Potential mismatch between upgrade script and contract roles.
**Fix:** Ensure `TRUSTED_RELAYER_ROLE` is defined and documented.

## Informational: Missing events for `deleteWithdrawMessage(bytes32)` in interface
**File:** `ICanonicalBridge.sol`
**Root cause:** The event `WithdrawCancelled` is declared but never emitted by the implementation.
**Impact:** Off-chain listeners expecting cancellation events will miss them.
**Fix:** Emit `WithdrawCancelled` (or `WithdrawMessageHashDeleted`) consistently; verify event mapping.
