# Security Audit Report

## Critical: Predictable and manipulable nonce generation in Mailbox
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `generateRandomNonce()`

`generateRandomNonce()` derives the nonce from `blockhash(block.number - 1)`, `block.timestamp`, `block.coinbase`, and the previous nonce. `blockhash`, `timestamp`, and `coinbase` are all miner/validator-controllable, so an attacker can predict or brute-force nonces. Additionally, only the lower 64 bits (`uint64`) are kept, making collisions extremely likely. This undermines replay protection in `receiveMessage` and `sendMessage`.

**Fix:** Use an unpredictable, on-chain entropy source (e.g., Chainlink VRF) or at minimum commit-reveal with a user-supplied secret, and do not truncate to 64 bits from a 256-bit hash.

## Critical: Unvalidated external call to arbitrary module in receiveMessage
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()`

After decoding the nonce, `receiveMessage` performs `module.call(message_)` where `module = $.modulesById[bytes32(sender_)]`. There is no validation that `message_` is an authorized instruction for that module (no function selector allowlisting, no signature check on `message_`). A malicious relayer or anyone who can craft a valid nonce can invoke arbitrary functions on registered modules.

**Fix:** Add authorization checks inside each module, or restrict `message_` to a predefined ABI and validate it before calling.

## Critical: No sender address length or format enforcement before module lookup
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()`

`bytes32(sender_)` casts arbitrary-length `bytes memory` to `bytes32` implicitly via `bytes32(sender_)`. If `sender_` is shorter or longer than 32 bytes, Solidity truncates or pads differently than expected, allowing module lookup collisions.

**Fix:** Enforce `bytesLengthEq32(sender_)` before casting and add `bytes32Initialized(bytes32(sender_))`.

## High: sendMessage ignores chainId and data parameters
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage()`

The first parameter (`bytes memory`) is unnamed and completely ignored. The `data_` parameter (security data / nonce) is also ignored; the function always creates a fresh `EthereumSecurityParam` with a newly generated nonce. This breaks any cross-chain protocol that relies on passing specific chain IDs or security parameters.

**Fix:** Use the `chainId_` parameter to encode the target chain, and either accept the caller-provided nonce in `data_` or clearly document that the mailbox generates it automatically.

## High: EtherBridge deposit calculates amount with truncation
**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

`uint256 amountGwei = amountWei / WEI_PER_LAMPORT;` uses integer division, silently truncating any fractional wei. If a user sends an amount that is not a perfect multiple of `WEI_PER_LAMPORT`, value is lost without error (other than the modulo check which only ensures divisibility, so truncation only happens with very large numbers or if the modulus check is bypassed).

Actually the `validDepositAmount` modifier requires `msg.value % WEI_PER_LAMPORT == 0`, so truncation does not occur under normal operation. However, the division is fragile and should use exact arithmetic assertions.

**Fix:** Assert `amountWei == amountGwei * WEI_PER_LAMPORT` after division.

## High: EtherBridge deposit does not validate mailbox call arguments
**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

The mailbox call passes `""` (empty bytes) for `chainId_` instead of the actual Ethereum chain ID. It also passes an empty `data_` instead of a nonce or security parameter, violating the mailbox's intended interface.

**Fix:** Pass `encodeChainId($.ethereumChainId)` and include a nonce/security parameter in `data_`.

## High: Treasury receive allows arbitrary authorized source
**File:** `smart-contracts/src/v1/Treasury.sol`  
**Function:** `receive()`

`receive()` allows `msg.sender == owner()` to deposit arbitrary ETH labeled as a bridge deposit. This could be abused to inflate deposit records or bypass auditing.

**Fix:** Remove the `owner()` exception or emit a different event for owner deposits.

## High: Solana deposit does not verify deposit nonce uniqueness
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

`deposit()` creates a receipt seeded by `eth_deposit_nonce` but never checks whether an account with that seed already exists. Reusing the same nonce will cause an Anchor `init` failure only if the account exists; but if the program allows overwriting or if initialization is skipped in future versions, replay is possible.

**Fix:** Explicitly check that `deposit_receipt` does not exist (Anchor's `init` does this by default, but the code relies solely on the seed) and enforce nonce monotonicity.

## Medium: Solana withdraw does not verify relayer authorization
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`

`withdrawer` sends SOL to `relayer`, but `relayer` is an `AccountInfo` (not a `Signer`). There is no check that the actual relayer signed the transaction or that the message was authorized. Any user can trigger a withdraw that sends funds to the hardcoded relayer address.

**Fix:** Require the relayer to be a signer and validate a signed message or authorization proof.

## Medium: Withdrawal receipt uses unbounded String
**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`

`WithdrawalReceipt.destination_address` is a `String`, which in Anchor has no length limit. A malicious user could supply an extremely long string, exceeding account size and causing transaction failure or storage bloat.

**Fix:** Use `String` with a length cap (`#[max_len(44)]`) or a fixed-size byte array.

## Medium: Mailbox receiveMessage has no length check on message
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `receiveMessage()`

Only `bytesInitialized(message_)` is enforced, which checks `length > 0`. There is no maximum length, allowing a malicious relayer to pass arbitrarily large messages that could exhaust gas during the module call.

**Fix:** Add a maximum message length check (`require(message_.length <= MAX_LENGTH)`).

## Low: Mailbox uses `addressArrayInitialized` but no `addressInitialized` for single module in addModule
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `addModule()`

`addModule` uses `addressInitialized(module)` which is fine, but it does not check if `moduleId` is non-empty beyond `bytes32Initialized`. The function allows adding a module with a zero-value `moduleId` only if the zero-value module does not exist; however `bytes32Initialized` prevents zero, so this is covered. Low severity.

**Fix:** No action needed; informational only.

## Low: EtherBridge uses `bytes32Initialized(recipient)` but does not enforce Solana address format
**File:** `smart-contracts/src/v1/EtherBridge.sol`  
**Function:** `deposit()`

`recipient` is just a `bytes32`. There is no validation that it represents a valid base58-encoded Solana public key or address.

**Fix:** Add format validation (e.g., length, character set, checksum) for Solana addresses.

## Low: CommonContainer bytesLengthEq32 is overly restrictive for chain IDs
**File:** `smart-contracts/src/v1/CommonContainer.sol`

`bytesLengthEq32` requires exactly 32 bytes. If chain IDs are shorter (e.g., "ethereum" encodes to fewer bytes after ABI encoding as `bytes32`), this is fine because `encodeChainId` produces exactly 32 bytes. No vulnerability.

**Fix:** Informational.

## Low: Mailbox `onlyModule` modifier does not verify module ID matches sender
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `sendMessage()`

`onlyModule` checks `hasRole(MODULE_ROLE, msg.sender)` but does not verify that the module's registered `bytes32` ID matches anything in the message. This is a design choice, not an immediate vulnerability.

**Fix:** Informational.

## Informational: Missing event emission for module removal
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `removeModule()`

No event is emitted when a module is removed, reducing auditability.

**Fix:** Emit an event (`ModuleRemoved(bytes32 moduleId, address module)`).

## Informational: Missing event for mailbox initialization
**File:** `smart-contracts/src/v1/Mailbox.sol`  
**Function:** `initialize()`

No event is emitted upon initialization.

**Fix:** Emit an initialization event.

## Informational: Solana program uses hardcoded pubkeys with compile-time feature flag
**File:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`

`RELAYER_PUBKEY` and `BRIDGE_AUTHORITY_PUBKEY` are hardcoded and selected by a compile-time feature flag (`use_test_authority`). If the feature is accidentally enabled in production, the authority and relayer become public test keys.

**Fix:** Load these from on-chain configuration accounts instead of compile-time constants.

## Informational: Solana deposit does not emit structured event for off-chain tracking
**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

Only an implicit account initialization happens; no structured event is emitted for indexers.

**Fix:** Add an `Event` emission with nonce, recipient, and amount.
