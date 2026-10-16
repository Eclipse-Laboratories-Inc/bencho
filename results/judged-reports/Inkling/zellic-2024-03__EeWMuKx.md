## Critical: EtherBridge deposit sends incorrect wei amount to treasury

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101)

**Root cause:** The contract computes `lamportAmount = amount / WEI_PER_GWEI` (line 313) and then locks `message.amount` (the lamport value, not wei) into the treasury via `(bool success,) = payable(address(treasury)).call{value: message.amount}("")` (line 374). This sends 1/1e9 of the intended wei to the treasury, effectively losing 99.9999999% of the deposit value.

**Impact:** User deposits are almost entirely lost; treasury receives negligible value.

**Fix:** Lock `amount` wei (`message.amount * WEI_PER_GWEI` or directly `amount`) in the treasury, not the lamport amount.

## Critical: EtherBridge fee not forwarded to treasury

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101)

**Root cause:** `msg.value == amount + fee`, but the treasury call only sends `message.amount` (the lamport-converted amount). The fee portion (`fee`) remains stuck in the EtherBridge contract but is never routed or accounted for separately.

**Impact:** Fees accumulate in the bridge contract instead of being handled correctly.

**Fix:** Ensure both `amount` (wei) and `fee` (wei) are properly accounted for; either send both to treasury or handle fee separately per design.

## Critical: Solana deposit uses empty signer seeds for CPI

**Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()` (line 29)

**Root cause:** `invoke_signed` is called with `&[]` (line 53) as signer seeds, but it should use the PDA seeds (`[b"deposit", eth_deposit_nonce.to_le_bytes().as_ref(), &bump]`) to sign as the deposit receipt account.

**Impact:** The CPI call will fail or is unauthorized; funds cannot be properly transferred.

**Fix:** Pass the correct PDA seeds and bump to `invoke_signed`.

## High: Solana withdraw does not verify relayer or validate transfer

**Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 31)

**Root cause:** The function takes `relayer: AccountInfo` without any address validation (no `address = RELAYER_PUBKEY` check). It also does not verify that `withdrawer` has sufficient lamports before invoking `system_instruction::transfer`.

**Impact:** Any account can call withdraw and potentially drain the withdrawer if the solana runtime allows it, or cause invalid state.

**Fix:** Add `#[account(mut, address = RELAYER_PUBKEY)]` or equivalent validation, and check balances before transfer.

## High: Mailbox generateRandomNonce is predictable and uses deprecated block.difficulty

**Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 201)

**Root cause:** The nonce is derived from `block.timestamp`, `block.difficulty`, `msg.sender`, and `nonceCounter`. `block.difficulty` is deprecated/constant on Ethereum post-merge. The nonce is highly predictable, allowing replay attacks or collision.

**Impact:** Nonce replay or prediction undermines message uniqueness guarantees.

**Fix:** Use a cryptographically secure random source (e.g., `chainlink-vrf` or `prevrandao`) and do not rely on `block.difficulty`.

## High: EtherBridge validSender modifier is a no-op

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `validSender()` (line 61)

**Root cause:** `validSender(msg.sender)` passes `msg.sender` as both the actual and expected sender, so `msg.sender == msg.sender` is always true. The intended check (probably comparing `msg.sender` against a registered or passed sender) is missing.

**Impact:** The modifier provides no access control.

**Fix:** Implement the intended sender validation (e.g., check against an allowed sender list or verify `msg.sender` matches the deposit message sender properly).

## High: Registry unregisterContract misses deleting contract type

**Affected file:** `smart-contracts/src/v1/Registry.sol`, `unregisterContract()` (line 674)

**Root cause:** The function deletes `identifierAddress` and `addressIdentifier` but does not delete `addressContractType[contractAddress]`.

**Impact:** Stale contract type data remains after unregistration, which could affect router/mailbox checks that query by address.

**Fix:** Add `delete addressContractType[contractAddress];`.

## Medium: Mailbox receiveMessage does not verify sendNonce

**Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()` (line 118)

**Root cause:** Only `receiveNonces` is tracked; there is no `sendNonces` check for incoming messages. However, the design expects messages from Eclipse to include a nonce, but the contract does not enforce that the nonce hasn't been used on the sending side. More importantly, `sendMessage` does not emit a verifiable proof that the message was actually routed properly.

**Impact:** Potential replay of messages if the relayer submits duplicate `data_` with the same nonce.

**Fix:** Ensure strict nonce tracking for both directions and validate against replay.

## Medium: Router routeIncomingMessage uses low-level call without return value enforcement beyond require

**Affected file:** `smart-contracts/src/v1/Router.sol`, `routeIncomingMessage()` (line 47)

**Root cause:** `actualAddress.call(message)` (line 767) forwards all available gas and ignores the called contract's return data beyond the boolean `success`. If the called contract returns `false` but doesn't revert, `require(success, ...)` catches it. However, no event is emitted and no granular error handling exists.

**Impact:** Silent failures or unexpected behavior on malformed module responses.

**Fix:** Capture and log return data; consider using a stricter interface call.

## Medium: EtherBridge withdraw does not verify recipient address format

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `withdraw()` (line 137)

**Root cause:** `message.recipient` is used directly without validating it's a non-zero address or within expected format.

**Impact:** Withdrawals could be directed to the zero address, permanently locking funds.

**Fix:** Add `require(message.recipient != address(0), ...)` and optionally validate against an allowlist.

## Medium: Solana deposit does not store amount or validate relayer balance

**Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()` (line 29)

**Root cause:** The function creates a receipt but never writes `amount` to `DepositReceipt`. It also does not check that `from_account` (relayer) has at least `amount` lamports before invoking the transfer.

**Impact:** Invalid receipts and potential failed or unauthorized transfers.

**Fix:** Add `amount` to `DepositReceipt`, and verify `from_account.lamports() >= amount`.

## Medium: Treasury uses transfer instead of call for withdrawals

**Affected file:** `smart-contracts/src/v1/Treasury.sol`, `withdraw()` (line 917)

**Root cause:** `to.transfer(amount)` (line 919) forwards a fixed 2300 gas stipend, which can fail if the recipient is a smart contract that requires more gas (e.g., for logging or further calls).

**Impact:** Withdrawals to smart contract wallets could fail.

**Fix:** Use `(bool success, ) = to.call{value: amount}(""); require(success, ...);`.

## Low: EtherBridge initialize does not validate registry router and registry contract types properly

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `initialize()` (line 328)

**Root cause:** The contract relies on `registry.getAddress("Router")` and `registry.getAddress("Treasury")` without checking that the retrieved contracts are of the expected contract types (unlike Mailbox which uses `_isRouterContract` and `_isRegistryContract`).

**Impact:** Incorrect initialization if registry contains wrong mappings.

**Fix:** Add contract type checks using `registry.getContractType()`.

## Low: Mailbox validEncodedIdentifierLength allows empty bytes

**Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `validEncodedIdentifierLength()` (line 88)

**Root cause:** `require(addr.length <= 32, ...)` allows `length == 0`, which should be invalid for an identifier.

**Impact:** Empty identifiers could be processed incorrectly.

**Fix:** Add `require(addr.length > 0, ...)`.

## Low: Solana withdraw does not include amount in message encoding consistently

**Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 31)

**Root cause:** `Message.amount` is set correctly but the encoded `Data` only includes `nonce`. There is no cross-check that the encoded message amount matches the transfer amount.

**Impact:** Potential inconsistency between on-chain state and off-chain message.

**Fix:** Ensure message encoding and state are consistent; add assertions.

## Low: EtherBridge deposit uses `nonReentrant` but locks before routing

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101)

**Root cause:** The message is routed via `router.routeOutgoingMessage` before the ether is locked in treasury. If the routing call reenters back into `deposit`, the treasury hasn't been updated yet, but `nonReentrant` prevents it. The ordering is correct but fragile.

**Impact:** Low risk due to `nonReentrant`, but ordering should be documented.

**Fix:** Lock funds before routing, or document the ordering explicitly.

## Low: Registry does not emit event on unregister for contract type removal

**Affected file:** `smart-contracts/src/v1/Registry.sol`, `unregisterContract()` (line 674)

**Root cause:** `addressContractType` is not cleared (see High finding), so even if cleared, no event reflects it.

**Impact:** Off-chain indexers may miss state changes.

**Fix:** Clear mapping and keep events consistent.

## Informational: Solana program uses hardcoded RELAYER_PUBKEY

**Affected file:** `eclipse-programs/programs/canonical_bridge/src/lib.rs`, line 11

**Root cause:** `pub const RELAYER_PUBKEY: Pubkey = pubkey!(...)` is compiled in. Changing relayer requires program upgrade/redeploy.

**Impact:** Operational rigidity.

**Fix:** Make relayer configurable via program initialization or upgradeable config.

## Informational: Missing event emission in Router routeIncomingMessage

**Affected file:** `smart-contracts/src/v1/Router.sol`, `routeIncomingMessage()` (line 47)

**Root cause:** No event is emitted after successfully routing an incoming message.

**Impact:** Off-chain monitoring is harder.

**Fix:** Emit an event like `MessageRouted(identifier, message)`.

## Informational: EtherBridge does not emit event on treasury lock

**Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101)

**Root cause:** Only `Deposited` event is emitted; no event confirms treasury balance change.

**Impact:** Off-chain reconciliation is more complex.

**Fix:** Emit a `FundsLocked` or similar event after the treasury transfer succeeds.

## Informational: Mailbox does not emit event for sendNonce updates

**Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `mailOutgoingMessage()` (line 154)

**Root cause:** `sendNonces` is updated but no event is emitted.

**Impact:** Harder to track outbound message nonces off-chain.

**Fix:** Emit an event upon nonce update.
