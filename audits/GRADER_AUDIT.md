# Grader hardening audit (2026-10-16)

Every grader in `audits/*/eclipse-*/` was re-read against its `audit.toml`
finding, its `ticket.md`, and its reference `fix.patch`. Rule: a grader must
(1) fail on the audited tree for the stated defect, (2) pass on the reference
fix, (3) not give full credit for a partial fix, (4) not reject a remediation
the auditor/ticket accepts, and (5) include at least one keep-working test so
closing the hole by breaking the feature does not score.

| Finding | Defect found in grader | Hardening |
|---|---|---|
| eclipse-001 | Single deposit amount (min only) | Added a 3x-min deposit and asserted only the fee stays in EtherBridge |
| eclipse-002 | Single amount (5 lamports) | Added a 123-lamport conversion case |
| eclipse-003 | No keep-working case | Added non-zero recipient withdraw and non-empty `mailOutgoingMessage` success cases. Note: `Mailbox.initialize` already has `addressIsSet(_relayer)` on the audited tree, so the ticket's 2 checks are the full graded scope |
| eclipse-004 | No replay case | Added replayed-nonce revert (ticket requires it) |
| eclipse-005 | `assertGe` accepted an arbitrarily large `MIN_DEPOSIT` | Added `test_keep_minDepositIsNotExcessive` (<= 2x rent-exempt requirement; reference is ~1.6x) and mirrored the bound in `ticket.md` |
| eclipse-006 | No access-control keep case | Added unauthorized-sender revert |
| eclipse-007 | No negative case | Added insufficient-balance and fee>amount reverts |
| eclipse-008 | Cryptic equality assert; no re-use case | `assertFalse`, plus cancelled-id reauthorization and non-canceller revert |
| eclipse-009 | Single happy path | Added pays-exactly-once (second claim reverts) and unauthorized-claim revert |
| eclipse-010 | Enforced only one of the auditor's two accepted remediations (reject-at-authorize); keep-test assertion was near-tautological | Rewrote as a disjunctive test: authorize-reverts (reference) OR authorized-and-claimable paying `amountWei-feeWei`. Fixed keep-test to `assertTrue(withdrawMsgIdProcessed)` |

Totals after hardening: 25 tests across 10 graders (was 13).
