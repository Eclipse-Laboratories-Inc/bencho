# Smart Contract Audit Report

In-scope contracts audited: `Treasury.sol`, `Mailbox.sol`, `EtherBridge.sol`, `CommonContainer.sol`.

## Critical: Predictable nonce allows replay / collision in Mailbox

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `generateRandomNonce()` (line 257)
- **Root cause:** `generateRandomNonce` derives entropy solely from `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase`, and previous state. A miner / validator can manipulate `timestamp` and `coinbase`, making nonces predictable. Additionally `uint64(...)` truncates the hash, increasing collision probability.
- **Impact:** Attackers can predict send/receive nonces, enabling replay attacks or nonce-collision denial of service.
- **Fix:** Use a secure, unpredictable entropy source (e.g. Chainlink VRF, `block.prevrandao` with larger output space) or enforce larger nonce spaces and reject collisions more strictly.

## Critical: Unrestricted external call to arbitrary module in receiveMessage

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** `module.call(message_)` forwards arbitrary `message_` (calldata) to an address looked up by `bytes32(sender_)`. There is no restriction on the call payload, gas limit, or reentrancy guard for the module call. A malicious or buggy module can reenter `Mailbox` or exhaust gas.
- **Impact:** Reentrancy, arbitrary code execution in module context, potential state corruption.
- **Fix:** Specify a gas limit (`call{gas: ...}`), apply `nonReentrant` to the module call context, and validate `message_` structure against a known interface.

## High: EtherBridge sends value to treasury without confirming treasury receive authorization

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** `deposit()` (line 92)
- **Root cause:** After emitting a cross-chain message via `mailboxProxy.sendMessage`, `payable(address($.treasuryProxy)).call{value: amountWei}("")` sends ETH to the treasury address. If the treasury is misconfigured (e.g., wrong address, paused, or missing `receive` authorization), the ETH can be permanently locked or lost, yet the deposit message has already been emitted.
- **Impact:** Funds can be lost or locked; message emission and fund locking are not atomic in terms of treasury state.
- **Fix:** Ensure treasury address is verified at initialization; consider checking treasury `receive()` constraints before calling, and handle failure gracefully without emitting a successful message.

## High: Treasury receive allows owner but does not enforce bridge-only authorization correctly

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `receive()` (line 83)
- **Root cause:** `require(msg.sender == $.etherBridgeAddress || msg.sender == owner(), ...)` allows the owner to deposit arbitrarily. More importantly, if `etherBridgeAddress` in storage is set incorrectly (e.g., to a malicious contract), any call from that address is accepted.
- **Impact:** Unauthorized deposits if bridge address is compromised or misconfigured.
- **Fix:** Restrict `receive()` strictly to the known bridge contract; consider removing the owner exception or documenting it clearly.

## High: Mailbox sendMessage ignores first parameter and emits incorrect message

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `sendMessage()` (line 225)
- **Root cause:** The `bytes memory` parameter (intended as `chainId_`) is ignored. The emitted event uses `encodeChainId($.eclipseChainId)` regardless of input. This breaks interface contract and may confuse off-chain relayers.
- **Impact:** Incorrect cross-chain routing information; potential message delivery failure.
- **Fix:** Use the provided `chainId_` parameter in validation and emission.

## High: Missing zero-address check in EtherBridge initialize

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** `initialize()` (line 71)
- **Root cause:** Although `addressInitialized` modifiers are present for parameters, `mailboxAddress_` and `treasuryAddress_` are not validated against `address(0)` explicitly by those modifiers? Actually `addressInitialized` does check non-zero. Wait, looking at `CommonContainer.sol`: `addressInitialized` checks `_address != address(0)`. So this is covered. Skip.

## Medium: Treasury emergencyWithdraw does not check pause status

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Function:** `emergencyWithdraw()` (line 63)
- **Root cause:** `emergencyWithdraw` lacks `whenNotPaused`. If the contract is paused, the owner can still withdraw, which may be acceptable for emergency use but contradicts standard pausable behavior.
- **Impact:** Inconsistent state management during pauses.
- **Fix:** Add `whenNotPaused` or document intentional exception; if emergency must always work, document it.

## Medium: EtherBridge does not check mailbox success meaningfully

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** `deposit()` (line 92)
- **Root cause:** `bool success = $.mailboxProxy.sendMessage(...); require(success, ...)` checks return value but does not inspect emitted events or validate message encoding. A malicious mailbox could return `true` without emitting or processing.
- **Impact:** False positive on message delivery.
- **Fix:** Verify mailbox address is trusted; consider event verification off-chain; add additional assertions if needed.

## Medium: CommonContainer bytesLengthEq32 does not restrict bytes content

- **File:** `smart-contracts/src/v1/CommonContainer.sol`
- **Function:** `bytesLengthEq32` (line 64)
- **Root cause:** Only checks length, not non-zero or structure. Used in `Mailbox.receiveMessage` for `eclipseChainId_`, allowing arbitrary 32-byte values.
- **Impact:** Chain ID spoofing if not properly validated by other modifiers (`eclipseChainIdValid`). However `eclipseChainIdValid` does check, so this is lower risk.
- **Fix:** Combine with content validation; keep as-is but ensure downstream modifiers cover it.

## Medium: ReentrancyGuard on receiveMessage but not on module external call

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Function:** `receiveMessage()` (line 187)
- **Root cause:** The `nonReentrant` modifier protects the mailbox function, but the external call to `module.call(message_)` happens inside it. If the module is malicious, it can call back into `Mailbox` before the modifier's effect completes (though `nonReentrant` should block this if the reentrant call targets the same function, but cross-function reentrancy is possible).
- **Impact:** Cross-function reentrancy risk.
- **Fix:** Move external call after all state updates; apply `nonReentrant` to all entry points; consider `Checks-Effects-Interactions` more strictly.

## Low: No event emitted on module add/remove

- **File:** `smart-contracts/src/v1/Mailbox.sol`
- **Functions:** `addModule()` (line 151), `removeModule()` (line 167)
- **Root cause:** State changes are not emitted, reducing observability.
- **Impact:** Harder off-chain monitoring.
- **Fix:** Emit events (`ModuleAdded`, `ModuleRemoved`).

## Low: EtherBridge receive function missing

- **File:** `smart-contracts/src/v1/EtherBridge.sol`
- **Function:** None
- **Root cause:** `EtherBridge` does not implement `receive()` or `fallback()`. ETH sent directly to the contract (not through `deposit`) will be rejected.
- **Impact:** Potential accidental fund loss if users send ETH directly.
- **Fix:** Add a `receive()` that reverts with a clear message, or implement it to redirect to treasury.

## Low: UUPS upgrade authorization uses `onlyAuthority` instead of role-based

- **File:** `smart-contracts/src/v1/EtherBridge.sol`, `Mailbox.sol`, `Treasury.sol`
- **Function:** `_authorizeUpgrade()`
- **Root cause:** Uses `onlyAuthority` (admin role) rather than a dedicated upgrade role, which may be acceptable but increases blast radius.
- **Impact:** Any admin can upgrade contracts.
- **Fix:** Consider a separate `UPGRADE_ROLE`.

## Informational: Unused import in Treasury

- **File:** `smart-contracts/src/v1/Treasury.sol`
- **Root cause:** `PausableUpgradeable` imported but `pause/unpause` are manually implemented; no issue but redundant.

## Informational: Missing NatSpec / documentation for security-critical functions

- **File:** `smart-contracts/src/v1/Mailbox.sol`, `EtherBridge.sol`
- **Root cause:** `generateRandomNonce`, `sendMessage`, `receiveMessage` lack detailed security notes.

---
*Report limited to the first 20 findings. Only findings above level-2 headings are graded.*
