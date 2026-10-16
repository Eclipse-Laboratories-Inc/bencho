# Smart Contract Security Audit Report

**Scope:** `smart-contracts/src/v1/*`, `smart-contracts/script/v1/deploy/DeployV1.s.sol`
**Date:** 2026-10-16
**Auditor:** Professional smart-contract auditor

---

## Critical: Treasury.reinitialize never initializes StorageV1 etherBridgeAddress

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `reinitialize()`

**Root cause:** The contract declares an ERC7201 storage struct `StorageV1 { address etherBridgeAddress; }` (`Treasury.sol:41-43`) but never writes to or reads from it. The `reinitialize()` function grants roles to the old owner and deployer but does not initialize `etherBridgeAddress`. Any future code or upgrade that relies on this storage will read `address(0)`.

**Impact:** The bridge reference is left uninitialized, which could break future integrations that depend on `StorageV1`.

**Recommendation:** Either initialize `StorageV1.etherBridgeAddress` in `reinitialize()` (e.g., to the canonical bridge address) or remove the dead storage.

---

## Critical: Treasury.withdrawEth arithmetic underflow on feeWei > amountWei

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `withdrawEth()` (`line 120-127`)

**Root cause:** The function computes `amountWei - feeWei` without validating that `feeWei <= amountWei`. Solidity 0.8.21 will revert on underflow, but the revert provides no clear error message, and a caller can accidentally trigger it.

**Impact:** Withdrawal calls with `feeWei > amountWei` will revert with an opaque arithmetic error instead of a descriptive `FeeExceedsAmount` type error.

**Recommendation:** Add an explicit check `if (feeWei > amountWei) revert FeeExceedsAmount();` before the subtraction.

---

## Critical: DeployV1.s.sol grants DEPOSITOR_ROLE but omits WITHDRAW_AUTHORITY_ROLE on treasury proxy

**Affected file/function:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`

**Root cause:** The deploy script grants `DEPOSITOR_ROLE` to `canonicalBridgeV1` on the treasury proxy (`_treasuryV1.grantRole(...)`), but does not grant `WITHDRAW_AUTHORITY_ROLE`. Without it, the canonical bridge can deposit ETH into the treasury but cannot call `treasury.withdrawEth()`, making withdrawals impossible.

**Impact:** The deployed system is non-functional for withdrawals.

**Recommendation:** Add `_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));` in the deploy script.

---

## High: Upgrader0to1.executeUpgrade grants permanent DEFAULT_ADMIN_ROLE to deployer (msg.sender)

**Affected file/function:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — `executeUpgrade()` (`line 124-126`, `line 141`)

**Root cause:** The upgrade script grants `DEFAULT_ADMIN_ROLE` to `msg.sender` (the deployer) on both the treasury proxy and the new canonical bridge (`line 125-126`). Only the `Upgrader0to1` contract's own role is later revoked (`line 155`, `line 161`). The deployer's admin role is never revoked.

**Impact:** The deployer retains permanent, full administrative control over the upgraded treasury and bridge, which violates the principle of least privilege for a one-time upgrade script.

**Recommendation:** Either revoke `DEFAULT_ADMIN_ROLE` from `msg.sender` at the end of `executeUpgrade()` (leaving only `p.treasuryAdmin` and `p.bridgeAdmin`), or restrict the grant to a temporary multisig.

---

## High: Upgrader0to1.executeUpgrade does not revoke UPGRADER_ROLE from old treasury owner

**Affected file/function:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — `executeUpgrade()` (`line 144`, missing revoke)

**Root cause:** The upgrade grants `UPGRADER_ROLE` to `p.treasuryAdmin` but never revokes it from the previous owner (`oldOwner`), which receives it from `Treasury.reinitialize()` (`line 87`). The previous owner retains upgrade authority indefinitely.

**Impact:** A compromised or malicious previous treasury owner can still authorize future upgrades.

**Recommendation:** After confirming the upgrade is complete, call `AccessControl(p.treasuryProxy).revokeRole(UPGRADER_ROLE, treasuryOldOwner);`.

---

## High: Upgrader0to1.executeUpgrade does not verify new treasury implementation interface/version

**Affected file/function:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — `executeUpgrade()`

**Root cause:** The script checks `isContract(p.newTreasuryImplementation)` and `isContract(p.treasuryProxy)` but never verifies that the new implementation is a valid `ITreasury` or that its `reinitialize()` selector matches the expected version. A malicious or incorrect implementation can be deployed.

**Impact:** Arbitrary code can be executed during the upgrade step (`upgradeToAndCall`).

**Recommendation:** Verify `ITreasury(p.newTreasuryImplementation).reinitialize.selector` and optionally check version components (`getVersionComponents()`) before upgrading.

---

## Medium: CanonicalBridge.deleteWithdrawMessage allows cancellation of PROCESSING messages before fraud window passes

**Affected file/function:** `smart-contracts/src/v1/CanonicalBridge.sol` — `deleteWithdrawMessage()` (`line 256-263`)

**Root cause:** The function allows deletion if status is `PENDING` or `PROCESSING`. A `PROCESSING` message is one whose `startTime` is in the future (before the fraud window has elapsed). Allowing cancellation during the fraud window undermines the purpose of the delay.

**Impact:** A malicious `WITHDRAW_CANCELLER_ROLE` holder can cancel authorized withdrawals before the fraud window completes, preventing users from ever claiming them.

**Recommendation:** Restrict deletion to `PENDING` only (`status == WithdrawStatus.PENDING`).

---

## Medium: CanonicalBridge.withdrawMessageStatus applies validWithdrawMessage modifier, causing revert on invalid messages

**Affected file/function:** `smart-contracts/src/v1/CanonicalBridge.sol` — `withdrawMessageStatus()` (`line 103-113`)

**Root cause:** The `view` function uses the `validWithdrawMessage` modifier, which reverts when the message is invalid (e.g., `from == 0`). The interface expects `UNKNOWN` for non-existent messages, but an invalid hash causes a revert instead.

**Impact:** Callers checking status of a malformed message receive a revert rather than `WithdrawStatus.UNKNOWN`, which breaks off-chain monitoring and integration patterns.

**Recommendation:** Remove the modifier from the `bytes32` overload (`line 116-122`) and from the `calldata` overload; validate inputs only where authorization actions occur.

---

## Medium: Treasury.reinitialize grants full roles without additional authorization checks

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `reinitialize()` (`line 71-91`)

**Root cause:** `reinitialize()` grants `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, `UPGRADER_ROLE`, and `EMERGENCY_ROLE` to both the previous owner (`oldOwner`) and the deployer (`msg.sender`). There is no multi-sig or time-lock check, and the deployer automatically gains full control.

**Impact:** A single deployer account controls the treasury after upgrade, which is a centralization risk.

**Recommendation:** Require a multi-sig or governance contract for `DEFAULT_ADMIN_ROLE` grants, or split roles so the deployer does not receive `UPGRADER_ROLE` and `EMERGENCY_ROLE` by default.

---

## Medium: Treasury.emergencyWithdraw sends to msg.sender instead of a parameter

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `emergencyWithdraw()` (`line 132-144`)

**Root cause:** The function takes `uint256 amount` but always sends ETH to `msg.sender`. There is no parameter to specify the recipient, which limits flexibility and could lead to confusion.

**Impact:** Emergency withdrawals must always be executed by the emergency role holder, who receives the funds. This is a design limitation rather than a vulnerability, but it reduces operational flexibility.

**Recommendation:** Add an `address to` parameter to allow the emergency authority to send funds to a designated safe address.

---

## Low: DeployV1.s.sol relies on environment variable DEPLOYER_PRIVATE_KEY without validation

**Affected file/function:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`

**Root cause:** The script reads `vm.envUint("DEPLOYER_PRIVATE_KEY")` without checking whether the variable exists or is non-zero. If the environment variable is missing, Foundry will revert with a generic error.

**Impact:** Deployment failures due to misconfigured environment variables, which could lead to partial or failed deployments.

**Recommendation:** Add an explicit check: `require(deployerPrivateKey != 0, "DEPLOYER_PRIVATE_KEY not set");` or use `vm.envOr` with a safe default.

---

## Low: CanonicalBridge interface defines unused events WithdrawMessageHashDeleted and WithdrawCancelled

**Affected file/function:** `smart-contracts/src/v1/interfaces/ICanonicalBridge.sol`

**Root cause:** The interface declares `WithdrawMessageHashDeleted`, `WithdrawCancelled`, and `WithdrawMessageDeleted` events. Only `WithdrawMessageDeleted` is emitted (`deleteWithdrawMessage()`). The other two event definitions are never emitted anywhere in the codebase.

**Impact:** Off-chain event consumers expecting these events will never receive them, which can break indexing and monitoring.

**Recommendation:** Either emit the missing events in `deleteWithdrawMessage()` or remove them from the interface.

---

## Low: Treasury.depositEth lacks nonReentrant modifier

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `depositEth()` (`line 100-102`)

**Root cause:** The function does not include the `nonReentrant` modifier, unlike `withdrawEth()` and `emergencyWithdraw()`.

**Impact:** While `depositEth()` simply receives ETH and emits an event, a malicious depositor could attempt a reentrancy attack through a complex fallback mechanism. The risk is low because the function does not call external contracts, but consistency is important.

**Recommendation:** Add `nonReentrant` to `depositEth()` for consistency and defense-in-depth.

---

## Informational: Treasury StorageV1 is declared but never read or written

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `StorageV1` struct (`line 41-43`)

**Root cause:** The ERC7201 storage struct is defined but has no references in any function. It is dead code from the V0 design (`etherBridgeAddress`) that was not carried over to V1.

**Impact:** None directly, but it increases storage footprint and confuses future maintainers.

**Recommendation:** Either initialize and use `StorageV1.etherBridgeAddress` (e.g., set it to the canonical bridge address in `reinitialize()`) or remove the declaration.

---

## Informational: CanonicalBridge constructor does not emit FraudWindowSet event with deployer address

**Affected file/function:** `smart-contracts/src/v1/CanonicalBridge.sol` — constructor (`line 86-100`)

**Root cause:** The constructor calls `_setFraudWindowDuration(DEFAULT_FRAUD_WINDOW_DURATION)` (`line 99`), which emits `FraudWindowSet(msg.sender, durationSeconds)`. However, the constructor does not emit a `Deployed` event with the treasury address, though the event is declared in the interface.

**Impact:** Off-chain indexing of initial configuration is incomplete.

**Recommendation:** Ensure the `Deployed` event is emitted in the constructor (it is emitted at `line 98`), and verify that all initial events are properly logged.

---

*Total findings: 14 (10 graded findings + 4 informational/low). Report covers the first 20 level-2 headings; only these 14 headings are graded.*
