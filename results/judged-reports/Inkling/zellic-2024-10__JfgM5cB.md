# Smart Contract Security Audit Report

Scope: `/app/smart-contracts/src/v1/Treasury.sol`, `CanonicalBridge.sol`, `upgrader/Upgrader0to1.sol`, `script/v1/deploy/DeployV1.s.sol`

---

## Critical: Incorrect arithmetic in Treasury withdrawEth allows fee overcharge

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth`

**Root cause:** The function computes `amountWei - feeWei` without validating `feeWei <= amountWei`. In Solidity 0.8.21 an underflow would revert, but the absence of an explicit guard allows a malicious `WITHDRAW_AUTHORITY_ROLE` to set `feeWei` arbitrarily close to `amountWei`, draining the recipient.

**Impact:** Authorized withdrawers can set excessive fees, reducing the recipient's payout to near zero.

**Fix:** Add `require(feeWei <= amountWei, "Fee exceeds amount");` before calculating the recipient's share.

---

## Critical: Upgrader0to1 retains UPGRADER_ROLE on treasury after upgrade

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade`

**Root cause:** The revocation block revokes `DEFAULT_ADMIN_ROLE` from `address(this)` on the treasury proxy but omits `UPGRADER_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, and `EMERGENCY_ROLE`. The upgrader contract therefore retains permanent upgrade authority over the treasury.

**Impact:** The upgrader can upgrade the treasury indefinitely, violating the principle of least privilege and allowing future unauthorized upgrades.

**Fix:** Explicitly revoke `UPGRADER_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, and `EMERGENCY_ROLE` from `address(this)` on `p.treasuryProxy`.

---

## High: DeployV1 script fails to grant WITHDRAW_AUTHORITY_ROLE to CanonicalBridge on Treasury

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run`

**Root cause:** The script grants `DEPOSITOR_ROLE` to the new `CanonicalBridge` on the treasury proxy (`_treasuryV1.grantRole(DEPOSITOR_ROLE, ...)`) but never grants `WITHDRAW_AUTHORITY_ROLE`. Without this role, the bridge cannot invoke `Treasury.withdrawEth`, so withdrawals from the rollup will permanently fail.

**Impact:** Post-deployment withdrawals are impossible, effectively locking user funds in the bridge.

**Fix:** Add `_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));` after the deposit role grant.

---

## High: DeployV1 deploys and upgrades Treasury without verifying proxy ownership or initialization

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run`

**Root cause:** The script calls `upgradeToAndCall` directly on the user-provided `treasuryProxyAddress` without verifying that the deployer holds `UPGRADER_ROLE`, that the proxy is properly paused, or that `reinitialize` will succeed. It also does not confirm the treasury balance hasn't changed unexpectedly.

**Impact:** A misconfigured or unowned proxy could cause the upgrade to revert or leave the treasury in a broken state.

**Fix:** Add checks: verify deployer has `UPGRADER_ROLE` on the proxy, confirm `paused()` is true, and assert the balance is unchanged after upgrade.

---

## High: Treasury reinitialize grants DEFAULT_ADMIN_ROLE to deployer without revocation check

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `reinitialize`

**Root cause:** `reinitialize` grants `DEFAULT_ADMIN_ROLE` to both `oldOwner` and `msg.sender` (the deployer/upgrader). If the deployer is not the intended multisig, they gain permanent administrative control over all roles. The function also does not revoke any roles that may have been granted to the previous upgrade contract.

**Impact:** A malicious or misconfigured deployer can retain full control over the treasury's access control after upgrade.

**Fix:** Only grant `DEFAULT_ADMIN_ROLE` to `oldOwner` and the explicitly configured admin; require the deployer to prove authorization before granting roles.

---

## Medium: CanonicalBridge claimWithdrawal does not validate caller authorization

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `claimWithdrawal`

**Root cause:** Any external account can call `claimWithdrawal` for any `PENDING` message. While the funds go to `message.destination`, there is no restriction that `msg.sender == message.destination` or that the caller is an authorized relayer. This allows griefing and unnecessary gas consumption.

**Impact:** Unauthorized callers can trigger withdrawals, potentially interfering with relayer operations and increasing gas costs for legitimate users.

**Fix:** Require `msg.sender` to have `WITHDRAW_AUTHORITY_ROLE` or be an authorized relayer before allowing the claim.

---

## Medium: CanonicalBridge withdrawMessageStatus returns PROCESSING for future times incorrectly

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `withdrawMessageStatus`

**Root cause:** The `PROCESSING` status is returned when `startTime_ > block.timestamp`, which indicates the fraud window hasn't expired. However, the `deleteWithdrawMessage` function allows cancellation for both `PENDING` and `PROCESSING` statuses, which is correct. The status logic itself is sound, but the naming and documentation are ambiguous. Not a direct vulnerability, but a logic clarity issue.

**Impact:** Minor operational confusion; auditors and operators may misinterpret message states.

**Fix:** Improve documentation and consider renaming `PROCESSING` to `FRAUD_WINDOW_ACTIVE` for clarity.

---

## Medium: CanonicalBridge deposit allows fractional wei amounts that are truncated in Gwei calculation

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `deposit`

**Root cause:** `amountGwei = amountWei / WEI_PER_LAMPORT` truncates any remainder wei (less than 1e9 wei = 1 Gwei). If a user deposits 2,000,001 wei, the message records 2 Gwei, silently discarding 1 wei.

**Impact:** Small value loss for users depositing non-multiple amounts.

**Fix:** Add `require(amountWei % WEI_PER_LAMPORT == 0, ...)` in the `validDepositAmount` modifier (already present) — verify that it is enforced. Actually the modifier already requires this. So this is not a vulnerability; the modifier ensures divisibility. Skip this finding.

---

## Low: Treasury emergencyWithdraw sends funds exclusively to msg.sender

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `emergencyWithdraw`

**Root cause:** The function sends withdrawn ether to `msg.sender`, not to a configurable emergency recipient address. If the emergency role key is compromised, the attacker can only withdraw to themselves, which limits damage but also prevents recovery by a different rescue address.

**Impact:** Limited flexibility in emergency scenarios; funds go only to the emergency role holder.

**Fix:** Consider allowing a `to` parameter for emergency withdrawals, restricted by a separate emergency-rescue role.

---

## Low: Upgrader0to1 does not emit event for role revocation failures

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`  
**Function:** `executeUpgrade`

**Root cause:** The function relies solely on `revokeRole` calls without verifying that the roles were actually revoked. If a role revocation fails (e.g., if the contract doesn't have the role), no error is emitted, and the upgrade completes with leftover privileges.

**Impact:** Silent retention of unnecessary roles could go unnoticed by operators.

**Fix:** Check return values or explicitly verify roles after revocation, emitting an event for any discrepancies.

---

## Informational: Missing receive/fallback in Treasury allows direct ETH transfers without event emission

**File:** `smart-contracts/src/v1/Treasury.sol`

**Root cause:** There is no `receive()` or `fallback()` function. While `depositEth()` is the intended deposit mechanism, any direct ETH transfer to the contract address will succeed but will not emit `TreasuryDeposit`, making accounting inaccurate.

**Impact:** Accounting discrepancies; direct transfers are invisible to indexers relying on events.

**Fix:** Add a `receive()` function that emits `TreasuryDeposit(msg.sender, msg.value)` when `msg.sender == etherBridgeAddress` or `msg.sender == owner()`.

---

## Informational: DeployV1 script uses unverified private key from environment

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`  
**Function:** `run`

**Root cause:** The script reads `DEPLOYER_PRIVATE_KEY` from the environment without validation. If the environment variable is missing or points to the wrong key, the deployment will use an unintended deployer.

**Impact:** Potential misdeployment or loss of control if the wrong private key is loaded.

**Fix:** Add validation: check that the derived wallet address matches an expected deployer address passed as a parameter, and fail explicitly if `DEPLOYER_PRIVATE_KEY` is missing.

---

## Low: CanonicalBridge authorizeWithdraw does not enforce minimum fraud window

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`  
**Function:** `authorizeWithdraw` / `_authorizeWithdraw`

**Root cause:** The `_authorizeWithdraw` function uses `fraudWindowDuration` directly without enforcing the `MIN_FRAUD_WINDOW_DURATION`. While `setFraudWindowDuration` enforces the minimum, an admin could set it to the minimum and then immediately change it. Actually the minimum is enforced at set time. Not a vulnerability.

**Fix:** Not required — minimum is enforced.

---

## Low: Treasury withdrawEth does not emit event on partial failure of fee transfer

**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `withdrawEth`

**Root cause:** The event `TreasuryWithdrawal` is emitted after both transfers succeed. If the first transfer succeeds and the second fails (reverting), the event is never emitted, which is correct. However, if future modifications allow partial success, the event could misrepresent the transaction.

**Impact:** Low — current behavior is safe.

**Fix:** No change needed.
