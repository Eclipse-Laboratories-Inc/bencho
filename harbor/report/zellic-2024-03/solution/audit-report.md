# Zellic audit, 2024-03-13

## Critical: Deposited ether is not locked in the treasury

Location: smart-contracts/src/v1/EtherBridge.sol: EtherBridge.deposit

deposit converts the deposited wei to lamports for the outgoing message (amount / 1e9) and then forwards message.amount, the lamport value, to the Treasury instead of the full wei amount. Almost all deposited ether stays in EtherBridge, which has no way to withdraw it.

## High: Withdraw instruction does not validate the relayer account

Location: eclipse-programs/programs/canonical_bridge/src/instructions/withdraw.rs: Withdraw accounts

The Solana withdraw instruction transfers the withdrawer's tokens to a caller-supplied relayer account and records a withdrawal for the Ethereum side. Unlike deposit, it has no constraint that the relayer account is the expected relayer address, so an attacker can route tokens to an account they control and still have the Ethereum relayer pay out, draining it for almost no cost.

## Critical: Withdrawal amount is not converted from lamports to wei

Location: smart-contracts/src/v1/EtherBridge.sol: EtherBridge.withdraw

The withdrawal message amount is denominated in lamports (1 lamport = 1 gwei), but withdraw passes it to Treasury.withdraw as wei without multiplying by 1e9. Users receive one billionth of the funds they withdrew.

## Informational: Test suite does not cover negative paths or cross-chain flows

Location: smart-contracts/test (multiple contracts)

Tests only exercise surface-level success paths. Negative cases and every revert branch are untested, especially the cross-chain deposit and withdrawal flows; several findings in this audit would have been caught by simple test cases.

## Low: Missing zero-address and empty-input validation

Location: smart-contracts/src/v1/Mailbox.sol: Mailbox.initialize, Mailbox.mailOutgoingMessage; smart-contracts/src/v1/EtherBridge.sol: EtherBridge.withdraw

Mailbox.initialize does not check that the relayer is non-zero, Mailbox.mailOutgoingMessage does not reject an empty or zero destination (to_), and EtherBridge.withdraw does not reject a zero message.recipient.

## Informational: receiveMessage does not follow checks-effects-interactions

Location: smart-contracts/src/v1/Mailbox.sol: Mailbox.receiveMessage

receiveMessage routes the message to the router (an external call) before marking the nonce as received. nonReentrant prevents exploitation today, but the nonce update should happen before the external call.
