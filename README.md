# Eclipse Canonical Bridge — Security Benchmark (`bencho`)

Ten historical security-audit findings from the Eclipse canonical bridge ([`Eclipse-Laboratories-Inc/syzygy`](https://github.com/Eclipse-Laboratories-Inc/syzygy)), packaged both in **Harbor format** (`harbor/eclipse-001` .. `harbor/eclipse-010`) and as a standalone **Foundry / SWE-agent evaluation suite** (`tasks/`, `scripts/`).

See [`harbor/README.md`](harbor/README.md) for the Harbor package structure, snapshot grouping, and hardening details.

## Headline Evaluation Results (Claude Sonnet 4.5 vs. Inkling)

We evaluated `claude-sonnet-4-5` (`claude-sonnet-4-5-20250929`) and Thinking Machines `thinkingmachines/Inkling` under two regimes:

1. **Open-ended discovery audit (Harbor prompt — no finding disclosed)**: The agent receives only the vulnerable smart-contract tree and a general instruction to audit the contracts for security defects and patch what it finds. No audit notes, finding titles, or hidden tests are shown to the agent.
2. **Ticketed repair (finding disclosed)**: The agent is given an engineering ticket describing the specific audit finding.

A task qualifies as sufficiently hard when **fewer than 3 of 5** attempts score reward `1` (`< 60%` pass rate).

| Task | Snapshot | Audit & Finding | Defect Summary | Discovery: Inkling (5 runs) | Discovery: Claude Sonnet 4.5 (5 runs) | Ticketed Repair: Inkling / Claude | Status |
|---|---|---|---|---|---|---|---|
| `eclipse-001` | `70b57c233347` | Zellic 3.1 | `EtherBridge.deposit` forwards `message.amount` (lamports) instead of `amount` (wei) to `Treasury` | 5/5 | 5/5 | 5/5 / 5/5 | Re-calibrating (in-tree `specs/v1/EtherBridge.md` leak removed in `harbor/`) |
| `eclipse-002` | `70b57c233347` | Zellic 3.3 | `EtherBridge._withdraw` passes lamports to `Treasury.withdraw` without `* 1e9` wei conversion | **0/5** | **0/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-003` | `70b57c233347` | Zellic 3.5 | Missing zero-recipient / empty-destination validation in `EtherBridge` and `Mailbox` | **0/5** | **0/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-004` | `70b57c233347` | Zellic 3.6 | `Mailbox.receiveMessage` marks nonce after external `router` call | **0/5** | **0/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-005` | `bcbec05047af` | OtterSec `OS-ECB-ADV-00` | `MIN_DEPOSIT` omits 128-byte Solana account storage overhead in rent calculation | **0/5** | **0/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-006` | `bcbec05047af` | OtterSec `OS-ECB-ADV-02` | `Mailbox.sendMessage` emits `ethereumChainId` instead of `eclipseChainId` in `MessageSent` | **0/5** | **0/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-007` | `061cba3992df` | OtterSec `OS-ECS-SUG-00.1` | `Treasury` balance check requires `amountWei + feeWei` even though fee is deducted from `amountWei` | **0/5** | 5/5 | 5/5 / 5/5 | Held out (solved by Claude) |
| `eclipse-008` | `ffb018a68bdc` | OtterSec `OS-ECS-SUG-00.2` | Cancelling a withdrawal leaves `withdrawMsgIdProcessed` permanently set | **0/5** | **2/5** | 5/5 / 5/5 | **Qualifies** |
| `eclipse-009` | `9b3f09d6a78f` | OtterSec `OS-ECS-SUG-01.1` | `claimWithdrawal` updates withdrawal state to `CLOSED` after external `treasury.withdrawEth` call | **0/5** | 3/5 | 5/5 / 5/5 | Borderline (`0/5` Inkling, `3/5` Claude) |
| `eclipse-010` | `26c409b8c563` | OtterSec `OS-ECS-SUG-00.3` | `authorizeWithdraw` accepts a zero `feeReceiver` address | **0/5** | 3/5 | 5/5 / 5/5 | Borderline (`0/5` Inkling, `3/5` Claude) |

Detailed breakdowns live in:
- [`results/report.md`](results/report.md) — overall evaluation summary
- [`results/discovery/claude-sonnet-4-5/report.md`](results/discovery/claude-sonnet-4-5/report.md) — Claude Sonnet 4.5 discovery audit report & per-attempt JSONL
- [`results/discovery/inkling/report.md`](results/discovery/inkling/report.md) — Inkling discovery audit report & per-attempt JSONL
- [`results/report-claude-sonnet-4-5.md`](results/report-claude-sonnet-4-5.md) — Claude Sonnet 4.5 ticketed repair report
- [`results/rejected_findings.md`](results/rejected_findings.md) — candidate findings excluded during task validation

## Repository Layout

```
harbor/eclipse-00N/  Self-contained Harbor task directories (pinned Dockerfile, non-root, no-network, sha256 anti-tamper verifier)
tasks/eclipse-00N/   Task metadata, hidden Foundry grader, and isolated reference patch
scripts/             Harbor exporter, task validator, grader, and evaluation runners
swesmith/            SWE-smith pin (9b74ac0) and Solidity profile
environment/         SWE-agent Foundry container and model configs
results/             Validation logs and evaluation reports (Claude Sonnet 4.5 & Inkling)
```

## Running Harbor Tasks

Verify the oracle patch on a Harbor task:

```bash
harbor run -p harbor/eclipse-001 -a oracle
```

Run Claude Sonnet 4.5 or Inkling across all 10 Harbor tasks:

```bash
./scripts/run_harbor_eval.sh claude
./scripts/run_harbor_eval.sh inkling
```
