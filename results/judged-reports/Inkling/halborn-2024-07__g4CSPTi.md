## Critical: Predictable / manipulable nonce undermines replay protection
- **File / Function:** `Mailbox.sol` — `generateRandomNonce()`
- **Root cause:** The nonce is derived from `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase`, all of which are miner-influenced or publicly known. It is not cryptographically unpredictable.
- **Impact:** An attacker who can influence block production (or observe the values before a transaction is mined) can predict or force nonce collisions, defeating replay protection and allowing duplicate `sendMessage` or `receiveMessage` attempts.
- **Fix:** Use an incrementing counter stored in state (`lastNonce++`) or a secure random source (e.g., `Chainlink VRF`) instead of block-derived entropy.

## Critical: Unrestricted external call to arbitrary module in receiveMessage
- **File / Function:** `Mailbox.sol` — `receiveMessage()`
- **Root cause:** The function performs a low-level `module.call(message_)` without restricting the target, calldata format, or gas. Because the call uses all remaining gas (`nonReentrant` prevents reentrancy on the mailbox only), a malicious or compromised module can consume the call frame or trigger unexpected external behavior.
- **Impact:** A malicious module could reenter through the module contract (not the mailbox, so `nonReentrant` doesn't stop it) or execute arbitrary logic with the mailbox's context, potentially corrupting cross-chain state.
- **Fix:** Restrict the call to a predefined interface and limit gas (`call{gas: ...}`), or use a high-level interface call with strict function selectors.

## High: Emergency withdrawal uses raw call without address validation
- **File / Function:** `Treasury.sol` — `emergencyWithdraw()`
- **Root cause:** The function sends Ether to `msg.sender` via `(bool success,) = msg.sender.call{value: amount}("");`. There is no check that `msg.sender` is the intended recipient, and the function allows any owner to withdraw to themselves. Combined with `onlyOwner`, this is by design, but there is no time-lock or multi-sig enforcement mentioned.
- **Impact:** If the single owner is compromised, all treasury funds can be drained instantly. The spec notes withdrawals are paused and should be managed by a multi-sig, but the contract does not enforce that.
- **Fix:** Add a multi-sig or time-delay mechanism for withdrawals, or enforce that withdrawals can only go to a pre-approved treasury address.

## High: No replay protection for send nonces beyond storage check
- **File / Function:** `Mailbox.sol` — `sendMessage()`
- **Root cause:** The nonce is generated with `generateRandomNonce()` and stored, but if a collision occurs (`sendNonces[outboundNonce] == true`), the transaction simply reverts. There is no mechanism to recover from collisions or to guarantee uniqueness under miner influence.
- **Impact:** A miner could deliberately cause nonce collisions for targeted messages, causing DoS for cross-chain sends.
- **Fix:** Replace with a monotonically increasing nonce (`lastNonce++`).

## High: EtherBridge deposit sends Ether before mailbox message is confirmed
- **File / Function:** `EtherBridge.sol` — `deposit()`
- **Root cause:** The function calls `mailboxProxy.sendMessage(...)` first (line 111) and then transfers Ether to treasury (line 115). If the mailbox call succeeds but the treasury transfer fails (e.g., treasury is paused or the call reverts), the message is already emitted but the funds are not locked.
- **Impact:** Funds could be lost or the message could be emitted without backing Ether, creating an inconsistent state between chains.
- **Fix:** Lock funds in treasury first (`call{value: ...}`), and only emit/forward the mailbox message after confirming the treasury deposit.

## High: Missing chain ID validation on mailbox send
- **File / Function:** `Mailbox.sol` — `sendMessage()`
- **Root cause:** The first parameter (`bytes memory` without a name) is never validated or used. The function does not require the caller to provide the correct Ethereum chain ID, allowing a module to send messages that claim to originate from an incorrect chain.
- **Impact:** Cross-chain routing errors or spoofed origin chains, which could be exploited if the relayer or receiving module relies on chain identity.
- **Fix:** Require the first parameter to match `ethereumChainId` (e.g., `ethereumChainIdValid(chainId_)` modifier) and use it in the emitted event.

## Medium: Unused / unvalidated parameter in Mailbox interface
- **File / Function:** `Mailbox.sol` / `IMailbox.sol` — `sendMessage()`
- **Root cause:** The interface defines `bytes memory chainId_` but the implementation ignores it. The event `MessageSent` uses `encodeChainId($.eclipseChainId)`, not the parameter.
- **Impact:** Callers may provide arbitrary data without effect, masking integration errors and making the API misleading.
- **Fix:** Validate `chainId_` against the stored Ethereum chain ID or document its purpose clearly.

## Medium: `bytesLengthEq32` modifier used for chain ID but allows arbitrary 32-byte values
- **File / Function:** `Mailbox.sol` — `receiveMessage()` / `CommonContainer.sol`
- **Root cause:** The modifier `bytesLengthEq32` only checks length (`== 32`), not content. Any 32-byte value passes, including `bytes32(0)`. There is no check that the chain ID was actually initialized or recognized.
- **Impact:** A malicious relayer could pass arbitrary `eclipseChainId_`, as long as its length is 32 bytes, bypassing intended chain validation.
- **Fix:** Combine length check with an equality check against `$.eclipseChainId` (already partially done via `eclipseChainIdValid`), but ensure that `bytesLengthEq32` is not the only guard.

## Medium: Treasury receive allows owner deposits bypassing bridge checks
- **File / Function:** `Treasury.sol` — `receive()`
- **Root cause:** The fallback allows both `etherBridgeAddress` and `owner()` to deposit. There is no additional validation that deposits come exclusively from the bridge (as intended by the spec), enabling an owner to inject arbitrary Ether and manipulate treasury state.
- **Impact:** An owner could deposit unverified Ether, making the treasury balance inconsistent with bridge records.
- **Fix:** Remove the `msg.sender == owner()` exception, or restrict it to a known admin role with additional event/metadata requirements.

## Medium: Reentrancy guard does not protect treasury call in EtherBridge
- **File / Function:** `EtherBridge.sol` — `deposit()`
- **Root cause:** `deposit()` uses `nonReentrant`, but the low-level `payable(address($.treasuryProxy)).call{value: amountWei}("")` is made after the mailbox call. If the treasury's `receive()` triggers a reentrant call back into `deposit()` (e.g., through a malicious treasury contract), `nonReentrant` on EtherBridge would prevent it, but if the treasury is a proxy or external contract, there could be cross-contract reentrancy that bypasses the guard.
- **Impact:** If the treasury is replaced or behaves maliciously, reentrancy through the treasury could corrupt state.
- **Fix:** Apply checks-effects-interactions: update state / emit event after external calls, or use `ReentrancyGuard` consistently and avoid calling unknown contracts after state changes.

## Low: `generateRandomNonce` uses `uint64` truncation
- **File / Function:** `Mailbox.sol` — `generateRandomNonce()`
- **Root cause:** The function casts a 256-bit hash to `uint64`, significantly reducing entropy and increasing collision probability.
- **Impact:** Higher likelihood of nonce collisions over time, leading to DoS or replay issues.
- **Fix:** Use the full `uint256` for nonces, or use a sequential counter.

## Low: No event emitted on module add/remove
- **File / Function:** `Mailbox.sol` — `addModule()` / `removeModule()`
- **Root cause:** These functions modify the module registry but do not emit any events for off-chain tracking.
- **Impact:** Off-chain monitors cannot detect unauthorized module changes promptly.
- **Fix:** Emit `ModuleAdded(bytes32 moduleId, address module)` and `ModuleRemoved(...)` events.

## Low: `emailChainId` parameter in interface docs misldocumented
- **File / Function:** `IMailbox.sol` — comments
- **Root cause:** The docstrings say `@param chainId_ is the address of the receiver` and `@param data_ is the address of the receiver`, which are incorrect.
- **Impact:** Integration errors due to misleading documentation.
- **Fix:** Correct the docstrings to match the actual parameter meanings.

## Low: `CommonContainer.bytesLengthEq32` does not reject `bytes32(0)`
- **File / Function:** `CommonContainer.sol`
- **Root cause:** The modifier checks `length == 32` but does not check that the 32 bytes are non-zero. `bytes32(0)` encoded as bytes is 32 zero bytes and passes.
- **Impact:** Zero chain IDs or module IDs could pass validation if not paired with `bytes32Initialized`.
- **Fix:** Ensure `bytes32Initialized` is always paired with length checks.

## Low: `Mailbox.receiveMessage` does not validate `sender_` format
- **File / Function:** `Mailbox.sol` — `receiveMessage()`
- **Root cause:** `sender_` is decoded directly via `bytes32(sender_)` for module lookup, without validating that the encoded bytes represent a valid module ID format or that it matches an expected length.
- **Impact:** If `sender_` is malformed but exactly 32 bytes, it could resolve to an unexpected module mapping entry or return zero without a clear error.
- **Fix:** Ensure `bytes32Initialized` is applied to `sender_` after decoding, or require the encoded value to match a registered module ID.

## Low: `EtherBridge` uses `bytes32` recipient without validation
- **File / Function:** `EtherBridge.sol` — `deposit()`
- **Root cause:** The `recipient` parameter is validated with `bytes32Initialized` only (non-zero). There is no check that the recipient is a valid Eclipse address format (base58-decoded Solana address). The spec says it should be a base58-encoded Solana address packed into `bytes32`.
- **Impact:** Invalid or malicious recipient values could be sent across the bridge, leading to unrecoverable deposits on the target chain.
- **Fix:** Add format validation (e.g., length or checksum checks for base58-encoded data) before encoding.

## Low: Missing `initializer` guard on `addModule` / `removeModule`
- **File / Function:** `Mailbox.sol`
- **Root cause:** These external functions are callable by anyone with the admin role at any time, even during initialization or if the mailbox has not finished setup. There is no state check preventing module modifications before initialization completes.
- **Impact:** If initialization is interrupted or re-entered (though `initializer` prevents re-init), module changes could corrupt the module registry unexpectedly.
- **Fix:** Add a state variable (`initialized` or `initializedViaUUPS`) and ensure module modifications are only allowed after full initialization.

## Informational: `Mailbox.sendMessage` ignores first argument; API inconsistency
- **File / Function:** `Mailbox.sol` / `IMailbox.sol`
- **Root cause:** The interface signatures include a `bytes memory chainId_` parameter that is never validated or emitted properly. The event uses the stored `eclipseChainId`, not the parameter.
- **Impact:** Confusion for integrators and potential future bugs if the parameter is intended for cross-chain routing.
- **Fix:** Either validate and use the parameter, or remove it from the interface and implementation.

## Informational: `Mailbox.generateRandomNonce` documentation overstates unpredictability
- **File / Function:** `Mailbox.sol` — `generateRandomNonce()`
- **Root cause:** The NatSpec claims the nonce is "resistant to manipulation and harder to predict in advance given the params solidity supports," but the underlying entropy sources (`blockhash`, `timestamp`, `coinbase`) are fully predictable or miner-controlled.
- **Impact:** False sense of security; developers may rely on the nonce for cryptographic guarantees it does not provide.
- **Fix:** Update documentation to reflect the actual limitations, and replace the mechanism with a secure counter or random oracle.

## Informational: `Treasury` specifies future multi-sig but does not enforce it
- **File / Function:** `Treasury.sol`
- **Root cause:** The spec notes that withdrawals are paused and will be managed by a different multi-sig authority, but the contract uses a single `Ownable2StepUpgradeable` owner. There is no multi-sig logic or separate role for withdrawal authorization.
- **Impact:** The contract does not meet the stated security design; a single compromised owner can drain all funds.
- **Fix:** Implement multi-sig or separate roles for owner (admin) and withdrawal authority.

## Informational: No event emitted for `addModule` / `removeModule`
- **File / Function:** `Mailbox.sol`
- **Root cause:** Registry modifications lack events.
- **Impact:** Off-chain monitoring is limited.
- **Fix:** Emit events for module changes.
