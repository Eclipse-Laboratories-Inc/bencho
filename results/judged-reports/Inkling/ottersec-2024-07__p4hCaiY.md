# Security Audit Report

## Critical: Predictable nonce generation in Mailbox.generateRandomNonce
- File: `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()`
- Root cause: The nonce is derived from `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase`, and the previous nonce. All of these values are either fully known (timestamp, coinbase) or controlled/manipulated by the block proposer/miner (`blockhash`). This makes the nonce highly predictable and not cryptographically secure.
- Impact: Replay protection relies on nonce uniqueness. A predictable/manipulable nonce weakens replay defense for cross-chain messages, allowing potential replay or nonce-collision attacks by a malicious validator/miner.
- Fix: Replace pseudo-random block-property hashing with a secure, counter-based nonce stored in contract state, incremented atomically per message, and optionally combined with a cryptographic hash of the message payload.

## Critical: Missing length validation on sender_/message_ in Mailbox.receiveMessage
- File: `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()`
- Root cause: Only `bytesLengthEq32` is applied to `eclipseChainId_`. `sender_` and `message_` use `bytesInitialized` (only checks non-empty). When looking up the module, `bytes32(sender_)` is used. In Solidity, a shorter `bytes memory` pads with zeros when cast to `bytes32`, and a longer value truncates. This can cause the module lookup (`modulesById[bytes32(sender_)]`) to resolve to an unintended module.
- Impact: A trusted relayer could craft `sender_` that pads/truncates to the `bytes32` id of an authorized module, delivering a malicious message to the wrong module.
- Fix: Enforce exact 32-byte length for `sender_` (`bytesLengthEq32`) and validate `message_` structure/length before calling `module.call()`.

## High: Arbitrary deposit receipt creation without Ethereum event linkage
- File: `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()`
- Root cause: The instruction only requires that `relayer == RELAYER_PUBKEY`. There is no on-chain verification that the `eth_deposit_nonce` and `amount` correspond to a verified Ethereum deposit event (e.g., no hash of the mailbox message or signature from the bridge contract). A compromised or malicious relayer can initialize arbitrary `DepositReceipt` accounts and transfer any amount of SOL from the relayer to any `to` account.
- Impact: If the relayer key is compromised, an attacker can mint arbitrary deposit receipts and steal SOL.
- Fix: Add validation that the deposit parameters match an allowed/verified message from the Ethereum mailbox (e.g., verify a hash or include a signed proof from the mailbox contract).

## High: No authorization linking withdrawal to Ethereum withdrawal messages
- File: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()`
- Root cause: Any `withdrawer` (signer) can call `withdraw()` with arbitrary `destination_address`, `withdrawal_nonce`, and `amount`. There is no verification that the withdrawal was authorized by the Ethereum mailbox or that the nonce/amount match a valid cross-chain withdrawal message.
- Impact: Users can initiate arbitrary withdrawals that do not correspond to real bridge withdrawals, potentially confusing off-chain indexing or allowing duplicate/extraneous withdrawal receipts.
- Fix: Require a proof or signature from the mailbox/bridge contract verifying the withdrawal parameters, or enforce that the `withdrawer` and `amount` match an authorized message.

## High: Fixed-size WithdrawalReceipt risks account overflow with long String
- File: `eclipse-programs/programs/canonical_bridge/src/state.rs`, `WithdrawalReceipt`
- Root cause: `WithdrawalReceipt::size()` returns a fixed `1024`, but the account contains `destination_address: String` which has dynamic length (4-byte length prefix + bytes). There is no length limit enforced on the string. A very long `destination_address` could exceed the reserved 1024 bytes, causing serialization errors or account corruption.
- Impact: Potential account corruption, deserialization failures, or overflow if a malicious user passes an extremely long `destination_address`.
- Fix: Enforce a maximum string length in the instruction (e.g., `require!(destination_address.len() <= 200, ...)`) and adjust `size()` accordingly, or use a fixed-size byte array instead of `String`.

## Medium: Unvalidated receiver_ and message_ in Mailbox.sendMessage
- File: `smart-contracts/src/v1/Mailbox.sol`, `sendMessage()`
- Root cause: `sendMessage()` accepts arbitrary `bytes memory receiver_` and `bytes memory message_` with only `onlyModule` and `nonReentrant`. There is no validation that the receiver is non-empty, that the message conforms to expected formats, or that the receiver matches a registered module id.
- Impact: Authorized modules can emit arbitrary `MessageSent` events with incorrect or malicious payloads, potentially confusing downstream relayers or consumers.
- Fix: Add length/content validation for `receiver_` and `message_`, and ensure `receiver_` maps to a known module or chain id.

## Medium: Weak replay protection due to short and predictable nonce
- File: `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` / `sendMessage()` / `receiveMessage()`
- Root cause: Nonce is only 64 bits (`uint64`). Combined with the predictable generation method (block properties + previous state), the nonce space is small and vulnerable to brute-force or collision attempts. Additionally, `sendMessage` does not check that the nonce hasn't been used before; it only sets `sendNonces[nonce] = true`. A duplicate nonce would silently overwrite.
- Impact: Potential nonce collision allows replay of messages or confusion between sent and received messages.
- Fix: Use a monotonically increasing counter (`uint256`) stored in state, checked for existence before use, and derived from a secure source rather than block properties.

## Medium: No validation of `to` account or `amount` in Rust deposit instruction
- File: `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()`
- Root cause: The `to` account (`AccountInfo`) is not validated (only a `/// CHECK` comment). The `amount` is not validated against any minimum or maximum, and there is no check that `to` is owned by the intended user or is a valid account.
- Impact: A malicious relayer could direct deposit SOL to arbitrary accounts (including program accounts or accounts without space for data), and could use any amount.
- Fix: Validate `to` is a valid system/account owned by a user, and enforce minimum/maximum deposit amounts linked to Ethereum parameters.

## Low: Potential revert in generateRandomNonce at block 0
- File: `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()`
- Root cause: `blockhash(block.number - 1)` will underflow/revert when `block.number == 0` because `uint256` arithmetic checks for underflow in Solidity 0.8.
- Impact: The first transaction in a new chain or in a block at height 0 that calls `sendMessage` will revert.
- Fix: Add a guard (`require(block.number > 0, ...)`) or use a different entropy source that does not require `block.number - 1`.

## Low: Only DEFAULT_ADMIN_ROLE used for authority checks in EtherBridge
- File: `smart-contracts/src/v1/EtherBridge.sol`, `onlyAuthority()`
- Root cause: `onlyAuthority` only checks `DEFAULT_ADMIN_ROLE`. There is no granular role separation (e.g., separate roles for pausing, upgrading, or managing modules). This violates the principle of least privilege.
- Impact: Any admin can perform all administrative actions (pause, upgrade, change roles), increasing the blast radius of a compromised admin key.
- Fix: Introduce separate role constants (e.g., `PAUSER_ROLE`, `UPGRADER_ROLE`) and restrict modifiers accordingly.

## Low: Treasury receive allows owner deposits without distinguishing source
- File: `smart-contracts/src/v1/Treasury.sol`, `receive()`
- Root cause: `receive()` allows both `etherBridgeAddress` and `owner()` to send ether. There is no event parameter distinguishing whether a deposit came from the bridge or the owner, which could confuse auditing.
- Impact: Off-chain tracking may misattribute owner deposits as bridge deposits.
- Fix: Add separate event types or include a `source` parameter in `TreasuryDeposit` to distinguish bridge vs owner deposits.

## Low: Hardcoded bridge authority in Rust with no upgrade mechanism
- File: `eclipse-programs/programs/canonical_bridge/src/lib.rs` / `init_config.rs`
- Root cause: `BRIDGE_AUTHORITY_PUBKEY` is hardcoded at compile time. There is no instruction to rotate or update the authority key after initialization.
- Impact: If the authority private key is compromised, there is no on-chain mechanism to replace it, requiring program redeployment.
- Fix: Store the authority pubkey in the `Configuration` account and provide an `update_authority` instruction restricted to the current authority.

## Low: Missing event emission in Rust instructions
- File: `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `withdraw.rs`
- Root cause: The instructions do not emit Anchor `Event` logs for successful deposits/withdrawals. Only `log_outbox_message` (a `msg!`) is used for withdrawals.
- Impact: Reduced auditability and difficulty for off-chain indexers to reliably detect and record deposit/withdrawal events.
- Fix: Define and emit structured Anchor events (`DepositEvent`, `WithdrawalEvent`) in each instruction.

## Informational: Unused or incomplete event logging for outbox messages
- File: `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `log_outbox_message()`
- Root cause: `log_outbox_message` logs a base64-encoded message via `msg!`, but there is no structured event or guarantee that the message reaches the Ethereum mailbox. The message encoding (`WithdrawalMessageSent`) includes `chain_id: "Eclipse"` hardcoded.
- Impact: Off-chain relayers must parse unstructured log output, and the hardcoded chain id may become incorrect if the program is used on a different chain.
- Fix: Emit a structured event (e.g., `MessageSent`) and make `chain_id` configurable in `Configuration`.

## Informational: Mailbox module removal requires exact module address match
- File: `smart-contracts/src/v1/Mailbox.sol`, `removeModule()`
- Root cause: `removeModule` requires both the module id and the exact module address to match. There is no event emitted on removal, and no check that the module is not currently in use.
- Impact: Auditing module changes is harder; removing a module that has pending messages could cause issues.
- Fix: Emit an event (`ModuleRemoved`) and consider checking for pending messages or adding a deactivation delay.

## Informational: Fixed-size accounts waste space and increase rent costs
- File: `eclipse-programs/programs/canonical_bridge/src/state.rs`
- Root cause: `WithdrawalReceipt` and `Configuration` use `size() -> 1024` regardless of actual data needs. This reserves 1 KB per account, increasing rent costs unnecessarily.
- Impact: Higher operational/rent costs; no direct security impact.
- Fix: Calculate exact sizes based on fixed fields and enforce a maximum dynamic field length, or use more compact representations.
