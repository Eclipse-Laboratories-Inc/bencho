# Security Audit Report — Eclipse Bridge Contracts & Canonical Bridge Program

## Critical: EtherBridge deposit sends lamports instead of wei to treasury

- **Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (line 127)
- **Root cause:** `message.amount` is computed as `amount / WEI_PER_GWEI` (lamports, line 113). The treasury transfer at line 127 uses `message.amount` (`lamportAmount`) as the wei value: `payable(address(treasury)).call{value: message.amount}("")`. Only 1/1e9 of the intended wei is locked.
- **Impact:** Deposits severely under-collateralize the treasury. The fee portion (`fee / WEI_PER_GWEI`) is also not retained; the full `msg.value` is partially lost to the contract or unaccounted for.
- **Fix:** Send `amount` (full wei) to treasury, not `message.amount`. Lock `fee` in the contract or treasury separately, and emit accurate amounts.

## Critical: EtherBridge deposit does not lock fee or retain it

- **Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `deposit()` (lines 101-131)
- **Root cause:** The `fee` is included in `msg.value` (line 47) but `deposit()` only transfers `message.amount` (lamports) to treasury. The fee wei is never moved to treasury or kept in the contract; it remains in the EtherBridge but is not tracked or used.
- **Impact:** Fees accumulate untracked in EtherBridge, making accounting impossible and allowing misuse or loss.
- **Fix:** Explicitly transfer `fee` to a fee-holding account/treasury and emit the correct fee amount.

## Critical: Solana withdraw lacks authorization — anyone can call

- **Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 31)
- **Root cause:** The `Withdraw` accounts struct defines `withdrawer: Signer<'info>` with no constraint linking it to a trusted relayer or to the deposit nonce. There is no `relayer` signer check. Any user can sign a withdrawal, receive SOL at the `relayer` account, and emit a withdrawal message.
- **Impact:** Unauthorized withdrawals of SOL from any user to the hardcoded relayer account, and fake withdrawal messages emitted.
- **Fix:** Require the `withdrawer` to be the authorized relayer pubkey (like `RELAYER_PUBKEY` in deposit) or use a PDA authorization mechanism.

## Critical: Mailbox nonce generation is predictable (not cryptographically secure)

- **Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 201)
- **Root cause:** Uses `block.timestamp`, `block.difficulty` (0 post-merge), `msg.sender`, and `nonceCounter`. The output is fully predictable. Nonces are meant to prevent replay attacks but can be computed by anyone.
- **Impact:** Attackers can pre-compute nonces, craft valid `authoritySignature` (if they compromise relayer key) or replay messages with predictable nonces.
- **Fix:** Use a secure randomness source or an incrementing counter stored in a mapping that is validated by the relayer, rather than deriving from public blockchain state.

## High: Registry unregisterContract does not clear contract type mapping

- **Affected file:** `smart-contracts/src/v1/Registry.sol`, `unregisterContract()` (line 39)
- **Root cause:** `delete identifierAddress[identifier]` and `delete addressIdentifier[contractAddress]` are executed, but `delete addressContractType[contractAddress]` is missing.
- **Impact:** After unregistering, `getContractType()` still returns the old type (line 65-69), which can cause authorization bypasses in Router (`onlyModuleContract` / `onlyMailboxContract`) or Mailbox (`onlyRouter`).
- **Fix:** Add `delete addressContractType[contractAddress];`.

## High: EtherBridge withdraw does not validate sender or recipient

- **Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `withdraw()` (line 137)
- **Root cause:** Only `correctWithdrawValue(message.amount)` is checked. There is no validation that `message.sender` corresponds to an authorized address, that `message.recipient` is non-zero, or that the message came from the mailbox/router.
- **Impact:** Arbitrary withdrawal messages can be processed if the router is tricked into calling `withdraw` with malicious parameters.
- **Fix:** Validate `message.sender` and `message.recipient`, and verify the message origin (e.g., require a mailbox/relayer signature or nonce tracking).

## High: Router routeIncomingMessage performs arbitrary external call without restricting return value

- **Affected file:** `smart-contracts/src/v1/Router.sol`, `routeIncomingMessage()` (lines 47-63)
- **Root cause:** `actualAddress.call(message)` forwards all remaining gas and arbitrary calldata. The return value is not checked for data size; failure only checks boolean success. A malicious module could consume all gas or cause unexpected reentrancy behavior despite `nonReentrant`.
- **Impact:** If a malicious module is registered, it can drain gas, cause denial of service, or attempt reentrancy through the router.
- **Fix:** Use `call` with a gas limit, check return data size, and restrict which contracts can be registered as modules.

## High: Mailbox receiveMessage does not validate sender format or nonce uniqueness properly

- **Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()` (line 118)
- **Root cause:** `validEncodedIdentifierLength(sender_)` only checks `length <= 32`. It does not verify the bytes represent a valid address. The nonce check (`receiveNonces[secParam.nonce] == false`) is basic but relies on predictable nonces.
- **Impact:** Malformed sender identifiers can be passed through to the router, and replay protection is weak.
- **Fix:** Validate that the sender bytes decode to a valid address or match expected format; improve nonce security.

## Medium: EtherBridge deposit validSender modifier is a tautology

- **Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `validSender()` (line 61) and `deposit()` (line 108)
- **Root cause:** `require(msg.sender == sender)` where `sender` is `msg.sender` passed as argument; it always passes and provides no additional authorization.
- **Impact:** False sense of security; no actual sender restriction beyond the external call.
- **Fix:** Remove the useless modifier or implement real authorization (e.g., require a specific contract or signed message).

## Medium: Treasury withdraw uses deprecated `.transfer()` (2300 gas stipend)

- **Affected file:** `smart-contracts/src/v1/Treasury.sol`, `withdraw()` (line 25)
- **Root cause:** `to.transfer(amount)` only forwards 2300 gas. If `to` is a smart contract with a non-empty fallback/receive function that uses more gas, the transfer will revert.
- **Impact:** Withdrawal to smart contract recipients will fail unexpectedly.
- **Fix:** Replace with `(bool success, ) = to.call{value: amount}(""); require(success, "Transfer failed");`

## Medium: Solana deposit uses empty signer seeds for invoke_signed

- **Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs`, `deposit()` (lines 46-53)
- **Root cause:** `invoke_signed` is called with `&[]` (empty seeds), but the `relayer` is the payer. If the program expects PDA-based authorization for the `to` account, it is missing. The `to` account is unconstrained.
- **Impact:** SOL can be transferred to arbitrary `to` accounts without proper authorization, since only the relayer pays but no PDA validates the deposit.
- **Fix:** Ensure `to` is validated (e.g., a derived PDA or registered account) and that transfer authorization is correct.

## Medium: Registry getContractType throws instead of returning a safe default

- **Affected file:** `smart-contracts/src/v1/Registry.sol`, `getContractType()` (line 65)
- **Root cause:** If `bytes(id).length == 0`, it reverts with `"Address not registered"`. Other functions (`getAddress`, `getIdentifier`) also revert rather than return default values.
- **Impact:** This is by design but makes error handling harder and can cause unexpected reverts in router/mailbox authorization checks.
- **Fix:** Document behavior clearly; consider returning `ContractType.OTHER` as a safe default for unregistered addresses.

## Low: Mailbox mailOutgoingMessage uses public generateRandomNonce

- **Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `generateRandomNonce()` (line 201)
- **Root cause:** Function is `public` and not restricted. Anyone can call it to manipulate `nonceCounter` or observe outputs.
- **Impact:** Enables nonce prediction and potential interference with nonce state.
- **Fix:** Restrict to internal/onlyRouter, or remove public visibility.

## Low: EtherBridge estimateFee does not use gas price consistently with sufficientFee

- **Affected file:** `smart-contracts/src/v1/EtherBridge.sol`, `estimateFee()` and `sufficientFee()`
- **Root cause:** `estimateFee()` multiplies by `tx.gasprice`, but `sufficientFee()` uses `MIN_DEPOSIT_GAS * FEE_MARGIN` (no gas price). The fee estimate and the required fee are computed differently.
- **Impact:** Users may calculate an incorrect fee, leading to failed transactions.
- **Fix:** Make both use the same formula (`MIN_DEPOSIT_GAS * FEE_MARGIN * tx.gasprice`).

## Low: Router onlyModuleContract relies solely on registry type, not identity

- **Affected file:** `smart-contracts/src/v1/Router.sol`, `onlyModuleContract()` (line 19)
- **Root cause:** Any contract registered with type `MODULE` can call `routeOutgoingMessage`, even if it was recently registered by a malicious owner or through a compromised registry update.
- **Impact:** If registry control is compromised, arbitrary modules can send messages.
- **Fix:** Add additional authorization checks (e.g., require module contracts to be whitelisted individually or verified at initialization).

## Informational: Solana withdraw emits message without authorization validation

- **Affected file:** `eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs`, `withdraw()` (line 71-79)
- **Root cause:** `log_outbox_message()` emits a base64-encoded `WithdrawalMessageSent` without any validation that the withdrawal was properly authorized. Combined with the missing authorization check, this allows fake outbox events.
- **Impact:** Off-chain relayers could be tricked by fake withdrawal messages if authorization is not enforced elsewhere.
- **Fix:** Only emit after full authorization checks pass.

## Informational: Mailbox receiveMessage does not check msg.value usage

- **Affected file:** `smart-contracts/src/v1/Mailbox.sol`, `receiveMessage()` (line 118)
- **Root cause:** The function is `payable` but never uses `msg.value`. It simply ignores any ETH sent, which could confuse users or be used to send dust.
- **Impact:** Minor confusion; no direct security impact.
- **Fix:** Remove `payable` or handle `msg.value` explicitly.

## Informational: Registry registerContract allows overwriting existing entries without event distinction

- **Affected file:** `smart-contracts/src/v1/Registry.sol`, `registerContract()` (line 24)
- **Root cause:** Overwriting an existing identifier or address updates mappings in place but emits the same `ContractRegistered` event without indicating an update.
- **Impact:** Event logs are ambiguous for auditors.
- **Fix:** Emit different events for new registrations vs updates, or document the behavior.
