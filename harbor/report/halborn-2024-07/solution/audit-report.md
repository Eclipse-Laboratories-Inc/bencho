# Halborn audit, 2024-07-22

## Low: Predictable nonce from generateRandomNonce

Location: smart-contracts/src/v1/Mailbox.sol: Mailbox.generateRandomNonce, Mailbox.initialize

generateRandomNonce derives nonces from the previous nonce and block properties (blockhash, timestamp, coinbase), and the initial lastNonce is predictable. Future nonces can be predicted, so a receiveMessage call can pre-mark a future nonce as used and cause a denial of service; only the trusted-relayer restriction lowers the severity.

## Informational: Revert strings instead of custom errors

Location: smart-contracts/src/v1 (multiple contracts)

require statements use hard-coded revert strings; custom errors would reduce deployment and runtime gas and give structured error data.

## Informational: Centralization risk: owner-only pause and unpause

Location: smart-contracts/src/v1: pause / unpause

pause and unpause are callable only by the owner, a single point of failure if that key is compromised; multi-signature control is recommended.

## Informational: Centralization risk: unrestricted emergency withdrawal

Location: smart-contracts/src/v1/Treasury.sol: Treasury.emergencyWithdraw

The owner can withdraw any amount of ether from the Treasury at any time with no timelock, limit, or multi-party approval. A compromised or malicious owner can drain user funds.
