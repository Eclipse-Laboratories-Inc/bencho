# Smart Contract Security Audit Report

Scope: `smart-contracts/src/v1/Treasury.sol`, `CanonicalBridge.sol`, `upgrader/Upgrader0to1.sol`, `script/v1/deploy/DeployV1.s.sol`

---

## Critical: Treasury missing receive/fallback for direct ETH transfers
**File:** `smart-contracts/src/v1/Treasury.sol` — contract `Treasury`
**Root cause:** The interface `ITreasury` explicitly states it assumes "a fallback function to receive ether," but the contract defines neither `receive()` nor `fallback()`.
**Impact:** Any direct ETH transfer (e.g. from a self-destructing contract or an accidental send) will revert, potentially locking or preventing expected fund flows.
**Fix:** Add `receive() external payable` (with `whenNotPaused` and proper authorization checks if needed, or at minimum `emit TreasuryDeposit(msg.sender, msg.value)` and a source check) to the contract.

---

## Critical: emergencyWithdraw lacks reentrancy guard
**File:** `smart-contracts/src/v1/Treasury.sol` — function `emergencyWithdraw`
**Root cause:** The function uses `.call{value: amount}("")` to send ETH to `msg.sender` but does not apply the `nonReentrant` modifier used on `withdrawEth`.
**Impact:** A malicious `EMERGENCY_ROLE` holder could reenter during the external call. Although no mutable state is updated after the call, the absence of the guard is a deviation from the contract's own security pattern and creates unnecessary risk.
**Fix:** Add `nonReentrant` modifier to `emergencyWithdraw`.

---

## High: CanonicalBridge constructor does not validate treasury is a contract
**File:** `smart-contracts/src/v1/CanonicalBridge.sol` — constructor
**Root cause:** `treasuryAddress` is assigned to the immutable `TREASURY` without any `isContract` or non-zero validation. The `Upgrader0to1` validates with `isContract`, but the direct constructor path (used by `DeployV1.s.sol`) does not.
**Impact:** If an EOA or invalid address is passed as treasury, all deposits will silently succeed (`.call` to EOA returns `true`) but ETH will be lost, and withdrawals via `ITreasury(TREASURY).withdrawEth(...)` will fail unrecoverably.
**Fix:** Add `_checkAddress(treasuryAddress)` and `_checkContract(treasuryAddress)` (or at minimum a zero-address check) in the constructor.

---

## High: Upgrader0to1 grants DEFAULT_ADMIN_ROLE to unverified msg.sender
**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — function `executeUpgrade`
**Root cause:** The contract grants `DEFAULT_ADMIN_ROLE` to `msg.sender` (line 125) and to `p.bridgeAdmin` without verifying that `msg.sender` is an authorized multisig or trusted entity. The code comment explicitly warns: "REVOKE manually if caller is not an authoritative multisig."
**Impact:** Any party that can call `executeUpgrade` (any `UPGRADER_ROLE` holder) can permanently assign themselves full admin authority over both the treasury proxy and the new CanonicalBridge. This creates a dangerous footgun.
**Fix:** Remove the automatic `msg.sender` grant or restrict it to a verified admin parameter (`p.treasuryAdmin` or a separate `deployerAdmin` address with explicit confirmation).

---

## Medium: Treasury.emergencyWithdraw does not enforce fee or balance consistency checks
**File:** `smart-contracts/src/v1/Treasury.sol` — function `emergencyWithdraw`
**Root cause:** The function checks `address(this).balance < amount` but does not apply any additional constraints (e.g., max withdrawal limits, rate limits, or comparison with other roles). It also lacks any logging of the recipient beyond the event.
**Impact:** A compromised `EMERGENCY_ROLE` key can drain the entire treasury in a single transaction without additional safeguards.
**Fix:** Consider adding a maximum withdrawal cap or time-delay mechanism in the contract design (or document clearly that this is an emergency-only full-drain mechanism). At minimum, document the behavior clearly.

---

## Medium: CanonicalBridge.deleteWithdrawMessage does not emit expected cancellation events
**File:** `smart-contracts/src/v1/CanonicalBridge.sol` — function `deleteWithdrawMessage`
**Root cause:** The interface defines `WithdrawCancelled` and `WithdrawMessageHashDeleted` events, but `deleteWithdrawMessage` only emits `WithdrawMessageDeleted` (line 263) and does not emit either of the cancellation events.
**Impact:** Off-chain monitors and indexers relying on the standard cancellation events will miss cancellation activity, leading to incorrect withdrawal-state tracking.
**Fix:** Emit `WithdrawCancelled(msg.sender, messageHash)` or `WithdrawMessageHashDeleted(msg.sender, messageHash)` (or both, matching interface expectations) inside `deleteWithdrawMessage`.

---

## Medium: DeployV1 script does not set fraud window or configure bridge roles
**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`
**Root cause:** The script deploys `CanonicalBridge` and upgrades the treasury but never calls `setFraudWindowDuration`, grants `DEPOSITOR_ROLE` to the bridge (it grants `DEPOSITOR_ROLE` from treasury to bridge, which is correct), and does not verify that `canonicalBridgeV1` has its admin roles configured. More importantly, the script grants `WITHDRAW_AUTHORITY_ROLE` directly to `trustedRelayerAddress`, which is fine, but does not set any fraud window duration explicitly (it relies on the constructor default of 7 days, which is fine). The bigger issue is that the script deploys a brand-new `CanonicalBridge` without any verification that `treasuryProxyAddress` points to the upgraded treasury.
**Impact:** In a misconfigured deployment, the bridge could be connected to the wrong treasury or operate with an unverified fraud window, allowing incorrect withdrawal timing.
**Fix:** Add explicit verification steps after deployment (e.g., assert `canonicalBridgeV1.TREASURY() == treasuryProxyAddress`, assert fraud window is the expected value, assert roles are set correctly) and emit a summary event or console log confirming safe configuration.

---

## Low: Treasury.reinitialize grants roles without revoking previous admin
**File:** `smart-contracts/src/v1/Treasury.sol` — function `reinitialize`
**Root cause:** `reinitialize` grants `DEFAULT_ADMIN_ROLE` to both `oldOwner` and `msg.sender`. It does not revoke `DEFAULT_ADMIN_ROLE` from any previous holder (e.g., the `Upgrader0to1` contract that called `upgradeToAndCall`). Although `executeUpgrade` revokes it afterward, any failure between `reinitialize` and the revocation step would leave the upgrader with admin rights.
**Impact:** If the upgrade process is interrupted, the `Upgrader0to1` contract retains `DEFAULT_ADMIN_ROLE` on the treasury proxy.
**Fix:** In `reinitialize`, explicitly revoke `DEFAULT_ADMIN_ROLE` from any known previous admin (e.g., the caller of `upgradeToAndCall` if it is a contract) before granting new roles. Ensure the upgrade script performs all revocations atomically.

---

## Low: CanonicalBridge.precision constant is unused
**File:** `smart-contracts/src/v1/CanonicalBridge.sol`
**Root cause:** `uint256 private constant PRECISION = 1e18;` is declared but never referenced in the contract logic.
**Impact:** Dead code increases binary size slightly and may confuse auditors or maintainers.
**Fix:** Remove the unused constant.

---

## Low: Treasury.withdrawEth transfers to `msg.sender` in emergencyWithdraw without role verification of recipient
**File:** `smart-contracts/src/v1/Treasury.sol` — function `emergencyWithdraw`
**Root cause:** `emergencyWithdraw` sends ETH to `msg.sender` (the role holder) rather than allowing a specified recipient. While this is a design choice, it means only the key holder can receive emergency funds, which limits operational flexibility (e.g., sending to a multisig or cold wallet).
**Impact:** Minor design limitation; not a direct vulnerability.
**Fix:** Document the design choice clearly or change the function signature to accept a `to` address with appropriate validation.

---

## Informational: Treasury interface comments mention fallback but implementation omits it
**File:** `smart-contracts/src/v1/interfaces/ITreasury.sol`
**Root cause:** The interface docstring says "assumes the implementation will provide a fallback function to receive ether," yet `Treasury.sol` provides none.
**Impact:** Confusion for integrators; potential integration failure.
**Fix:** Either add the fallback/receive function to `Treasury.sol` or update the interface comment to reflect the actual behavior (relying solely on `depositEth`).

---

## Informational: DeployV1 script uses `vm.createWallet` with private key from environment
**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`
**Root cause:** The script reads `DEPLOYER_PRIVATE_KEY` directly from the environment without any additional validation or sanitization.
**Impact:** Standard Foundry deployment pattern; low risk but worth noting for operational security.
**Fix:** Ensure the environment variable is set securely and that deployment logs do not leak private keys.

---

*Audit conducted on 2026-10-16. At most 20 findings reported; only the first 20 level-2 headings are graded.*
