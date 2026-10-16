# Security Audit Report

## Critical: EtherBridge deposit sends less ETH to treasury than locked

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()`

**Root cause / impact:** The deposit computes `lamportAmount = amount / WEI_PER_GWEI`. It then sends `message.amount` (lamports) to treasury, but `msg.value` was `amount + fee` wei. Only a tiny fraction of the deposited wei is locked; the rest remains in the contract. Example: 1 ether deposit sends only 1 wei to treasury.

**Fix:** Send `amount` wei to treasury (`payable(address(treasury)).call{value: amount}("")`) and use lamports only in the routed message.

## Critical: EtherBridge deposit does not validate recipient or lock full amount

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()`

**Root cause / impact:** The function locks only `message.amount` (lamports) instead of `amount`. The remaining `amount - lamportAmount + fee` stays in EtherBridge. Withdrawal logic expects wei amounts, so treasury will be severely underfunded.

**Fix:** Lock the full `amount` wei in treasury; encode lamports only in the message.

## Critical: Mailbox generateRandomNonce relies on predictable block values

**File:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()`

**Root cause / impact:** Nonce uses `block.timestamp`, `block.difficulty` (deprecated and predictable), `msg.sender`, and a counter. Nonces are not random; replay or collision is feasible. Additionally `nonceCounter` is not reset, but that is minor compared to predictability.

**Fix:** Use `keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, nonceCounter))` or an off-chain random beacon; never rely solely on `block.difficulty`.

## High: Mailbox receiveMessage does not verify nonce before routing

**File:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()`

**Root cause / impact:** `router.routeIncomingMessage()` is called before `receiveNonces[secParam.nonce]` is updated. If routing reverts, the nonce is never set but the message may have partially executed (e.g., external call). More importantly, the nonce check is after decoding but the message is routed before the nonce is marked used — though here it is before update. Actually the nonce check happens before routing, so replay is prevented, but if routing fails the nonce is not burned. However, a malicious relayer could call with a valid nonce, cause routing to revert, then replay with same nonce (since nonce not burned). That is a replay issue.

Wait, the nonce is checked before routing (`require(receiveNonces... == false)`). If routing reverts, the nonce is not set to true, so replay is possible. A relayer could replay the same valid message after a failed routing.

**Fix:** Set `receiveNonces[secParam.nonce] = true` before `router.routeIncomingMessage()` (use checks-effects-interactions, or at least burn the nonce before external call). Also consider reentrancy on router call.

## High: Mailbox sendNonces never used / nonce collision

**File:** `smart-contracts/src/v1/Mailbox.sol`, `mailOutgoingMessage()`

**Root cause / impact:** `sendNonces` mapping is written but never read; no replay protection exists for outgoing messages. Nonces are generated with a weak PRNG, making collisions likely.

**Fix:** Verify nonces or use sequential nonces with a mapping check; implement replay protection on both directions.

## High: EtherBridge withdraw sends amount but treasury uses wei

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `withdraw()`

**Root cause / impact:** The `WithdrawMessage.amount` is expected in wei (per event docs), but `deposit` computes `lamportAmount = amount / WEI_PER_GWEI`. The treasury holds wei, but the routed message carries lamports. Withdrawal passes `message.amount` directly to treasury, which expects wei. This creates a mismatch: if a user deposits 1500000 gwei, treasury gets 1500000 wei (~1.5M wei = 1.5e-12 ether), but withdrawal asks for 1500 wei? Actually lamport = amount / 1e9. For 1.5M gwei = 1.5e-12 ether, lamport is 1. So treasury holds ~1 wei but withdrawal asks for 1 wei — coincidentally close, but the logic is inconsistent. More importantly, `deposit` sends only lamports to treasury, not the full wei, which is the critical bug.

**Fix:** Make amount units consistent; document whether treasury holds wei or lamports.

## High: Router routeIncomingMessage lacks access control on target call

**File:** `smart-contracts/src/v1/Router.sol`, `routeIncomingMessage()`

**Root cause / impact:** Any address registered as MODULE can be called with arbitrary `message` (calldata). There is no validation on the target contract's behavior. A malicious module could reenter the mailbox or steal funds.

**Fix:** Restrict module contracts to trusted implementations; add reentrancy guards around external calls; consider using `call` with limited gas or a whitelist.

## High: Registry unregisterContract does not clear contract type

**File:** `smart-contracts/src/v1/Registry.sol`, `unregisterContract()`

**Root cause / impact:** `delete identifierAddress[identifier]` and `delete addressIdentifier[contractAddress]` are done, but `addressContractType[contractAddress]` is never deleted. After unregistering, `getContractType` will still return the old type because it reads from `addressIdentifier` (empty) then falls through to `addressContractType`. Actually `getContractType` checks `bytes(id).length != 0`; since `id` is empty after delete, it will revert with "Address not registered". So the leftover mapping is harmless but is a state hygiene issue.

**Fix:** Also `delete addressContractType[contractAddress]`.

## High: Treasury withdraw uses transfer instead of call

**File:** `smart-contracts/src/v1/Treasury.sol`, `withdraw()`

**Root cause / impact:** `to.transfer(amount)` forwards only 2300 gas, which breaks contracts that need more gas to receive funds. Also, `transfer` is deprecated in modern Solidity.

**Fix:** Use `(bool success, ) = to.call{value: amount}(""); require(success, ...);`

## High: Mailbox receiveMessage uses abi.decode without length check

**File:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()`

**Root cause / impact:** `abi.decode(data_, (EclipseSecurityParam))` can panic or decode incorrectly if `data_` is shorter than expected. There is no `try/catch` or length validation.

**Fix:** Check `data_.length` before decoding; wrap decode or validate encoding.

## Medium: EtherBridge deposit does not check router contract type

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `initialize()`

**Root cause / impact:** `router` is fetched from registry but `_isRouterContract` is never called. A malicious registry entry could point to a non-router, allowing arbitrary message routing.

**Fix:** Add `_isRouterContract` check in `EtherBridge.initialize()`.

## Medium: EtherBridge validSender modifier is redundant

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()`

**Root cause / impact:** Modifier `validSender(msg.sender)` checks `msg.sender == msg.sender`, which is always true. It provides no security value and suggests missing authorization (e.g., only router or module should call).

**Fix:** Remove the redundant modifier or replace with actual authorization (e.g., `onlyModule` or `onlyRouter`).

## Medium: Solana deposit instruction lacks relayer authorization beyond pubkey

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

**Root cause / impact:** `relayer` account is constrained by `address = RELAYER_PUBKEY` but there is no signature verification for the relayer beyond being that pubkey. The `deposit` instruction uses `invoke_signed` with an empty signer array (`&[]`), meaning the PDA signs but the relayer doesn't provide a valid authorization. Any account matching the pubkey can trigger the instruction.

**Fix:** Require relayer to sign the instruction explicitly and verify the signature.

## Medium: Solana withdraw lacks authorization and uses arbitrary signer

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`

**Root cause / impact:** The `withdrawer` is a `Signer` but there is no check that it is authorized. Anyone can call `withdraw`, create a `WithdrawalReceipt`, and transfer SOL from themselves to the relayer account. The `relayer` account is not verified against `RELAYER_PUBKEY` in the accounts struct (only in deposit).

**Fix:** Add authorization checks (e.g., require `relayer == RELAYER_PUBKEY` and verify `withdrawer` is the correct user or relayer); validate `withdrawal_nonce` is not reused.

## Medium: Solana deposit does not verify nonce reuse

**File:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`

**Root cause / impact:** `eth_deposit_nonce` is used as a seed but there is no check that a `DepositReceipt` with the same nonce already exists. A replay attack could recreate a deposit receipt with an existing nonce.

**Fix:** Before `init`, check that the account derived from the seed does not already exist (`ctx.accounts.deposit_receipt.to_account_info().data_len() == 0`).

## Low: Registry getContractType does not revert consistently

**File:** `smart-contracts/src/v1/Registry.sol`, `getContractType()`

**Root cause / impact:** If `addressContractType[addr]` exists but `addressIdentifier[addr]` was deleted, the function reverts incorrectly. Although the delete in `unregisterContract` is missing the type mapping, the inconsistency is a maintenance risk.

**Fix:** Ensure `unregisterContract` deletes all mappings; add a direct check on `addressContractType`.

## Low: Mailbox onlyRelayer modifier relies on state variable set at init

**File:** `smart-contracts/src/v1/Mailbox.sol`, `onlyRelayer()`

**Root cause / impact:** The relayer is immutable after initialization but there is no mechanism to rotate the relayer. A compromised relayer requires upgrading the contract, which is acceptable but worth documenting.

**Fix:** Consider adding an `updateRelayer` function restricted to owner.

## Low: EtherBridge deposit uses hardcoded gas limits

**File:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()`

**Root cause / impact:** The `router.routeOutgoingMessage{gas: MIN_DEPOSIT_GAS_ONLY_ROUTING}` call uses a fixed gas amount. If routing requires more gas (e.g., due to message complexity), the call will fail.

**Fix:** Allow dynamic gas or use a higher safe limit; document gas assumptions.

## Low: Solana withdrawal receipt uses oversized fixed space

**File:** `eclipse-programs/programs/canonical_bridge/src/state.rs`, `WithdrawalReceipt::size()`

**Root cause / impact:** `size()` returns a fixed 1024 bytes instead of computing the actual size based on `String` lengths. This wastes rent and storage.

**Fix:** Compute dynamic size based on string length and other fields.

## Informational: Missing events for critical state changes

**File:** Multiple contracts

**Root cause / impact:** Several functions (e.g., `Mailbox.mailOutgoingMessage`, `Router.routeIncomingMessage`) emit events but some state changes (nonce updates) don't have dedicated events. This reduces auditability.

**Fix:** Add events for nonce updates and external routing results.

