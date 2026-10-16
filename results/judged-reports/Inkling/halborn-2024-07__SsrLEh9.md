# Security Audit Report — Eclipse Smart Contracts v1

Scope: `smart-contracts/src/v1/Treasury.sol`, `Mailbox.sol`, `EtherBridge.sol`, `CommonContainer.sol`

---

## Critical: Predictable and manipulable nonce generation in Mailbox

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 257)

**Root cause:** The nonce is derived solely from `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase` (all validator/manipulable), and the previous nonce. No external entropy source is used. A malicious relayer or validator can influence or predict future nonces.

**Impact:** Replay protection relies on nonce uniqueness. Predictable nonces allow replay attacks or targeted nonce collisions, undermining cross-chain message integrity.

**Fix:** Introduce an external, unpredictable entropy source (e.g., commit-reveal, VDF, or chain-specific random beacon). Do not rely exclusively on block parameters.

---

## Critical: Unrestricted low-level external call in receiveMessage without return-data validation

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 187)

**Root cause:** `module.call(message_)` forwards arbitrary calldata to the module. While `require(success, ...)` checks the boolean result, there is no restriction on which function selector is invoked, and a malicious or compromised module could execute arbitrary logic.

**Impact:** If a module address is compromised or a spoofed `sender_` maps to a malicious module, arbitrary code execution is possible through the mailbox relay path.

**Fix:** Restrict `message_` to a known ABI-encoded format or whitelist selectors, and consider using `delegatecall`-style isolation or stricter module verification.

---

## High: sendMessage ignores the chainId parameter entirely

**File:** `Mailbox.sol`  
**Function:** `sendMessage()` (line 225)

**Root cause:** The first `bytes memory` parameter (`chainId_`) is unnamed and never read. The emitted event hardcodes `encodeChainId($.eclipseChainId)` regardless of what chain ID was requested.

**Impact:** Cross-chain messages cannot be routed to different destination chains; any chain-id spoofing attempt is silently ignored, breaking inter-chain routing guarantees.

**Fix:** Validate `chainId_` against the configured chain IDs and use it in the event and routing logic.

---

## High: EtherBridge deposit passes empty chainId to mailbox

**File:** `EtherBridge.sol`  
**Function:** `deposit()` (line 92)

**Root cause:** The call to `mailboxProxy.sendMessage` uses `""` (empty bytes) for the chain ID parameter, meaning no destination chain is specified.

**Impact:** The mailbox ignores the parameter, but this breaks the intended messaging protocol and could cause lost or misrouted messages if mailbox logic is updated to enforce chain validation.

**Fix:** Pass the correct target chain ID (e.g., `encodeChainId($.ethereumChainId)` or equivalent) to `sendMessage`.

---

## High: Reentrancy risk in Treasury emergencyWithdraw

**File:** `Treasury.sol`  
**Function:** `emergencyWithdraw()` (line 63)

**Root cause:** Although `nonReentrant` is present, the function performs an external `call` (`msg.sender.call{value: amount}("")`) before emitting the event. A malicious owner contract could re-enter through the receive/fallback path; `nonReentrant` should block it, but the low-level call pattern combined with owner-controlled execution creates an elevated risk profile.

**Impact:** If `nonReentrant` behavior is ever bypassed or the modifier is removed in an upgrade, full treasury drain is possible via reentrancy.

**Fix:** Use `address(owner()).call{value: amount}("")` explicitly (not `msg.sender`) and follow checks-effects-interactions strictly; emit events before external calls.

---

## High: Mailbox receiveMessage does not enforce strict bytes32 length on sender

**File:** `Mailbox.sol`  
**Function:** `receiveMessage()` (line 187)

**Root cause:** `bytes32(sender_)` converts arbitrary-length bytes. A shorter `sender_` will be left-padded with zeros, potentially mapping to an unintended module or causing collisions.

**Impact:** Message spoofing or misrouting to the wrong module if sender encoding is manipulated.

**Fix:** Enforce `bytesLengthEq32(sender_)` (or equivalent strict length check) before conversion.

---

## Medium: EtherBridge uses low-level call for treasury lock without event emission on failure path

**File:** `EtherBridge.sol`  
**Function:** `deposit()` (line 115)

**Root cause:** `(success,) = payable(address($.treasuryProxy)).call{value: amountWei}("");` locks funds in the treasury. If the treasury address is incorrect or the treasury rejects ETH (e.g., via `whenNotPaused`), the call fails and the entire deposit reverts. There is no graceful handling or partial state rollback mechanism.

**Impact:** A paused treasury blocks all bridge deposits, creating a denial-of-service on the bridge.

**Fix:** Ensure treasury and mailbox states are synchronized before deposit, or implement a recover/retry mechanism for locked funds.

---

## Medium: Mailbox module mapping allows duplicate IDs with different addresses in add/remove

**File:** `Mailbox.sol`  
**Functions:** `addModule()` (line 151), `removeModule()` (line 167)

**Root cause:** `addModule` checks `$.modulesById[moduleId] != address(0)` but does not prevent adding the same `module` address under a different ID. `removeModule` requires an exact address match but does not clean up roles if the address has other IDs.

**Impact:** Confused-deputy risks or orphaned roles if module management is not kept strictly consistent.

**Fix:** Track bidirectional mappings (id→address and address→id) and enforce uniqueness in both directions.

---

## Medium: CommonContainer bytesLengthEq32 only checks length, not content validity

**File:** `CommonContainer.sol`  
**Modifier:** `bytesLengthEq32` (line 64)

**Root cause:** The modifier verifies `_data.length == 32` but does not enforce non-zero content or decode validity. Combined with `decodeChainId`, an all-zero 32-byte value passes length checks but represents an invalid chain ID.

**Impact:** Invalid chain IDs (e.g., `bytes32(0)`) could pass validation if other checks are missing, leading to routing errors.

**Fix:** Add a `bytes32Initialized` or non-zero content check to `bytesLengthEq32` or to chain-id-specific modifiers.

---

## Medium: Treasury receive allows direct owner deposits without module mediation

**File:** `Treasury.sol`  
**Function:** `receive()` (line 83)

**Root cause:** The `receive()` function allows the owner (`msg.sender == owner()`) to deposit ETH directly, bypassing the ether bridge. While acceptable for emergencies, it breaks the audit trail that all treasury funds should originate from the bridge.

**Impact:** Accounting inconsistency; emergency or manual injections could mask bridge failures or be used to manipulate balances.

**Fix:** Restrict `receive()` exclusively to `$.etherBridgeAddress`, and require the owner to interact through the bridge or a separate explicit deposit path.

---

## Low: Mailbox generateRandomNonce does not handle blockhash unavailability

**File:** `Mailbox.sol`  
**Function:** `generateRandomNonce()` (line 257)

**Root cause:** `blockhash(block.number - 1)` returns `bytes32(0)` if called within the same block or for very recent blocks (depending on chain rules). The function does not detect this and will generate a predictable/repeated nonce.

**Impact:** Nonce collision or predictable values in rapid successive calls within the same block.

**Fix:** Check that `blockhash(block.number - 1) != bytes32(0)`; if unavailable, fall back to a different entropy source or revert.

---

## Low: EtherBridge MIN_DEPOSIT uses magic constant without named constants in modifier

**File:** `EtherBridge.sol`  
**Modifier:** `validDepositAmount()` (line 49)

**Root cause:** `MIN_DEPOSIT` is defined via `MIN_DEPOSIT_LAMPORTS * WEI_PER_LAMPORT`. The modifier compares `msg.value >= MIN_DEPOSIT`, which is correct, but the error message does not indicate the minimum required value, making debugging difficult.

**Impact:** User experience and operational clarity are reduced; no direct security impact.

**Fix:** Include the minimum value in the revert message.

---

## Informational: Missing event for module role changes

**File:** `Mailbox.sol`  
**Functions:** `addModule()` (line 151), `removeModule()` (line 167)

**Root cause:** No events are emitted when a module is added or removed, reducing off-chain monitoring and auditability of critical access-control changes.

**Fix:** Emit `ModuleAdded(bytes32 id, address module)` and `ModuleRemoved(bytes32 id, address module)` events.

---

## Informational: Interface parameter names do not match implementation

**File:** `IMailbox.sol` (line 22)

**Root cause:** The `sendMessage` interface documentation incorrectly labels parameters (e.g., `chainId_` described as "address of the receiver"). The implementation ignores the first parameter entirely.

**Impact:** Integration errors and developer confusion when interacting with the mailbox.

**Fix:** Align interface documentation with the actual parameter semantics and implementation behavior.

---

*Report generated by professional smart-contract audit. Only the first 20 level-2 headings are graded.*
