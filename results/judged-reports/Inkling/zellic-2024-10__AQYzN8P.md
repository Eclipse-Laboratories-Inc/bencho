## Critical: Treasury `withdrawEth` allows fee extraction exceeding withdrawal amount

- **File:** `smart-contracts/src/v1/Treasury.sol`, `withdrawEth`
- **Root cause:** There is no validation that `feeWei <= amountWei`. Although `CanonicalBridge` checks `feeWei > amountWei` in its modifier, `Treasury.withdrawEth` is public and callable directly by any `WITHDRAW_AUTHORITY_ROLE` holder. If `feeWei > amountWei`, Solidity 0.8 arithmetic underflows on `amountWei - feeWei`, causing a revert. More importantly, if `feeWei == amountWei`, the recipient (`to`) receives zero wei while the full `amountWei` is deducted from the treasury and sent entirely to `feeReceiver`.
- **Impact:** A malicious or buggy withdrawal authority can drain the treasury by setting `feeWei = amountWei`, sending all withdrawn value to their own fee receiver and nothing to the intended recipient.
- **Fix:** Add `require(feeWei <= amountWei, "Fee exceeds amount");` in `withdrawEth`.

## Critical: `Upgrader0to1.executeUpgrade` does not revoke old bridge roles from treasury

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, `executeUpgrade`
- **Root cause:** After deploying the new `CanonicalBridge`, the function grants `DEPOSITOR_ROLE` and `WITHDRAW_AUTHORITY_ROLE` to the new bridge on the treasury proxy (lines 129-130), but never revokes these roles from `p.oldEtherbridgeAddress`. If the old `EtherBridgeV0` had previously been granted these roles (e.g., during initialization or a prior upgrade), it retains them indefinitely.
- **Impact:** The deprecated old bridge contract retains full deposit and withdrawal authority over the treasury, allowing potential unauthorized withdrawals or deposits after the upgrade is complete.
- **Fix:** After granting roles to the new bridge, explicitly revoke `DEPOSITOR_ROLE` and `WITHDRAW_AUTHORITY_ROLE` from `p.oldEtherbridgeAddress` on the treasury proxy.

## High: `DeployV1.s.sol` bypasses `Upgrader0to1` safeguards and skips critical role revocation

- **File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`, `run`
- **Root cause:** The deployment script manually deploys `CanonicalBridge` and `Treasury`, then calls `upgradeToAndCall` directly on the treasury proxy without using `Upgrader0to1.executeUpgrade`. This skips: (1) verification that both contracts are paused, (2) proper ownership transfer (`acceptOwnership`), (3) revocation of the old bridge's authority roles, (4) verification of internal trust, and (5) revocation of temporary admin roles from the deployer.
- **Impact:** A production deployment using this script could leave the old bridge with treasury authority, miss role revocation steps, and fail to enforce the upgrade safeguards designed into `Upgrader0to1`.
- **Fix:** Update the deploy script to use `Upgrader0to1.executeUpgrade` with properly prepared parameters rather than manually deploying and upgrading.

## High: `Upgrader0to1.executeUpgrade` grants `DEFAULT_ADMIN_ROLE` to arbitrary `msg.sender` without verification

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, `executeUpgrade`
- **Root cause:** Line 125 grants `DEFAULT_ADMIN_ROLE` to `msg.sender`. The only access control is `onlyUpgrader`. If the `UPGRADER_ROLE` is compromised or assigned to an attacker, the attacker can call `executeUpgrade` and receive admin roles on both the treasury and the new canonical bridge, enabling full control.
- **Impact:** A compromised `UPGRADER_ROLE` leads to complete takeover of both contracts because the attacker receives `DEFAULT_ADMIN_ROLE` automatically.
- **Fix:** Require `msg.sender` to be an authorized multisig or admin address (e.g., `p.bridgeAdmin` or `p.treasuryAdmin`) rather than arbitrarily granting admin to any `UPGRADER_ROLE` holder.

## High: `CanonicalBridge.deposit` forwards ETH with encoded selector without verifying target contract interface

- **File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `deposit`
- **Root cause:** The deposit uses `.call{value: amountWei}(abi.encodeWithSignature("depositEth()"))` to the immutable `TREASURY` address. There is no interface check or `require` verifying that the target contract actually implements `ITreasury` or that the call consumes the expected amount. While the `success` boolean is checked, a malicious treasury contract could return true without actually storing the deposit properly.
- **Impact:** If `TREASURY` is misconfigured or points to a malicious contract that returns `true` but does not lock funds, the bridge emits a `Deposited` event and considers the deposit complete while ETH is lost or redirected.
- **Fix:** Verify `TREASURY` is a contract implementing `ITreasury` at deployment time and consider using a direct interface call (`ITreasury(TREASURY).depositEth{value: amountWei}()`) instead of low-level `.call`.

## High: `Upgrader0to1.executeUpgrade` does not verify new treasury implementation version or storage compatibility

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, `executeUpgrade`
- **Root cause:** The function accepts any `p.newTreasuryImplementation` address that passes the `isContract` check. There is no check that the new implementation's `getVersionComponents()` matches the expected version, that storage layouts are compatible, or that the implementation isn't a malicious contract.
- **Impact:** A malicious or buggy implementation could corrupt treasury storage, break access controls, or drain funds upon upgrade.
- **Fix:** Add checks that the new implementation reports the expected version (`MAJOR_VERSION == 2`) and optionally verify the implementation against a known hash or deployed reference.

## Medium: `Treasury.reinitialize` grants admin roles without checking previous state or authorization

- **File:** `smart-contracts/src/v1/Treasury.sol`, `reinitialize`
- **Root cause:** The function grants `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, `UPGRADER_ROLE`, and `EMERGENCY_ROLE` to both `oldOwner` (from previous `OwnableStorage`) and `msg.sender`. There is no check that `msg.sender` is authorized, that `oldOwner` is non-zero, or that roles aren't granted to unexpected addresses. The `reinitializer(2)` modifier only prevents double initialization for version 2.
- **Impact:** If the proxy is upgraded to a malicious implementation that calls `reinitialize()`, the attacker (`msg.sender`) receives admin roles. Additionally, if `oldOwner` was previously changed to an attacker, the attacker retains admin roles after upgrade.
- **Fix:** Add a `require(msg.sender == oldOwner || msg.sender == authorizedUpgrader)` check, and verify `oldOwner != address(0)`.

## Medium: `CanonicalBridge.deleteWithdrawMessage` fails to emit `WithdrawMessageHashDeleted` event

- **File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `deleteWithdrawMessage`
- **Root cause:** The interface (`ICanonicalBridge.sol`) defines both `WithdrawMessageDeleted` and `WithdrawMessageHashDeleted` events. The `deleteWithdrawMessage` function (line 262) only emits `WithdrawMessageDeleted`. The `WithdrawMessageHashDeleted` event is never emitted by any function in the contract, despite being declared in the interface.
- **Impact:** Off-chain indexers or listeners expecting `WithdrawMessageHashDeleted` will miss cancellation events, leading to incorrect state tracking. While not directly exploitable, it breaks contract interface guarantees.
- **Fix:** Emit `WithdrawMessageHashDeleted(msg.sender, messageHash)` in `deleteWithdrawMessage`.

## Medium: `Treasury.withdrawEth` sends ETH before emitting the event

- **File:** `smart-contracts/src/v1/Treasury.sol`, `withdrawEth`
- **Root cause:** The external ETH transfers (`call`) occur before the `emit TreasuryWithdrawal` event. If either `.call` reverts (though `nonReentrant` protects), the event would not be emitted. More importantly, the event emission order violates the checks-effects-interactions pattern relative to event logging.
- **Impact:** If the external call to `feeReceiver` reverts, the entire transaction reverts (good). However, the event is emitted after the interaction, which is acceptable but less ideal. The real issue is that if `success` is true for `to` but false for `feeReceiver`, the event isn't emitted and the entire transaction reverts, which is safe. Not critical.
- **Fix:** Move the event emission before the external calls to follow checks-effects-interactions strictly, or keep as-is since it doesn't create an exploit.

## Medium: `CanonicalBridge.authorizeWithdraws` allows empty message arrays

- **File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `authorizeWithdraws`
- **Root cause:** The function iterates over `messages` without checking `messages.length > 0`. Passing an empty array succeeds without any effect.
- **Impact:** Wasted gas and potential confusion, but not a security vulnerability.
- **Fix:** Add `require(messages.length > 0, "Empty messages array");`.

## Medium: `Upgrader0to1.executeUpgrade` does not revoke `EMERGENCY_ROLE` from deployer/contract on new bridge

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, `executeUpgrade`
- **Root cause:** The revocation loop (lines 155-161) revokes `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `STARTER_ROLE`, `WITHDRAW_AUTHORITY_ROLE`, `WITHDRAW_CANCELLER_ROLE`, and `FRAUD_WINDOW_SETTER_ROLE` from `address(this)` on `newCanonicalBridge`, but does not revoke `EMERGENCY_ROLE`. If the deployer or upgrader contract temporarily receives `EMERGENCY_ROLE`, it retains it.
- **Impact:** If `address(this)` was granted `EMERGENCY_ROLE` (it isn't directly, but through temporary admin roles it could request it), the upgrader contract retains emergency withdrawal authority over the new canonical bridge after the upgrade.
- **Fix:** Ensure `EMERGENCY_ROLE` is not granted to `address(this)` during upgrade, and add explicit revocation if needed.

## Medium: `DeployV1.s.sol` uses `vm.createWallet` with private key from environment without validation

- **File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`, `run`
- **Root cause:** The script reads `DEPLOYER_PRIVATE_KEY` directly from `vm.envUint` and creates a wallet. There is no validation that the key corresponds to an authorized deployer, that the address derived from it is non-zero, or that it isn't the zero/private key.
- **Impact:** If the environment variable is misconfigured (e.g., empty, zero, or attacker-controlled), the script could deploy contracts from an unintended or compromised key.
- **Fix:** Add validation: `require(deployerPrivateKey != 0, "Invalid deployer key");` and optionally verify the derived address against an allowed deployer list.

## Low: `CanonicalBridge.withdrawMessageStatus` applies `validWithdrawMessage` modifier to a view function

- **File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `withdrawMessageStatus`
- **Root cause:** The `validWithdrawMessage` modifier performs multiple `revert` checks. Applying it to a view function means that querying the status of an invalid message will revert instead of returning `WithdrawStatus.UNKNOWN`.
- **Impact:** Off-chain callers or contracts that try to query status for malformed messages will receive a revert rather than a graceful `UNKNOWN` response, which may break integrations.
- **Fix:** Remove the `validWithdrawMessage` modifier from the view overload of `withdrawMessageStatus`, or create a separate internal validation path for view queries.

## Low: `Treasury` lacks a `receive()` or `fallback()` function

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Root cause:** The contract does not implement `receive()` or `fallback()`. Any direct ETH transfer (e.g., `selfdestruct` push or `.send`/`.transfer`) to the treasury will revert.
- **Impact:** While this prevents accidental direct deposits, it also prevents recovery of ETH sent directly or via `selfdestruct`, which could lead to permanently locked funds. The `depositEth()` function requires the caller to have `DEPOSITOR_ROLE`, which excludes direct transfers.
- **Fix:** Add a `receive() external payable` function that emits `TreasuryDeposit` if appropriate, or explicitly document that direct transfers are not supported.

## Low: `Upgrader0to1` uses `extcodesize` check which is vulnerable to constructor-time calls

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, `_isContract`
- **Root cause:** The `_isContract` function uses `extcodesize` to verify an address is a contract. This check can be bypassed during a contract's constructor when called externally (before deployment completes), because `extcodesize` returns 0 during the constructor execution.
- **Impact:** If `executeUpgrade` is called in a complex transaction where one of the parameter addresses is being deployed in the same transaction, the contract check could incorrectly pass for a non-contract address.
- **Fix:** Add an additional check such as `c.codehash != 0` or verify contracts through a trusted registry rather than relying solely on `extcodesize`.

## Informational: `Upgrader0to1` constructor grants `UPGRADER_ROLE` and `DEFAULT_ADMIN_ROLE` without initialization

- **File:** `smart-contracts/src/v1/upgrader/Upgrader0to1.sol`, constructor
- **Root cause:** The constructor grants `UPGRADER_ROLE` and `DEFAULT_ADMIN_ROLE` to `msg.sender`. There is no `initializer` modifier or initialization function, meaning the contract cannot be deployed via proxy and the roles are fixed at deployment time.
- **Impact:** The deployer of `Upgrader0to1` permanently holds admin and upgrader roles unless revoked manually. This is acceptable for a one-time upgrade contract, but it limits flexibility and requires careful role management.
- **Fix:** Document the single-use nature of the contract and ensure roles are revoked after the upgrade completes. Consider adding an `onlyUpgrader` guard to `executeUpgrade` (already present) and ensuring `DEFAULT_ADMIN_ROLE` is revoked after successful execution.

## Informational: `CanonicalBridge` does not restrict maximum fraud window duration

- **File:** `smart-contracts/src/v1/CanonicalBridge.sol`, `setFraudWindowDuration`
- **Root cause:** While there is a `MIN_FRAUD_WINDOW_DURATION` check (1 day), there is no `MAX_FRAUD_WINDOW_DURATION` check. The `fraudWindowDuration` could be set to an extremely large value (e.g., hundreds of years).
- **Impact:** A compromised `FRAUD_WINDOW_SETTER_ROLE` could set the fraud window to an excessively large duration, effectively blocking all withdrawals indefinitely.
- **Fix:** Add a `MAX_FRAUD_WINDOW_DURATION` (e.g., 365 days) and enforce it in `setFraudWindowDuration`.

## Informational: `DeployV1.s.sol` does not emit any deployment verification events

- **File:** `smart-contracts/script/v1/deploy/DeployV1.s.sol`, `run`
- **Root cause:** The deploy script only logs to console but does not emit events or call any verification functions to confirm roles, pausing state, or contract versions.
- **Impact:** Off-chain verification of deployment is limited to console logs, making automated monitoring or auditing harder.
- **Fix:** Add explicit checks (e.g., `require(canonicalBridgeV1.paused() == false)`) and emit events or log structured data confirming all roles are assigned correctly.
