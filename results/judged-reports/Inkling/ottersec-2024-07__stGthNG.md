# Security Audit Report — Eclipse Bridge

## Critical: Weak nonce generation allows replay / collision in Mailbox
**File:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 244)
**Root cause:** The nonce is derived from `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase`, and `$.lastNonce`. All of these are miner/validator-manipulable (`blockhash` can be influenced, `timestamp` and `coinbase` are directly controllable by the block proposer). Only the lower 64 bits are kept.
**Impact:** Nonces can be predicted or forced to collide. A malicious relayer could replay messages or craft duplicate nonces, defeating replay protection (`receiveNonces`).
**Fix:** Use a cryptographically secure source of entropy (e.g., `keccak256(abi.encodePacked(...))` is still weak). Ideally use a counter-based nonce with strict sequential tracking, or rely on an external entropy oracle / Chainlink VRF. At minimum, replace block properties with unpredictable on-chain data (e.g., hash of all prior messages plus a secret seed) and keep full 256 bits.

## Critical: Solana deposit does not link amount to any validated message
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()` (line 31)
**Root cause:** The function creates a `DepositReceipt` and performs a SOL transfer from the hardcoded `relayer` to an arbitrary `to` account. There is no validation that the `amount` corresponds to an Ethereum deposit event, no check of a cross-chain message, and no verification that the `eth_deposit_nonce` has not been used (only PDA init prevents exact reuse). The `amount` is taken directly from the caller's argument.
**Impact:** The hardcoded relayer can be made to transfer arbitrary SOL to any `to` account with any `amount`, as long as the PDA hasn't been initialized. There is no economic linkage to Ethereum.
**Fix:** Verify the deposit against a signed message or a verified cross-chain event from the Mailbox / Ethereum side before transferring SOL. Ensure `amount` and `to` are derived from an authenticated message, not user input.

## Critical: Solana withdraw allows arbitrary amount and has no receipt linkage
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 36)
**Root cause:** `amount` and `destination_address` are user-supplied and stored in a newly initialized PDA. There is no check that the `amount` matches any locked balance, any Ethereum withdrawal event, or any message from the mailbox. The `withdrawer` sends SOL to the hardcoded `relayer`.
**Impact:** A user can create a withdrawal receipt with any `amount` and any `destination_address`, sending their own SOL to the relayer. The receipt has no linkage to actual bridge reserves.
**Fix:** Validate the withdrawal against a verified message from Ethereum / Mailbox. Ensure the amount matches a previously locked deposit or a cross-chain withdrawal authorization.

## High: Mailbox receiveMessage forwards arbitrary bytes without module validation
**File:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()` (line 177)
**Root cause:** After decoding the nonce, the contract looks up `module` by `bytes32(sender_)` and calls `(bool success,) = module.call(message_)`. There is no restriction on the content of `message_`, no signature verification of the sender, and no validation that the message was intended for this module.
**Impact:** If a malicious module is registered (or if the `modulesById` mapping is manipulated), arbitrary calls can be made. Even with a trusted relayer, a compromised module address could receive malicious payloads.
**Fix:** Add message authentication (e.g., require a signature or MAC from the sender) and restrict the message format. Ensure the module expects the exact encoding.

## High: EtherBridge deposit converts wei to gwei via integer division with no overflow protection
**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101)
**Root cause:** `uint256 amountGwei = amountWei / WEI_PER_LAMPORT;` performs integer division. Although `validDepositAmount` requires divisibility, there is no protection against overflow in the encoded message or in downstream processing.
**Impact:** If `amountWei` is very large, `amountGwei` could still overflow in Solana (`u64`) when processed, leading to incorrect amounts on the rollup. The contract doesn't enforce a maximum deposit.
**Fix:** Add a `MAX_DEPOSIT` check and ensure `amountGwei` fits in the target chain's integer type (`uint64`).

## High: Solana init_config uses hardcoded authority without initialization guard beyond `init`
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/init_config.rs`, `init_config()` (line 23)
**Root cause:** The `Configuration` PDA is initialized once (`init`). After initialization, there is no mechanism to rotate the `BRIDGE_AUTHORITY_PUBKEY` or recover from a compromised authority. The authority is hardcoded in the binary.
**Impact:** If the hardcoded authority key is lost or compromised, the bridge configuration cannot be updated safely.
**Fix:** Implement an upgradeable authority mechanism or multi-sig authority. At minimum, document the key management policy.

## High: Solana withdraw uses invoke_signed with empty seeds incorrectly
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 60)
**Root cause:** `invoke_signed(&transfer_instruction, &[...], &[])` passes empty signer seeds (`[]`). This implies no PDA-derived signature is added, but the code uses `invoke_signed` instead of `invoke`. While this may not fail (since the relayer is a direct signer), it is incorrect usage and could break if the program relies on PDA signatures for authorization.
**Impact:** Potential failure or unexpected behavior during CPI. It obscures the authorization model.
**Fix:** Use `invoke` (not `invoke_signed`) for standard system transfers where the signer is a direct account, or properly provide PDA seeds if a PDA is the intended signer.

## High: EtherBridge sendMessage passes wrong parameter mapping to mailbox
**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 120)
**Root cause:** `$.mailboxProxy.sendMessage("", $.etherBridgeId, encodedMessage, "")` maps arguments as `(chainId_="", receiver_=$.etherBridgeId, message_=encodedMessage, data_="")`. The interface defines `receiver_` as "the address of the receiver" (`bytes`), but the bridge passes `etherBridgeId` (a `bytes32` encoded as bytes). This inverts the intended message routing.
**Impact:** The mailbox may route the message incorrectly, or the receiver on the Eclipse side may not match the intended module.
**Fix:** Pass the correct `receiver_` (target chain address / module id) and `chainId_` according to the mailbox interface specification.

## Medium: Treasury receive allows only etherBridge or owner, but no event emission on direct ETH send
**File:** `smart-contracts/src/v1/Treasury.sol`, `receive()` (line 72)
**Root cause:** If ETH is sent directly (not through `deposit`), the event is emitted but there's no linkage to a deposit message. The contract doesn't reject extra ETH during a paused state? Actually `whenNotPaused` is applied.
**Impact:** If the bridge is paused, the treasury can't receive ETH from the bridge, but it could still receive ETH from the owner. No direct vulnerability.
**Fix:** Ensure the treasury only accepts ETH from the bridge when not paused and tracks the total locked amount.

## Medium: Mailbox nonce tracking only keeps boolean flags
**File:** `smart-contracts/src/v1/Mailbox.sol`, `StorageV1` (line 51)
**Root cause:** `mapping(uint64 => bool) receiveNonces` and `sendNonces` store only booleans. There is no expiration or cleanup mechanism. Over time, the mapping grows unbounded (though `uint64` limits the space).
**Impact:** Storage bloat is minimal due to 64-bit keys. However, there is no mechanism to recycle or expire old nonces.
**Fix:** Consider adding a nonce window or using a counter-based system to limit storage growth.

## Medium: Mailbox addModule does not emit event
**File:** `smart-contracts/src/v1/Mailbox.sol`, `addModule()` (line 141)
**Root cause:** No event emission when a module is added or removed.
**Impact:** Off-chain monitoring and auditing are harder.
**Fix:** Emit `ModuleAdded` / `ModuleRemoved` events.

## Medium: Solana deposit and withdraw do not check rent exemption
**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`, `WithdrawalReceipt::size()` (line 38)
**Root cause:** `WithdrawalReceipt::size()` returns 1024 bytes (hardcoded), and `DepositReceipt::size()` calculates a small fixed size. There is no verification that the PDA is rent-exempt.
**Impact:** If the PDA is not funded with enough SOL, it could be garbage-collected or become unrentable.
**Fix:** Ensure the PDA is created with sufficient lamports (use `Init` with `rent` sysvar or enforce minimum balance checks).

## Low: EtherBridge UUPS upgrade authorization lacks upgrade event
**File:** `smart-contracts/src/v1/EtherBridge.sol`, `_authorizeUpgrade()` (line 141)
**Root cause:** The upgrade authorization is protected by `onlyAuthority`, but no event is emitted on upgrade.
**Impact:** Off-chain observers cannot detect contract upgrades.
**Fix:** Emit an `Upgraded` event in `_authorizeUpgrade` or rely on the OZ UUPS event.

## Low: Mailbox chain ID validation uses `bytesLengthEq32`
**File:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()` (line 188)
**Root cause:** `bytesLengthEq32` requires exactly 32 bytes for `eclipseChainId_`. This is fine for `bytes32` encoded as bytes, but the function doesn't enforce that the decoded chain ID matches the expected format beyond equality.
**Impact:** Minimal.
**Fix:** Ensure consistent encoding/decoding.

## Low: CommonContainer modifier `bytesLengthEq32` doesn't check content
**File:** `smart-contracts/src/v1/CommonContainer.sol`, `bytesLengthEq32()` (line 63)
**Root cause:** The modifier checks length but not content (e.g., all zeros).
**Impact:** Minimal.
**Fix:** Combine with `bytes32Initialized` where appropriate.

## Low: Solana bridge program uses `base64` for logging only
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `log_outbox_message()` (line 91)
**Root cause:** The withdrawal message is encoded and base64-logged, but there is no verification that the log is consumed or validated by any external system.
**Impact:** Logging does not provide security guarantees.
**Fix:** Ensure the log is processed by a trusted indexer or verifier.

## Low: EtherBridge deposit event doesn't index all fields
**File:** `smart-contracts/src/v1/interfaces/IEtherBridge.sol`, `Deposited` event (line 21)
**Root cause:** The event is correctly indexed (`sender`, `recipient`), but `amountWei` is not indexed.
**Impact:** Filtering by amount requires full log scanning.
**Fix:** Consider indexing `amountWei` if filtering by amount is required.

## Low: Solana init_config doesn't restrict re-initialization of PDA
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/init_config.rs`, `InitConfig` (line 7)
**Root cause:** Anchor's `init` modifier prevents re-initialization, but the `seeds` don't include the authority address.
**Impact:** Minimal.
**Fix:** None needed beyond standard Anchor behavior.

## Informational: EtherBridge uses separate storage slot for V1
**File:** `smart-contracts/src/v1/EtherBridge.sol`, `StorageV1` (line 48)
**Root cause:** The contract uses `STORAGE_V1_LOCATION` for upgradeable storage. This is standard.
**Impact:** None.
**Fix:** None.
