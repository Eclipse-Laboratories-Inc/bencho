## Critical: EtherBridge deposit sends wrong amount to treasury

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 127)

**Root cause:** After computing `lamportAmount = amount / WEI_PER_GWEI`, the contract sends `message.amount` (the lamport value) instead of `amount` (wei) to the treasury: `(bool success,) = payable(address(treasury)).call{value: message.amount}("");`. This transfers ~1/1e9 of the intended ETH.

**Impact:** Users lock almost no ETH; the bridge is effectively broken and deposits are lost/value stolen by misrouting.

**Fix:** Send `amount` (wei) to treasury: `.call{value: amount}("")`.

## Critical: EtherBridge validSender modifier is a no-op

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `validSender()` modifier (line 61-64) and `deposit()` (line 108)

**Root cause:** The modifier is invoked as `validSender(msg.sender)`, comparing `msg.sender == msg.sender` which always passes. It does not restrict who can deposit.

**Impact:** Any address can deposit, defeating intended sender validation.

**Fix:** Remove the useless modifier or enforce a real sender whitelist if needed.

## Critical: Mailbox nonce generation is predictable and weak

**File:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 201-206)

**Root cause:** Uses `block.timestamp`, `block.difficulty` (post-merge zero on PoS), `msg.sender`, and `nonceCounter`. `block.difficulty` is 0, making the nonce highly predictable. Only 64 bits also increases collision risk.

**Impact:** Relayer signatures/replay protection can be bypassed; nonces can be guessed or replayed.

**Fix:** Use a cryptographically secure random source and store/reject nonces properly.

## Critical: Registry unregisterContract fails to delete contract type

**File:** `smart-contracts/src/v1/Registry.sol`, `unregisterContract()` (line 39-48)

**Root cause:** It deletes `identifierAddress` and `addressIdentifier` but leaves `addressContractType[contractAddress]` intact.

**Impact:** After unregistering, `getContractType()` returns stale data, which can mislead router/module access controls.

**Fix:** Add `delete addressContractType[contractAddress];`.

## High: EtherBridge deposit does not send fee anywhere

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 101-131)

**Root cause:** The fee (`fee`) is included in `msg.value` check (`correctDepositValue`) but never transferred out. It stays in the contract but there is no mechanism to withdraw fees.

**Impact:** Fees accumulate with no reclaim path; contract design is broken.

**Fix:** Transfer `fee` to treasury or a designated fee collector.

## High: Mailbox sendMessage is public and lacks identifier validation

**File:** `smart-contracts/src/v1/Mailbox.sol`, `sendMessage()` (line 174-183)

**Root cause:** It is `public` (not `external`) and only requires `onlyRouter`, but doesn't verify the receiver identifier length or chain id properly for the actual relayed message structure.

**Impact:** Potential misuse if called directly by router with unexpected parameters.

**Fix:** Make `external` and enforce full validation on `receiver_`.

## High: Solana withdraw lacks authorization and validates nothing

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`

**Root cause:** Any signer can call `withdraw`, initialize a `WithdrawalReceipt`, and trigger a SOL transfer to `RELAYER_PUBKEY`. There is no verification of `destination_address`, `amount`, or nonce uniqueness/replay protection.

**Impact:** Anyone can withdraw SOL to the relayer account by crafting arbitrary receipts.

**Fix:** Verify the withdrawal nonce hasn't been used and that the signer is authorized.

## High: Solana deposit lacks `to` validation and uses empty signer seeds

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

**Root cause:** The `to` account has no validation (`/// CHECK` only), and `invoke_signed` uses `&[]` (no seeds), meaning the program does not actually sign the transfer. The relayer just sends SOL from themselves.

**Impact:** No real bridge authorization; SOL moves from relayer without program-level constraints.

**Fix:** Add `to` validation and use proper PDA seeds in `invoke_signed`.

## Medium: EtherBridge withdraw uses raw call without reentrancy guard on treasury

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `withdraw()` (line 137-151)

**Root cause:** `treasury.withdraw()` uses `.transfer()` inside treasury, which is okay, but the `onlyRouter` and `nonReentrant` on EtherBridge don't extend to the treasury's own logic. The treasury owner is the bridge, so it's okay, but design is fragile.

**Impact:** If treasury logic changes, could introduce reentrancy.

**Fix:** Ensure treasury withdraw uses `call` with checks or keeps `transfer` and verifies state before/after.

## Medium: Router routeIncomingMessage uses low-level call without gas limits

**File:** `smart-contracts/src/v1/Router.sol`, `routeIncomingMessage()` (line 47-63)

**Root cause:** `(bool success,) = actualAddress.call(message);` forwards all available gas. A malicious module could execute arbitrary code and exhaust gas.

**Impact:** Denial of service or unexpected behavior on incoming messages.

**Fix:** Use `.call{gas: ...}(message)` with a reasonable gas limit.

## Medium: Registry does not prevent duplicate identifier registrations

**File:** `smart-contracts/src/v1/Registry.sol`, `registerContract()` (line 24-35)

**Root cause:** It allows overwriting an identifier with a different address or type without emitting an update-specific event or revoking old mappings properly (though it does overwrite).

**Impact:** A malicious owner can silently redirect identifiers.

**Fix:** Add checks or emit updates clearly; consider two-step updates.

## Medium: Treasury receive function allows arbitrary ETH without event

**File:** `smart-contracts/src/v1/Treasury.sol`, `receive()` (line 29-30)

**Root cause:** `receive()` is `payable` but emits nothing. Combined with deposit logic errors, ETH can arrive unexpectedly.

**Impact:** Hard to track unexpected ETH.

**Fix:** Emit an event or restrict `receive` usage.

## Low: EtherBridge max deposit amount is very low (1 ether)

**File:** `smart-contracts/src/v1/EtherBridge.sol`, line 22

**Root cause:** `MAX_DEPOSIT_AMOUNT = 1 ether` limits bridge utility severely.

**Impact:** Bridge is impractical for meaningful transfers.

**Fix:** Raise the cap or make it configurable.

## Low: Registry getContractType does not delete stale mapping on unregister

**File:** `smart-contracts/src/v1/Registry.sol`, `getContractType()` (line 65-69)

**Root cause:** Same as critical finding; duplicate observation for the view function.

**Fix:** Ensure `unregisterContract` deletes `addressContractType`.

## Low: Mailbox generateRandomNonce is public and callable by anyone

**File:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 201-206)

**Root cause:** The function is `public`, allowing anyone to advance `nonceCounter` and influence nonce generation.

**Impact:** Can manipulate nonce state.

**Fix:** Make it `internal` and call only from `mailOutgoingMessage`.

## Low: EtherBridge correctWithdrawValue does not verify amount against balance before treasury call

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `withdraw()` (line 144)

**Root cause:** It checks treasury balance but only after `onlyRouter` and `correctWithdrawValue`. The order is fine, but `correctWithdrawValue` only checks `<= MAX_WITHDRAW_AMOUNT`, not actual balance.

**Impact:** Withdrawal fails at runtime rather than being rejected cleanly if underfunded.

**Fix:** Keep the balance check; it is present but could fail gracefully.

## Low: Solana deposit receipt size is hardcoded and may overflow

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`, `DepositReceipt::size()` (line 51-57)

**Root cause:** Size is manually computed. Any change to fields can cause miscalculation.

**Impact:** Account corruption if fields change.

**Fix:** Derive size from serialized data or use Anchor's `init` with computed size.

## Low: Solana withdraw receipt size is arbitrarily large (1024 bytes)

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`, `WithdrawalReceipt::size()` (line 38-40)

**Root cause:** Hardcoded to 1024 bytes regardless of `String` length, which is dynamic.

**Impact:** Wasted rent; potential serialization issues.

**Fix:** Compute size based on actual `String` length or cap it properly.

## Informational: EtherBridge estimateFee uses deprecated tx.gasprice naming

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `estimateFee()` (line 167-169)

**Root cause:** `tx.gasprice` is deprecated in newer Solidity; `tx.gasprice` still works in 0.8.21 but should be `tx.gasprice` (same). Not a real issue.

**Fix:** Consider using `block.basefee` or documenting.

## Informational: Router does not use registry contract type for module checks consistently

**File:** `smart-contracts/src/v1/Router.sol`, `_isModuleContract()` (line 75-78)

**Root cause:** Relies solely on registry mapping, which could be stale if unregister is broken.

**Fix:** Defensive coding; not a separate vulnerability.

