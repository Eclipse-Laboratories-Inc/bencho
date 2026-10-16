# OtterSec audit, 2024-07-18

## Medium: Minimum deposit ignores Solana account storage overhead

Location: smart-contracts/src/v1/EtherBridge.sol: MIN_DEPOSIT_LAMPORTS / MIN_DEPOSIT

MIN_DEPOSIT_LAMPORTS is meant to make the deposit receipt on Eclipse rent-exempt, but the rent calculation omits Solana's 128-byte ACCOUNT_STORAGE_OVERHEAD. The minimum deposit can be below the rent-exempt balance, so deposits may not be rent-exempt.

## Low: PDA bump is passed as an instruction argument

Location: eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs, withdraw.rs

deposit and withdraw take the bump for the deposit_receipt and withdrawal_receipt PDAs as a user-supplied argument and store it, instead of using the canonical bump Anchor derives from the account context. A wrong bump can be recorded for the receipt accounts.

## Low: MessageSent emits the Ethereum chain id as the destination

Location: smart-contracts/src/v1/Mailbox.sol: Mailbox.sendMessage

sendMessage emits MessageSent with encodeChainId($.ethereumChainId) as the destination chain id. Messages go to Eclipse, so off-chain consumers that route on this field see the wrong chain; it should be the Eclipse chain id.

## Informational: Outbox message logs can be truncated

Location: eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs: log_outbox_message

log_outbox_message emits the encoded WithdrawalMessageSent with msg!. Solana truncates program logs beyond 10 KB, so large messages lose event data; CPI events avoid the limit.

## Informational: 64-bit outbound nonce can collide

Location: smart-contracts/src/v1/Mailbox.sol: Mailbox.sendMessage / generateRandomNonce

sendMessage takes a uint64 nonce from generateRandomNonce and stores it in sendNonces without checking whether it was already used. A 64-bit random nonce makes collisions plausible at high volume; use a wider nonce and reject reuse.

## Informational: addressArrayInitialized accepts an empty array

Location: smart-contracts/src/v1/CommonContainer.sol: addressArrayInitialized modifier

addressArrayInitialized checks every element is non-zero but never checks that the array is non-empty, so an empty array passes validation.

## Informational: Bridge funds are custodied by the relayer account

Location: eclipse-programs/programs/canonical_bridge: relayer custody design

The relayer account holds custody of all bridged funds on the Solana side. If that key is compromised every bridged fund is lost; a program-derived account governed by program logic would remove that single point of failure.

## Informational: Implementation contracts can be initialized directly

Location: smart-contracts/src/v1/EtherBridge.sol, Treasury.sol, Mailbox.sol: constructors

The upgradeable implementations of EtherBridge, Treasury, and Mailbox do not call _disableInitializers in a constructor, so anyone can call initialize on the implementation address, become its owner, and potentially brick it.

## Informational: invoke_signed used where invoke suffices

Location: eclipse-programs/programs/canonical_bridge/src/instructions/deposit.rs, withdraw.rs

deposit and withdraw call invoke_signed even though no signer seeds are needed; plain invoke is sufficient.

## Informational: Oversized account allocations

Location: eclipse-programs/programs/canonical_bridge/src/state.rs: Configuration::size, WithdrawalReceipt::size

Configuration and WithdrawalReceipt allocate 1024 bytes each, although they need about 11 and 57 bytes. The excess wastes rent.
