## Critical: Predictable nonce generation allows replay and manipulation

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `generateRandomNonce()` (line 257)
- **Root cause:** The nonce is derived from `keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))`. `block.timestamp`, `block.coinbase`, and `blockhash` are all influenceable or predictable by validators/miners. The 64-bit truncation (`uint64($.lastNonce)`) further reduces entropy, making collisions likely.
- **Impact:** Attackers can predict or manipulate nonces, enabling replay attacks (`receiveNonces`) or nonce-collision abuses (`sendNonces`).
- **Fix:** Use a strong, unpredictable entropy source such as `Chainlink VRF` or an off-chain oracle. At minimum, include `msg.sender`, `block.prevrandao`, and an incrementing counter, and use the full 256-bit output.

## Critical: Unvalidated external call to arbitrary module allows full execution hijack

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** `message_` is passed directly to `module.call(message_)` (line 215) without encoding or validation. A malicious or misconfigured module can execute arbitrary code in the context of the mailbox, and since `nonReentrant` is on the mailbox (not the module), reentrancy through the module is possible.
- **Impact:** A compromised module can drain mailbox ether (it's `payable`), manipulate `receiveNonces`, or reenter to replay messages.
- **Fix:** Restrict `message_` to a known ABI-encoded format (e.g., `(bytes4 selector, ...)`), validate selectors against a whitelist, and consider using `call` with strict gas limits or low-level checks.

## Critical: `sendMessage` ignores `chainId_` parameter, breaking cross-chain routing

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `sendMessage()` (line 225)
- **Root cause:** The function accepts `bytes memory` (first argument) as `chainId_` per interface `IMailbox`, but never uses it. Instead it always emits `encodeChainId($.eclipseChainId)` (line 244). A caller expecting to target a different chain will have the message misrouted.
- **Impact:** Cross-chain messages can be misdelivered, causing loss of funds or state corruption on the target rollup.
- **Fix:** Validate `chainId_` against allowed chain IDs and include it in the emitted event; reject unexpected chain IDs.

## High: `EmergencyWithdraw` allows owner to withdraw arbitrary amounts without balance check enforcement

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `emergencyWithdraw()` (line 63)
- **Root cause:** `require(address(this).balance >= amount, ...)` checks balance, but there is no limit on `amount`. A malicious owner (or compromised owner key) can drain the entire treasury in one transaction.
- **Impact:** Total loss of bridged ether held in treasury.
- **Fix:** Add a time-lock or multi-sig requirement for large withdrawals, and enforce a maximum withdrawal cap per call.

## High: `receive()` allows unauthorized ether deposit if `etherBridgeAddress` is uninitialized

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `receive()` (line 83)
- **Root cause:** The modifier `whenNotPaused` and `require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), ...)` depend on `StorageV1`. Before initialization (`etherBridgeAddress` is zero), an attacker could call `initialize` with a malicious `etherBridgeAddress` and then deposit, or if initialization is skipped, the zero check allows anyone (since `msg.sender == address(0)` is false for normal callers, but the logic relies on initialized storage).
- **Impact:** Potential unauthorized ether lock-up or deposit bypass if initialization is manipulated.
- **Fix:** Ensure initialization is strictly enforced before any `receive` or external interaction; add `initialized` checks to the receive function.

## High: `EtherBridge.deposit` forwards ether without verifying treasury is callable/valid

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** `deposit()` (line 92)
- **Root cause:** `payable(address($.treasuryProxy)).call{value: amountWei}("")` sends ether to the treasury proxy address without confirming the target contract accepts ether (e.g., no `receive` or `fallback`). If the treasury address is wrong or a non-payable contract, ether could be permanently lost.
- **Impact:** Loss of user deposits.
- **Fix:** Verify `treasuryProxy` implements `ITreasury` and has a payable fallback/receive, or use a safe transfer pattern with balance verification.

## High: `Mailbox.receiveMessage` does not validate `message_` format before external call

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** `message_` is decoded only in the external module call. There is no length check or format validation before `module.call(message_)`. A malicious module could receive arbitrary call data and execute unexpected functions.
- **Impact:** Module compromise leading to cross-chain state corruption or fund loss.
- **Fix:** Require `message_` to match a strict ABI-encoded schema (e.g., fixed-length selector + arguments) and validate before calling.

## Medium: `Mailbox.sendMessage` does not prevent nonce reuse across different senders

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `sendMessage()` (line 225)
- **Root cause:** `sendNonces` is a global mapping (`mapping(uint64 => bool)`). If two different modules generate the same nonce (likely due to predictable generator), one will revert (`Nonce collision`), but the mapping does not tie nonce to sender/module. This allows denial-of-service for legitimate senders.
- **Impact:** Message sending can be blocked by nonce collision attacks.
- **Fix:** Compose nonce with sender/module ID (e.g., `keccak256(abi.encode(msg.sender, nonce))`) or maintain per-sender nonce mappings.

## Medium: `Mailbox.receiveMessage` does not tie nonce to sender, enabling replay from other senders

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** `receiveNonces[secParam.nonce]` is global. A nonce used by one sender can be replayed by another sender, causing `require` failure but not identifying the attacker. More importantly, if a nonce is reused intentionally, it only prevents replay globally rather than per-sender.
- **Impact:** Potential replay or denial of service; unclear security boundary.
- **Fix:** Store `receiveNonces` as `mapping(bytes32 => bool)` combining `bytes32(sender_)` and `nonce`.

## Medium: `generateRandomNonce` uses `blockhash(block.number - 1)` which is zero for recent blocks

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `generateRandomNonce()` (line 257)
- **Root cause:** For the most recent block (or within 256 blocks), `blockhash` can return `0` if the block is too recent or unavailable. This reduces entropy and makes nonce collisions more likely.
- **Impact:** Predictable nonces and potential replay/collision.
- **Fix:** Use `block.prevrandao` (post-merge) instead of `blockhash`, and ensure entropy does not collapse to zero.

## Medium: `CommonContainer.bytesLengthEq32` does not enforce 32-byte fixed-size encoding for chain IDs

- **File:** `smart-contracts/src/v1/CommonContainer.sol`
- **Function:** `bytesLengthEq32()` (line 64)
- **Root cause:** It only checks length == 32, but `decodeChainId` expects a `bytes32`. Any 32-byte payload passes, allowing malformed chain IDs to propagate.
- **Impact:** Potential chain ID confusion in `Mailbox.receiveMessage` or `sendMessage`, leading to misrouted messages.
- **Fix:** Validate that the bytes represent an expected chain ID format (e.g., non-zero, matches known IDs) before use.

## Medium: `Mailbox` module role not revoked on module removal for non-default roles

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `removeModule()` (line 167)
- **Root cause:** `removeModule` only revokes `MODULE_ROLE`. If additional roles were granted to the module (e.g., custom roles), they remain active.
- **Impact:** Removed module retains access through leftover roles.
- **Fix:** Ensure all roles granted to `module` are revoked in `removeModule`, or document and enforce a single-role policy.

## Low: `Treasury.receive()` does not emit event if sender is owner but no ether is sent

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `receive()` (line 83)
- **Root cause:** No `msg.value == 0` guard; a call with zero value from an authorized source will emit `TreasuryDeposit` with `0`, which could pollute event logs.
- **Impact:** Event spam, minor audit noise.
- **Fix:** Add `require(msg.value > 0, ...)` before emitting.

## Low: `EtherBridge` does not emit event if mailbox `sendMessage` succeeds but treasury call fails

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** `deposit()` (line 92)
- **Root cause:** The `Deposited` event is emitted after both calls succeed, but if the treasury call fails after mailbox succeeds, the event is never emitted, leaving an inconsistent off-chain state (message sent but no deposit event).
- **Impact:** Off-chain monitoring or indexers may miss failed deposits.
- **Fix:** Emit `Deposited` after confirming treasury receipt, or emit a separate `DepositFailed` event.

## Low: `Mailbox.addModule` does not check for duplicate module IDs before insertion

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `addModule()` (line 151)
- **Root cause:** The check `if ($.modulesById[moduleId] != address(0))` prevents overwriting, but it returns a generic revert string. There is no explicit check for zero module address before insertion.
- **Impact:** Minor, covered by `addressInitialized` modifier, but error message could be clearer.
- **Fix:** Keep current behavior; improve error messages if needed.

## Informational: `generateChainId` uses `abi.encodePacked` which can cause hash collisions

- **File:** `smart-contracts/src/v1/CommonContainer.sol`
- **Function:** `generateChainId()` (line 10)
- **Root cause:** `abi.encodePacked(string)` does not include length prefixes, making collisions possible between different strings (e.g., "ab" + "c" vs "a" + "bc").
- **Impact:** Very low practical risk for fixed chain names, but not cryptographically safe for arbitrary inputs.
- **Fix:** Use `abi.encode(string)` instead of `abi.encodePacked` to include length prefixes and eliminate ambiguity.

## Informational: `Mailbox` does not enforce `bytesInitialized` on `message_` content for non-empty messages

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** `bytesInitialized(message_)` requires `message_.length > 0`, but does not enforce minimum content length for the external call. Empty or minimal messages could trigger unexpected module behavior.
- **Impact:** Minor; depends on module implementation.
- **Fix:** Add a minimum length check (e.g., 4 bytes for function selector) if module expects ABI-encoded calls.

## Informational: `Mailbox` `sendMessage` does not validate `receiver_` before emitting

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `sendMessage()` (line 225)
- **Root cause:** `receiver_` is included directly in the event without validation. A malicious module could emit an event with an arbitrary `receiver_`, misleading off-chain listeners.
- **Impact:** Off-chain event spoofing (does not affect on-chain state).
- **Fix:** Validate `receiver_` against allowed formats or lengths before emitting.

## Informational: `EtherBridge` constant `MIN_DEPOSIT` computed from separate constants without validation

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** Constant definitions (lines 27-29)
- **Root cause:** `MIN_DEPOSIT = MIN_DEPOSIT_LAMPORTS * WEI_PER_LAMPORT` uses literal constants. There is no compile-time assertion verifying the arithmetic result.
- **Impact:** None for current values; potential error if constants are changed.
- **Fix:** Add a `require` or `assert` in `initialize` verifying `MIN_DEPOSIT` is non-zero.

## Informational: `Treasury` receives ether before confirming `etherBridgeAddress` is a contract

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `receive()` (line 83)
- **Root cause:** `msg.sender == $.etherBridgeAddress` allows any address set during initialization. If initialization is called with an externally owned account (EOA), that EOA can deposit, which may violate intended design.
- **Impact:** Minor; depends on initialization trust assumptions.
- **Fix:** In `initialize`, verify `etherBridgeAddress_` is a contract (e.g., `extcodesize > 0`) or enforce it through governance.
