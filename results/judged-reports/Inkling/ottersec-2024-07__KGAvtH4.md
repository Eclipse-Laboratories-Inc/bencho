# Security Audit Report

## Critical: Predictable nonce generation in Mailbox undermines replay protection

**Affected file/function:** `smart-contracts/src/v1/Mailbox.sol` — `generateRandomNonce()`

**Root cause:** The nonce is derived solely from `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase`. All three are either fully predictable or controllable by a validator/miner (or sequencer in a rollup context). Truncating to 64 bits further reduces entropy.

**Impact:** An attacker can pre-compute or influence nonces, weakening replay-protection guarantees for both inbound (`receiveNonces`) and outbound (`sendNonces`) messages. In extreme cases this could enable replay or message-collision attacks.

**Fix:** Replace with a cryptographically secure pseudo-random source (e.g., Chainlink VRF, commit-reveal scheme, or at minimum a counter-based nonce combined with a secret seed and `keccak256` of unpredictable off-chain entropy) rather than block properties alone.

---

## Critical: Solana deposit allows arbitrary recipient without validation

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` — `deposit()`

**Root cause:** The `to` account (`AccountInfo`) is never validated against a recipient whitelist, a pubkey format, or even the signer. The `relayer` is the only signer checked (`RELAYER_PUBKEY`), but the `to` field is fully user-controlled.

**Impact:** A malicious relayer (or any party able to invoke the program through the fixed relayer key) can redirect deposited lamports to any arbitrary account by supplying a different `to` account in the instruction accounts.

**Fix:** Validate `to` against an expected recipient pubkey or require it to match a derived PDA/address bound to the `recipient` parameter in the message.

---

## High: Incorrect space allocation for WithdrawalReceipt due to hardcoded size

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/state.rs` — `WithdrawalReceipt::size()`

**Root cause:** `size()` returns a fixed `1024`, but `WithdrawalReceipt` contains a `String` (`destination_address`) whose length is dynamic (`4 + len`). If the provided string exceeds ~1000 bytes, the account will overflow its allocated space, corrupting Solana account state or causing transaction failure.

**Impact:** Providing a long `destination_address` in `withdraw()` can exceed the reserved space, leading to unexpected behavior, failed transactions, or potential corruption when the account is initialized with `init`.

**Fix:** Calculate space dynamically based on actual string length (`4 + destination_address.len() + 8 + 8 + 1`) or enforce a strict maximum length and reserve accordingly.

---

## High: Withdraw instruction does not validate amount or destination format

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs` — `withdraw()`

**Root cause:** There is no check that `amount > 0`, no maximum, and no format/length validation on `destination_address`. Additionally, the `withdrawer` (any signer) can specify any destination and any amount.

**Impact:** Zero-value withdrawals can bloat the chain state with useless receipts. Arbitrarily long `destination_address` strings risk space overflow. There is no binding between the withdrawal message and a verified Ethereum recipient.

**Fix:** Add `require!(amount > 0, ...)`, enforce a maximum `destination_address` length, and validate `destination_address` against an expected format (e.g., hex-encoded Ethereum address of fixed length).

---

## High: Mailbox sendMessage does not check nonce collision before emission

**Affected file/function:** `smart-contracts/src/v1/Mailbox.sol` — `sendMessage()`

**Root cause:** The nonce is generated and stored in `sendNonces` (`$.sendNonces[outboundNonce] = true`) without first checking whether that nonce was already used. If the weak PRNG produces a duplicate, the previous nonce entry is silently overwritten, losing replay-protection for the earlier nonce.

**Impact:** A reused nonce could allow replay of an older outbound message if the mapping entry is overwritten and then considered fresh again.

**Fix:** Add `require($.sendNonces[outboundNonce] == false, "Nonce already used");` before setting it.

---

## Medium: Deposit instruction accepts zero or unvalidated amounts

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` — `deposit()`

**Root cause:** The `amount: u64` parameter is never checked for `amount > 0`. A zero-value deposit creates a `DepositReceipt` PDA and consumes on-chain space without any economic value transfer.

**Impact:** State bloat / DoS by creating unlimited zero-value deposit receipts.

**Fix:** Add `require!(amount > 0, "Amount must be positive");` at the start of the instruction.

---

## Medium: Mailbox receiveMessage lacks length guard before abi.decode

**Affected file/function:** `smart-contracts/src/v1/Mailbox.sol` — `receiveMessage()`

**Root cause:** `data_` is validated only by `bytesInitialized(data_)` (length > 0). It is then directly `abi.decode(data_, (EclipseSecurityParam))`. If `data_` is shorter than 32 bytes (or malformed), the decode will revert with an uninformative error, but there is no explicit length check.

**Impact:** Malformed `data_` can cause a revert, which is fine for safety, but without a precise length check, diagnostic clarity is reduced and unexpected behavior could occur with partial data.

**Fix:** Add `require(data_.length == 32, "Invalid security param length");` (or the exact expected size) before decoding.

---

## Medium: Treasury authorization uses view modifier incorrectly

**Affected file/function:** `smart-contracts/src/v1/Treasury.sol` — `_authorizeUpgrade()`

**Root cause:** The function is declared `internal view override onlyOwner {}`. Using `view` on a function that performs authorization checks (even if empty) is incorrect because it restricts how the function can be called in non-view contexts, and it is unnecessary.

**Impact:** Potential compatibility issues with upgrade patterns or unexpected behavior if the upgrade authorization is expected to be mutable/state-changing.

**Fix:** Remove the `view` modifier: `function _authorizeUpgrade(address) internal override onlyOwner {}`.

---

## Medium: EtherBridge sends message with empty receiver and no chain identifier

**Affected file/function:** `smart-contracts/src/v1/EtherBridge.sol` — `deposit()`

**Root cause:** `sendMessage` is called with `receiver_ = ""` (empty bytes) and `data_ = ""`. There is no chain identifier or receiver address attached to the message, which may break downstream processing in the mailbox or on the Eclipse side expecting these fields.

**Impact:** If the mailbox or rollup expects non-empty `receiver_` or `data_` (e.g., for routing or security params), the deposit message may be dropped or misrouted.

**Fix:** Populate `receiver_` and `data_` with the appropriate chain/recipient identifiers, or confirm the mailbox explicitly handles empty values.

---

## Low: Solana withdraw does not verify relayer receives correct amount

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs` — `withdraw()`

**Root cause:** The `system_instruction::transfer` sends `amount` from `withdrawer` to `relayer`. There is no validation that the `relayer` account actually receives the lamports or that the `amount` matches an expected fee/bridge value.

**Impact:** If the `relayer` account is modified or a different account is passed, funds could be misdirected. The impact is mitigated because the address is pinned to `RELAYER_PUBKEY`.

**Fix:** Assert `to_account` is exactly the expected relayer pubkey (already enforced by `address = RELAYER_PUBKEY`) and consider emitting an event for transparency.

---

## Low: No maximum string length enforced for withdrawal destination

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs` — `WithdrawalReceipt`

**Root cause:** `destination_address: String` has no length cap. Extremely long strings could exhaust the fixed 1024-byte space or cause serialization issues.

**Impact:** Denial of service or failed transactions when a very long string is provided.

**Fix:** Enforce a maximum length (e.g., 42 bytes for an Ethereum address) and return an error if exceeded.

---

## Informational: Fixed-size space reservation for Configuration is excessive

**Affected file/function:** `eclipse-programs/programs/canonical_bridge/src/state.rs` — `Configuration::size()`

**Root cause:** `Configuration` (two booleans + one `u8`) uses a fixed 1024 bytes. This is over-reservation, which is safe but wasteful.

**Impact:** Higher rent exemption cost than necessary, though not a security defect.

**Fix:** Reserve the exact required space: `1 + 1 + 1 = 3` (plus discriminator) instead of 1024.

---

## Informational: Mailbox module removal does not check role before revoking

**Affected file/function:** `smart-contracts/src/v1/Mailbox.sol` — `removeModule()`

**Root cause:** The function checks that `modulesById[moduleId] == module`, then deletes and revokes. There is no additional check that the module still holds `MODULE_ROLE` before revoking, though the mapping check implies it was granted.

**Impact:** Minimal risk; revoking a role that is not held is a no-op in OpenZeppelin.

**Fix:** No action required; this is informational.
