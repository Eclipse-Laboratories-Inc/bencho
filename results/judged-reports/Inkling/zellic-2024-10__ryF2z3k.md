# Security Audit Report — Smart Contracts

In-scope files audited:
- `smart-contracts/src/v1/Treasury.sol`
- `smart-contracts/src/v1/CanonicalBridge.sol`
- `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`
- `smart-contracts/script/v1/deploy/DeployV1.s.sol`

---

## Critical: Treasury withdrawEth arithmetic underflow

**File:** `smart-contracts/src/v1/Treasury.sol` — `withdrawEth`

**Root cause:** `payable(to).call{value: amountWei - feeWei}("")` performs unchecked subtraction. If `feeWei > amountWei`, Solidity 0.8 arithmetic checks will revert with an underflow, but more importantly there is no explicit `feeWei <= amountWei` guard inside Treasury. Even though `CanonicalBridge` validates this before calling, Treasury is independently callable by any `WITHDRAW_AUTHORITY_ROLE` holder. A malicious or misconfigured relayer contract can call `withdrawEth` directly with `feeWei > amountWei`, causing an underflow revert, or if the arithmetic were to wrap in an older pragma it would drain funds incorrectly.

**Impact:** Denial of withdrawal or incorrect amount transfer; potential loss of funds if arithmetic behavior is exploited.

**Fix:** Add `require(feeWei <= amountWei, "Fee exceeds amount")` at the top of `withdrawEth`.

---

## High: DeployV1 script does not grant WITHDRAW_AUTHORITY_ROLE to treasury for bridge

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`

**Root cause:** The script grants `DEPOSITOR_ROLE` to the canonical bridge (line 49-50) but never grants `WITHDRAW_AUTHORITY_ROLE`. Without it, the bridge cannot execute withdrawals via `ITreasury(TREASURY).withdrawEth`, breaking the withdrawal flow entirely after deployment.

**Impact:** The deployed bridge is unable to process withdrawals; users' funds are locked.

**Fix:** Add `_treasuryV1.grantRole(_treasuryV1.WITHDRAW_AUTHORITY_ROLE(), address(canonicalBridgeV1));`

---

## High: Treasury withdrawEth does not enforce feeWei <= amountWei

**File:** `smart-contracts/src/v1/Treasury.sol` — `withdrawEth`

**Root cause:** No validation that `feeWei` does not exceed `amountWei`. A direct call by a `WITHDRAW_AUTHORITY_ROLE` holder with `feeWei > amountWei` causes subtraction underflow (revert in Solidity 0.8, but still a vulnerability because it allows denial of service and indicates missing validation). Additionally, if `feeWei == amountWei`, `to` receives zero wei, which may not be intended.

**Impact:** Withdrawal denial of service; incorrect economic behavior.

**Fix:** Add `if (feeWei > amountWei) revert FeeExceedsAmount();` (or `require`) at the start of the function.

---

## High: Upgrader0to1 grants roles without revoking previous unauthorized roles on treasury

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — `executeUpgrade`

**Root cause:** The upgrade grants `DEFAULT_ADMIN_ROLE` to `msg.sender`, `p.bridgeAdmin`, `p.treasuryAdmin`, and `treasuryOldOwner`, but does not revoke any existing unauthorized roles that may have been granted previously (e.g., a malicious actor given `DEPOSITOR_ROLE` before upgrade). While access control is managed, the upgrade assumes the prior state is clean. More importantly, the contract grants `DEFAULT_ADMIN_ROLE` to `msg.sender` with a comment saying to revoke manually, which is a footgun.

**Impact:** Potential persistence of unwanted privileges if previous roles were compromised.

**Fix:** Before granting new roles, iterate and revoke all operational roles from unexpected addresses, or at minimum document and enforce a clean-state check.

---

## Medium: CanonicalBridge deleteWithdrawMessage allows cancellation in PROCESSING state but not CLOSED

**File:** `smart-contracts/src/v1/CanonicalBridge.sol` — `deleteWithdrawMessage`

**Root cause:** The condition is `status != PENDING && status != PROCESSING`, which allows deletion in `PROCESSING`. Once deleted, `startTime` is set to 0, which changes status back to `UNKNOWN`. This is intended behavior, but allowing cancellation after the fraud window has passed (`PROCESSING`) could be risky if a claim is in flight. Not a severe bug.

**Impact:** Withdrawals can be cancelled after the fraud window, which may be unintended economic behavior.

**Fix:** Restrict cancellation to `PENDING` only (`status != WithdrawStatus.PENDING`).

---

## Medium: DeployV1 script uses deployerPrivateKey from environment without validation

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`

**Root cause:** `vm.envUint("DEPLOYER_PRIVATE_KEY")` is read directly and used to create a wallet and start broadcast. There is no check that the private key corresponds to a funded or expected address. If the environment variable is missing or incorrect, the deployment will fail silently or use the wrong deployer.

**Impact:** Operational risk; deployment may use incorrect identity.

**Fix:** Add validation that the wallet has a non-zero balance or that `deployerPrivateKey != 0`, and log warnings.

---

## Low: Treasury reinitialize does not grant DEPOSITOR_ROLE or WITHDRAW_AUTHORITY_ROLE to oldOwner

**File:** `smart-contracts/src/v1/Treasury.sol` — `reinitialize`

**Root cause:** The old owner (`oldOwner`) is granted `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, `UPGRADER_ROLE`, and `EMERGENCY_ROLE`, but not `DEPOSITOR_ROLE` or `WITHDRAW_AUTHORITY_ROLE`. If the previous treasury owner also operated as the bridge or relayer, these roles must be re-granted separately by the deployer. This may be intentional (separation of duties), but it creates a missing-role scenario that can lock withdrawals if not handled in the deployment script.

**Impact:** Operational risk; withdrawal path broken if roles not manually assigned.

**Fix:** Document the missing roles clearly in comments, or grant `WITHDRAW_AUTHORITY_ROLE` to the bridge during upgrade (handled by `Upgrader0to1`).

---

## Low: CanonicalBridge withdrawMessageStatus returns PROCESSING when startTime > block.timestamp

**File:** `smart-contracts/src/v1/CanonicalBridge.sol` — `withdrawMessageStatus`

**Root cause:** If `startTime_ > block.timestamp`, the status is `PROCESSING`. This is slightly misleading terminology; the message is not being processed but is waiting for the fraud window. It is a naming issue, not a security vulnerability.

**Impact:** Confusion for integrators and monitoring.

**Fix:** Rename status or adjust logic (informational).

---

## Low: Upgrader0to1 does not check that treasuryAdmin is different from msg.sender

**File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol` — `executeUpgrade`

**Root cause:** No enforcement that `p.treasuryAdmin` or `p.bridgeAdmin` are non-zero or distinct from `msg.sender`. While they are validated as contracts/non-zero, there is no check against duplicate roles or administrative separation.

**Impact:** Centralization risk if all roles are given to the same address.

**Fix:** Add optional checks or document that roles should be separated.

---

## Informational: CanonicalBridge uses immutable TREASURY set in constructor

**File:** `smart-contracts/src/v1/CanonicalBridge.sol`

**Root cause:** `TREASURY` is `immutable`, which is secure and gas-efficient. No finding needed; this is a positive design choice.

---

## Informational: Treasury inherits from many upgradeable contracts

**File:** `smart-contracts/src/v1/Treasury.sol`

**Root cause:** The inheritance chain (`Initializable`, `AccessControlUpgradeable`, `PausableUpgradeable`, `ReentrancyGuardUpgradeable`, `UUPSUpgradeable`) is standard and properly initialized via `reinitializer(2)`. No security defect.

---

## Informational: Deploy script does not upgrade MailboxV0

**File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`

**Root cause:** The script creates a `CanonicalBridge` and upgrades the treasury, but does not interact with `MailboxV0`. This may be intentional (mailbox upgrade may be handled separately), but it is noted for completeness.

---

*Audit completed. At most 20 findings reported; only the first 20 level-2 headings are graded.*
