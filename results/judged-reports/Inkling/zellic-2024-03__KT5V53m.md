# Security Audit Report

## Critical: EtherBridge deposit sends wrong value to treasury

**File:** `smart-contracts/src/v1/EtherBridge.sol` — `deposit`

**Root cause:** The contract sends `message.amount` (lamports, after dividing by `WEI_PER_GWEI`) instead of the full `msg.value` deposit amount to the treasury. The fee portion is never locked, and the amount locked is incorrect.

**Impact:** User funds are mis-accounted; fees are lost on deposit; treasury balance does not match intended lock.

**Fix:** Transfer `amount + fee` to the treasury, or lock the full `msg.value` correctly.

---

## Critical: Solana deposit lacks authorization and amount validation

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs` — `deposit`

**Root cause:** `amount` parameter is not validated; any relayer can claim arbitrary amounts. The `to` account is not verified either.

**Impact:** Arbitrary SOL transfer amounts and unverified recipients.

**Fix:** Validate `amount` matches instruction data and enforce recipient checks.

---

## High: Registry unregisterContract leaks mapping entry

**File:** `smart-contracts/src/v1/Registry.sol` — `unregisterContract`

**Root cause:** `addressContractType[contractAddress]` is not deleted when unregistering.

**Impact:** Stale contract type remains mapped, allowing misuse after removal.

**Fix:** Add `delete addressContractType[contractAddress];`.

---

## High: Mailbox nonce is predictable and weak

**File:** `smart-contracts/src/v1/Mailbox.sol` — `generateRandomNonce`

**Root cause:** Uses `block.timestamp`, `block.difficulty` (deprecated in PoS), `msg.sender`, and a counter. Nonce is predictable/manipulable.

**Impact:** Replay protection can be bypassed by predicting nonces.

**Fix:** Use a cryptographic random source or commit-reveal pattern; avoid `block.difficulty`.

---

## High: Mailbox receiveMessage updates nonce after routing

**File:** `smart-contracts/src/v1/Mailbox.sol` — `receiveMessage`

**Root cause:** Nonce is updated (`receiveNonces[...] = true`) after `router.routeIncomingMessage(...)`. If routing reverts, nonce is not set, which is safe; but the ordering still allows message replay if routing behaves unexpectedly with external calls. More importantly, `nonReentrant` is present but routing could call back into mailbox via a malicious module before nonce is updated.

**Impact:** Potential replay or unexpected reentrancy path through router.

**Fix:** Update nonce before calling `router.routeIncomingMessage`.

---

## High: Router routeIncomingMessage uses unprotected low-level call

**File:** `smart-contracts/src/v1/Router.sol` — `routeIncomingMessage`

**Root cause:** `.call(message)` passes arbitrary data and value without specifying value/gas limits; any module can receive arbitrary ETH.

**Impact:** Potential loss of ETH or unexpected behavior if a malicious module is registered.

**Fix:** Use `.call{value: 0, gas: ...}` and restrict value transfers.

---

## High: Solana withdraw lacks authorization and replay protection

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs` — `withdraw`

**Root cause:** Any signer can withdraw any amount to the relayer. No replay check on `withdrawal_nonce`; receipt size is hardcoded incorrectly.

**Impact:** Unauthorized withdrawals; replay of withdrawal messages.

**Fix:** Add authorization checks, replay protection with nonce mapping, and correct account sizing.

---

## Medium: EtherBridge estimateFee ignores gas price dynamics

**File:** `smart-contracts/src/v1/EtherBridge.sol` — `estimateFee`

**Root cause:** Uses `tx.gasprice` without minimum floor and hardcoded constants.

**Impact:** Fee estimates may under-price transactions.

**Fix:** Add minimum gas price floor and consider dynamic gas estimation.

---

## Medium: EtherBridge deposit uses hardcoded gas limit

**File:** `smart-contracts/src/v1/EtherBridge.sol` — `deposit`

**Root cause:** `router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}` forces a fixed gas stipend that may fail if router needs more gas.

**Impact:** Outgoing message routing may fail unexpectedly.

**Fix:** Use a more generous gas limit or estimate gas dynamically.

---

## Medium: Treasury withdraw uses `transfer` instead of `call`

**File:** `smart-contracts/src/v1/Treasury.sol` — `withdraw`

**Root cause:** `to.transfer(amount)` limits gas to 2300, which can break withdrawals to smart contracts.

**Impact:** Withdrawals to contract addresses fail.

**Fix:** Replace with `(bool success, ) = to.call{value: amount}(""); require(success);`.

---

## Medium: Registry getContractType does not check for zero address properly

**File:** `smart-contracts/src/v1/Registry.sol` — `getContractType`

**Root cause:** Uses `bytes(id).length != 0` but does not explicitly require `addr != address(0)`.

**Impact:** Potential ambiguity for unregistered addresses.

**Fix:** Add explicit `require(addr != address(0), ...)`.

---

## Low: Mailbox validSender modifier is redundant

**File:** `smart-contracts/src/v1/Mailbox.sol` — `mailOutgoingMessage`

**Root cause:** `validSender(msg.sender)` checks `msg.sender == msg.sender`, which is always true.

**Fix:** Remove redundant modifier.

---

## Low: Mailbox initialize does not verify router non-zero

**File:** `smart-contracts/src/v1/Mailbox.sol` — `initialize`

**Root cause:** `routerAddress` from registry is not explicitly checked for non-zero before assignment (though `_isRouterContract` checks registry entry).

**Fix:** Explicitly require `routerAddress != address(0)`.

---

## Low: Registry identify mapping may collide

**File:** `smart-contracts/src/v1/Registry.sol`

**Root cause:** No validation that identifier is unique or normalized; same contract could be registered with different identifiers.

**Fix:** Enforce identifier uniqueness and normalization rules.

---

## Low: Solana deposit invoke_signed missing signer seeds

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

**Root cause:** `invoke_signed` is called with empty signer seeds (`&[]`). If `from_account` is a PDA, it requires correct seeds.

**Impact:** Transaction failure if PDA signing is required.

**Fix:** Provide correct PDA seeds if applicable.

---

## Informational: Mailbox ECDSA uses raw `abi.encodePacked` without EIP-712

**File:** `smart-contracts/src/v1/Mailbox.sol` — `receiveMessage`

**Root cause:** Signature hash is built with `keccak256(abi.encodePacked(...))` rather than structured `EIP-712` typed data.

**Fix:** Consider adopting EIP-712 for stronger signature semantics.

---

## Informational: EtherBridge deposit does not emit fee separately

**File:** `smart-contracts/src/v1/EtherBridge.sol`

**Root cause:** `Deposited` event includes fee but the fee is not tracked separately in treasury.

**Fix:** Track fee balance separately or clarify event semantics.

---

## Informational: Solana state size hardcoding

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`

**Root cause:** `WithdrawalReceipt::size()` returns hardcoded `1024` instead of derived size.

**Fix:** Derive size from fields dynamically.

---

## Informational: Router initialize does not check mailbox non-zero

**File:** `smart-contracts/src/v1/Router.sol` — `initialize`

**Root cause:** `mailboxAddress` from registry is not explicitly checked for non-zero.

**Fix:** Add `require(mailboxAddress != address(0), ...)`.
