# Smart Contract Security Audit Report

**Scope:** `smart-contracts/src/v1/`  
**Contracts Audited:** Treasury.sol, Mailbox.sol, EtherBridge.sol, CommonContainer.sol  

---

## Critical: Predictable nonce generation allows replay attacks in Mailbox

**File:** `Mailbox.sol` — `generateRandomNonce()` (line 257)

**Root Cause:** The nonce is derived from `keccak256(abi.encodePacked($.lastNonce, blockhash(block.number - 1), block.timestamp, block.coinbase))`. `blockhash`, `timestamp`, and `coinbase` are all miner/manipulable or predictable within short windows. A malicious relayer or miner can pre-compute or influence nonces, defeating replay protection.

**Impact:** `sendNonces` and `receiveNonces` mappings become unreliable. An attacker can replay messages or cause nonce collisions, undermining cross-chain message integrity.

**Fix:** Replace pseudo-random generation with a strictly monotonic counter (`++nonce`) or a cryptographically secure source (e.g., `block.prevrandao` combined with an increment-only sequence) and enforce uniqueness explicitly.

---

## Critical: sendMessage ignores chainId and data parameters

**File:** `Mailbox.sol` — `sendMessage()` (line 225)

**Root Cause:** The function signature is `sendMessage(bytes memory, bytes memory receiver_, bytes memory message_, bytes memory)` — both `chainId_` and `data_` parameters are unnamed and never used. The emitted `MessageSent` uses the stored `$.eclipseChainId`, not the passed `chainId_`, and ignores any extra security data.

**Impact:** Callers cannot specify a destination chain or attach additional security params (e.g., a custom nonce or signature). The interface contract implies these parameters exist but are discarded, which can break integration with relayers that rely on them.

**Fix:** Name the parameters (`chainId_`, `data_`), validate `chainId_` against `eclipseChainId`, and encode `data_` into the emitted event or security parameter.

---

## Critical: Mailbox receiveMessage does not validate sender authorization against module mapping correctly

**File:** `Mailbox.sol` — `receiveMessage()` (line 187)

**Root Cause:** `address module = $.modulesById[bytes32(sender_)];` looks up the sender by a `bytes32` cast of `bytes memory sender_`. The `sender_` is arbitrary bytes passed by the relayer. If the mapping contains a zero entry or collision, the module check can be bypassed or misdirected.

**Impact:** A malicious relayer could craft `sender_` such that `bytes32(sender_)` maps to a legitimate module, causing arbitrary messages to be delivered to the wrong contract logic.

**Fix:** Enforce strict `bytes32` decoding with length checks, require the decoded `bytes32` to correspond exactly to a registered module ID, and reject any ambiguous or zero mappings.

---

## High: Weak nonce allows replay in receiveMessage

**File:** `Mailbox.sol` — `receiveMessage()` (line 208)

**Root Cause:** Because `generateRandomNonce()` produces weak nonces, an attacker can replay a previously received message by guessing/reusing a nonce that hasn't been recorded, or by computing a nonce that collides with an existing one.

**Impact:** Replay of cross-chain messages, potentially leading to double execution of deposits, withdrawals, or administrative actions.

**Fix:** Use a strict incrementing nonce per sender/module or a secure random value from a trusted oracle, and store all used nonces immutably.

---

## High: EtherBridge does not validate mailbox response before locking funds

**File:** `EtherBridge.sol` — `deposit()` (line 92)

**Root Cause:** The contract calls `$.mailboxProxy.sendMessage(...)` and requires `success`, but does not verify the emitted event or that the mailbox actually recorded the message. Then it immediately transfers `amountWei` to the treasury (`payable(address($.treasuryProxy)).call{value: amountWei}("")`).

**Impact:** If the mailbox fails silently or is in an unexpected state, ether is locked in the treasury without a corresponding cross-chain message, leading to lost funds or unaccounted balances.

**Fix:** After calling `sendMessage`, parse the returned result or event to confirm message storage, and only then transfer to treasury. Consider using `call` with a reentrancy guard and event validation.

---

## High: Treasury receive allows owner to deposit arbitrary amounts without event validation

**File:** `Treasury.sol` — `receive()` (line 83)

**Root Cause:** The `receive()` function allows both the `etherBridgeAddress` and the `owner()` to send ether. There is no minimum deposit check, no event for unauthorized sources, and no differentiation between bridge and owner deposits.

**Impact:** The owner could deposit arbitrary amounts and potentially manipulate treasury accounting, or a misconfigured contract could send unexpected ether that gets accepted silently.

**Fix:** Restrict `receive()` to only the `etherBridgeAddress` (remove `owner()` allowance), enforce `MIN_DEPOSIT` if applicable, and emit distinct events for different sources.

---

## High: Reentrancy guard not applied to treasury receive

**File:** `Treasury.sol` — `receive()` (line 83)

**Root Cause:** The `receive()` function is marked `whenNotPaused` but does not use `nonReentrant`. Although it performs no external calls, it updates storage (`emit` uses no state change), but if a future override or inheritance introduces external interaction, the guard is missing.

**Impact:** Potential future reentrancy vulnerability if `receive()` is overridden or if the treasury is called via a proxy with fallback behavior.

**Fix:** Add `nonReentrant` modifier to `receive()` to maintain consistency with other entry points.

---

## High: EtherBridge uses `call` for treasury deposit without reentrancy protection

**File:** `EtherBridge.sol` — `deposit()` (line 115)

**Root Cause:** `payable(address($.treasuryProxy)).call{value: amountWei}("")` performs an external call inside a function that is `nonReentrant`. However, the treasury's `receive()` does not have `nonReentrant`. If a malicious treasury implementation is set (e.g., via upgrade), it could reenter the bridge.

**Impact:** Reentrancy through a malicious or compromised treasury proxy could allow multiple deposits with a single balance or drain the bridge.

**Fix:** Ensure the treasury is immutable or validated at initialization, and enforce strict checks on the treasury address. Additionally, consider using `pull` pattern instead of `push` for treasury funding.

---

## High: Mailbox module lookup allows zero module to be used if mapping is uninitialized

**File:** `Mailbox.sol` — `receiveMessage()` (line 213)

**Root Cause:** If `$.modulesById[bytes32(sender_)]` returns `address(0)`, the function reverts with "Module does not exist." However, the check happens after nonce validation and storage update (`receiveNonces[nonce] = true`). This means a replay attempt with an invalid module still burns the nonce.

**Impact:** A malicious relayer can waste nonces from legitimate messages by pairing them with invalid senders, preventing the real message from being delivered later (denial of service on replay protection).

**Fix:** Validate the module exists before updating the nonce mapping, and revert without consuming the nonce if the module is invalid.

---

## Medium: CommonContainer bytesArrayInitialized does not enforce length > 0 properly for single-element arrays

**File:** `CommonContainer.sol` — `bytesArrayInitialized()` (line 40)

**Root Cause:** The modifier checks `length > 0` and each element length > 0. This is generally fine, but for arrays with empty strings it correctly rejects. The issue is more subtle: there is no upper bound check, allowing extremely large arrays that could cause out-of-gas in initialization loops.

**Impact:** Denial of service during initialization if an admin passes an enormous array of module IDs or addresses.

**Fix:** Add a reasonable upper bound (e.g., 100) to `bytesArrayInitialized` and `addressArrayInitialized`.

---

## Medium: Missing zero-check for `mailboxAddress_` and `treasuryAddress_` initialization in EtherBridge

**File:** `EtherBridge.sol` — `initialize()` (line 71)

**Root Cause:** The `addressInitialized` modifier ensures non-zero addresses, but there is no validation that `mailboxAddress_` and `treasuryAddress_` are actual contracts (i.e., code exists) or that they match expected interfaces.

**Impact:** The bridge could be initialized with arbitrary EOA addresses, causing all deposits to fail or to send funds to addresses that don't behave as expected.

**Fix:** Add `require(address(mailboxAddress_).code.length > 0, ...)` and similar for treasury, or enforce interface checks at initialization.

---

## Medium: Mailbox `lastNonce` update in generateRandomNonce modifies storage before return

**File:** `Mailbox.sol` — `generateRandomNonce()` (line 257)

**Root Cause:** The function updates `$.lastNonce` in storage and then returns `uint64($.lastNonce)`. If the returned value is never actually stored or used correctly (e.g., due to an overflow or truncation), the state becomes desynchronized.

**Impact:** Nonce collisions or state corruption could occur if `uint64` truncation produces a duplicate nonce.

**Fix:** Separate nonce generation from storage update; compute the new nonce, verify it is unique, and then store it atomically.

---

## Medium: Treasury `emergencyWithdraw` allows full balance drain without time delay

**File:** `Treasury.sol` — `emergencyWithdraw()` (line 63)

**Root Cause:** There is no timelock, no multi-sig, and no partial withdrawal limit. The owner can drain the entire treasury instantly.

**Impact:** A compromised owner key or malicious admin can steal all bridge-locked ether immediately.

**Fix:** Implement a timelock (e.g., 48 hours), multi-sig requirement, or cap the maximum withdrawal per transaction.

---

## Medium: Mailbox `addModule` and `removeModule` lack event emission

**File:** `Mailbox.sol` — `addModule()` (line 151), `removeModule()` (line 167)

**Root Cause:** Administrative changes to modules are not emitted as events. This reduces transparency and makes off-chain monitoring difficult.

**Impact:** Security monitoring systems may miss unauthorized module additions or removals.

**Fix:** Emit `ModuleAdded(bytes32 moduleId, address module)` and `ModuleRemoved(bytes32 moduleId, address module)` events.

---

## Medium: EtherBridge deposit event does not include `recipient` correctly encoded

**File:** `EtherBridge.sol` — `deposit()` (line 118)

**Root Cause:** The `Deposited` event is emitted with `msg.sender`, `recipient`, and `amountWei`, but `recipient` is a raw `bytes32` that may not be validated as a valid base58-encoded Solana address. No format validation is performed.

**Impact:** Invalid recipient formats could be accepted, causing cross-chain delivery failures or fund loss.

**Fix:** Add validation that `recipient` conforms to the expected Solana base58 format or length, and emit a warning or revert if invalid.

---

## Low: Mailbox `onlyTrustedRelayer` modifier relies solely on role hash, no additional authentication

**File:** `Mailbox.sol` — `onlyTrustedRelayer` modifier (line 83)

**Root Cause:** The role hash is fixed (`TRUSTED_RELAYER_ROLE`), which is fine, but there is no additional validation like message signatures or chain ID verification beyond the modifier.

**Impact:** If the relayer key is compromised, the attacker can deliver arbitrary messages with no further checks.

**Fix:** Consider requiring message-level authentication (e.g., a signed payload from the relayer) in addition to role-based access control.

---

## Low: CommonContainer `encodeChainId` uses `abi.encode` instead of `abi.encodePacked` for consistency

**File:** `CommonContainer.sol` — `encodeChainId()` (line 6)

**Root Cause:** `encodeChainId` uses `abi.encode`, while `generateChainId` uses `abi.encodePacked`. This inconsistency could lead to unexpected encoding behavior when comparing or decoding chain IDs.

**Impact:** Potential mismatches in chain ID representation between encoding and decoding paths.

**Fix:** Use `abi.encodePacked` consistently in both `encodeChainId` and `generateChainId`, or document the encoding standard clearly.

---

## Low: EtherBridge `etherBridgeId` is stored as `bytes` but never validated against interface expectations

**File:** `EtherBridge.sol` — `StorageV1` (line 32)

**Root Cause:** `etherBridgeId` is set to `abi.encode(ETHER_BRIDGE_ID)` but there is no check that `ETHER_BRIDGE_ID` matches the module ID registered in the mailbox.

**Impact:** If the mailbox expects a different module identifier, the mailbox may reject messages from this bridge.

**Fix:** Ensure `ETHER_BRIDGE_ID` is registered in the mailbox at initialization time, or pass it as a parameter and validate it.

---

## Informational: Missing NatSpec documentation for several public/state variables

**File:** `Mailbox.sol`, `EtherBridge.sol`, `Treasury.sol`

**Root Cause:** Several storage variables (`StorageV1` fields) and parameters lack comprehensive NatSpec descriptions, making audit and integration more difficult.

**Impact:** Reduced code readability and maintainability.

**Fix:** Add `@dev`, `@param`, and `@return` documentation for all public/external functions and state variables.

---

## Informational: `generateRandomNonce` uses deprecated `block.coinbase` instead of `block.prevrandao`

**File:** `Mailbox.sol` — `generateRandomNonce()` (line 261)

**Root Cause:** `block.coinbase` is the miner address, which is less random than `block.prevrandao` (post-Merge randomness) in modern Ethereum.

**Impact:** Slightly reduced randomness quality for nonce generation.

**Fix:** Replace `block.coinbase` with `block.prevrandao` where appropriate.
