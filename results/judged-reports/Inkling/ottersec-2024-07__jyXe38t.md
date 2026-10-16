# Security Audit Report

## Critical: Weak pseudo-random nonce generation in Mailbox
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `generateRandomNonce()`
**Root cause:** The nonce combines `blockhash(block.number - 1)`, `block.timestamp`, and `block.coinbase`. `blockhash` is only available for the previous 256 blocks, returns 0 otherwise, and is miner-influenceable; `block.timestamp` and `block.coinbase` are also manipulable by validators/miners. This produces predictable or colliding nonces.
**Impact:** Nonce collisions allow replay of cross-chain messages (`sendMessage` / `receiveMessage`), breaking replay-protection guarantees.
**Fix:** Replace with a cryptographically secure entropy source (e.g., `Chainlink VRF`, `commit-reveal` scheme, or a sequential counter stored on-chain and incremented atomically) rather than block-derived values.

## Critical: Mailbox receiveMessage does not validate sender length before bytes32 cast
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `receiveMessage()`
**Root cause:** `bytes32(sender_)` is applied to `sender_` without enforcing it is exactly 32 bytes. `bytesInitialized` only checks `length > 0`. Truncation or left-padding can cause unexpected module lookups or collisions.
**Impact:** A malicious relayer could craft a `sender_` that maps to an unintended module address, redirecting messages.
**Fix:** Apply `bytesLengthEq32(sender_)` modifier to `sender_` in `receiveMessage`.

## Critical: Mailbox sendMessage ignores chainId parameter
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `sendMessage()`
**Root cause:** The first parameter `bytes memory chainId_` is never read; the function always uses the stored `ethereumChainId`. This breaks cross-chain routing if the caller intends to specify a different destination chain.
**Impact:** Messages may be emitted with the wrong chain identifier, causing off-chain relayers to misroute or drop messages.
**Fix:** Use `chainId_` (after validation) or remove the parameter and document the fixed behavior explicitly.

## High: EtherBridge deposit does not link message nonce to mailbox nonce
**File:** `smart-contracts/src/v1/EtherBridge.sol`, function `deposit()`
**Root cause:** The deposit message encoded for the mailbox (`IEtherBridge.DepositMessage`) contains no nonce or replay identifier. The mailbox handles its own nonce (`generateRandomNonce`), but the bridge does not include it in the message payload, so the off-chain relayer must synthesize security params independently.
**Impact:** Off-chain relayer must construct `EclipseSecurityParam` manually, creating risk of nonce mismatch or replay if the bridge and mailbox states diverge.
**Fix:** Include a nonce or unique identifier directly in `DepositMessage` and pass it through to the mailbox security param.

## High: Solana deposit instruction does not record amount in receipt
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `state.rs`
**Root cause:** `DepositReceipt` stores `bump`, `to`, and `eth_deposit_nonce` but has no `amount` field. The `amount` parameter is only used in the system transfer instruction (`system_instruction::transfer`) and is never persisted.
**Impact:** There is no on-chain record of how many lamports were deposited, making reconciliation with Ethereum impossible and allowing arbitrary amounts to be moved without proof.
**Fix:** Add an `amount: u64` field to `DepositReceipt` and write it during `deposit()`.

## High: Solana withdraw instruction has no authorization or amount validation
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`
**Root cause:** Any signer (`withdrawer`) can initiate a withdrawal of any `amount`, transferring lamports from themselves to the hardcoded `relayer`. There is no check linking the withdrawal to a prior deposit, no minimum amount, and no authorization beyond being a signer.
**Impact:** Users can withdraw arbitrary amounts (limited only by their own balance) without proof of a corresponding Ethereum deposit, enabling double-spend or drain risks if combined with other vulnerabilities.
**Fix:** Require proof of a corresponding `DepositReceipt` (e.g., verify the nonce exists and amount matches) and restrict withdrawals to the original deposit recipient.

## High: Treasury receive allows arbitrary sources when not paused
**File:** `smart-contracts/src/v1/Treasury.sol`, function `receive()`
**Root cause:** `receive()` checks `msg.sender == $.etherBridgeAddress || msg.sender == owner()` but does not enforce that `msg.value` matches any expected deposit amount, and allows any value from these sources.
**Impact:** While intended for the bridge, an admin or the bridge contract could send arbitrary ETH, potentially confusing accounting.
**Fix:** Consider adding an event-only receive that rejects unexpected values, or ensure the bridge always sends exactly the expected amount and logs it properly.

## Medium: Mailbox generateRandomNonce can return 0 or repeated values
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `generateRandomNonce()`
**Root cause:** If `block.number == 1` or `> 256` blocks behind, `blockhash` returns 0. Combined with other predictable fields, nonce uniqueness is weak.
**Impact:** Repeated nonces break replay protection on `receiveNonces` mapping, allowing message replay.
**Fix:** Use a monotonically increasing counter (`uint64`) stored in contract state instead of block-derived entropy.

## Medium: Solana withdraw does not validate destination_address format
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `state.rs`
**Root cause:** `destination_address` is a `String` with no length or encoding checks. It is encoded via `alloy_rlp` but never validated against a valid Ethereum address format.
**Impact:** Malformed or malicious strings could corrupt off-chain message parsing, leading to misrouted withdrawals.
**Fix:** Validate `destination_address` is a valid hex-encoded 20-byte address (`String::len() == 42` and starts with `0x`) before accepting.

## Medium: EtherBridge deposit locks funds before confirming mailbox success
**File:** `smart-contracts/src/v1/EtherBridge.sol`, function `deposit()`
**Root cause:** The treasury `.call{value: amountWei}` happens after the mailbox `sendMessage`, but if the mailbox call succeeds and the treasury call fails (e.g., treasury contract reverts or is self-destructed), the message has already been emitted, creating an inconsistency.
**Impact:** A partially failed deposit could result in an emitted cross-chain message without corresponding locked funds.
**Fix:** Lock funds in the treasury first, then send the mailbox message, or use an atomic commit/revert pattern.

## Medium: Mailbox receiveMessage does not emit event on module call failure
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `receiveMessage()`
**Root cause:** If `module.call(message_)` fails (`success == false`), the transaction reverts with `require(success, ...)`, which rolls back state changes. This is safe but provides poor off-chain observability; however, no direct vulnerability.
**Impact:** Not a direct vulnerability, but poor observability. (Already covered by safe revert behavior.)
**Fix:** Not required; revert is safe.

## Low: Solana deposit uses invoke_signed with empty seeds for relayer transfer
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`
**Root cause:** `invoke_signed` is called with `&[]` seeds, but the `from_account` (`relayer`) is already a `Signer`. The use of `invoke_signed` is unnecessary and could mask future seed-based authorization requirements.
**Impact:** Low direct risk, but could confuse future maintainers or lead to authorization gaps if seeds are incorrectly added.
**Fix:** Use a standard `invoke` (without signed seeds) since the relayer is a direct signer.

## Low: Treasury emergencyWithdraw uses msg.sender instead of owner()
**File:** `smart-contracts/src/v1/Treasury.sol`, function `emergencyWithdraw()`
**Root cause:** `msg.sender` is used for `call{value: amount}` but the modifier `onlyOwner` ensures it is the owner. This is redundant but safe.
**Impact:** None, but redundant.
**Fix:** Keep as-is or explicitly use `owner()` for clarity.

## Low: CommonContainer bytesLengthEq32 does not enforce non-empty bytes32 array elements
**File:** `smart-contracts/src/v1/CommonContainer.sol`
**Root cause:** `bytes32ArrayInitialized` checks `!= bytes32(0)` but does not enforce any additional format constraints.
**Impact:** Low; format validation should be done at call sites.
**Fix:** Not required.

## Low: EtherBridge validDepositAmount allows zero amount if MIN_DEPOSIT is 0
**File:** `smart-contracts/src/v1/EtherBridge.sol`
**Root cause:** `MIN_DEPOSIT` is a computed positive constant (`LAMPORTS_PER_YEAR * EXEMPTION_THRESHOLD * DEPOSIT_RECEIPT_DATA_LEN` > 0), so zero cannot pass. Safe by design.
**Impact:** None.

## Low: Mailbox addModule does not check if module address is a contract
**File:** `smart-contracts/src/v1/Mailbox.sol`, function `addModule()`
**Root cause:** `addModule` grants `MODULE_ROLE` to any non-zero address without verifying it implements the expected interface.
**Impact:** A wrongly configured module could receive messages it cannot process, but no direct security impact.
**Fix:** Add interface verification if desired.

## Low: Solana init_config does not emit event
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/init_config.rs`
**Root cause:** `init_config` creates the configuration PDA but does not emit an event.
**Impact:** Reduced auditability; no direct vulnerability.
**Fix:** Emit an event on initialization.

## Medium: Solana withdrawal_receipt uses fixed 1024 bytes space
**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`
**Root cause:** `WithdrawalReceipt::size()` returns a hardcoded 1024 bytes (`TODO: optimize here`). This over-allocates space but is safe.
**Impact:** Wasted rent; not a security vulnerability.
**Fix:** Compute exact size based on fields.

## Informational: Hardcoded bridge authority and relayer pubkeys in Solana
**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`
**Root cause:** `RELAYER_PUBKEY` and `BRIDGE_AUTHORITY_PUBKEY` are hardcoded constants with feature flags for test mode.
**Impact:** Changing relayer or authority requires a program upgrade/redeployment.
**Fix:** Consider allowing these to be configured at initialization rather than compile-time constants.

## Informational: EtherBridge UUPS authorization does not restrict upgrade target
**File:** `smart-contracts/src/v1/EtherBridge.sol`, function `_authorizeUpgrade()`
**Root cause:** `_authorizeUpgrade` only checks `onlyAuthority` but does not restrict the new implementation address.
**Impact:** An admin can upgrade to any contract, which is the intended UUPS behavior, but should be reviewed carefully.
**Fix:** Not a vulnerability by design; document upgrade procedures.
