# Evaluation report

All 50 scored attempts returned reward 1. No task qualifies. A task qualifies when fewer than 3 of 5 independent attempts score reward 1.

## Results

| Task | Finding | Reference valid | Historical B passes | Successes | Qualifies |
|---|---|---|---|---|---|
| eclipse-001 | Zellic 3.1 | yes | yes | 5/5 | no |
| eclipse-002 | Zellic 3.3 | yes | yes | 5/5 | no |
| eclipse-003 | Zellic 3.5 | yes | yes | 5/5 | no |
| eclipse-004 | Zellic 3.6 | yes | yes | 5/5 | no |
| eclipse-005 | OS-ECB-ADV-00 | yes | yes | 5/5 | no |
| eclipse-006 | OS-ECB-ADV-02 | yes | yes | 5/5 | no |
| eclipse-007 | OS-ECS-SUG-00.1 | yes | yes | 5/5 | no |
| eclipse-008 | OS-ECS-SUG-00.2 | yes | yes | 5/5 | no |
| eclipse-009 | OS-ECS-SUG-01.1 | yes | yes | 5/5 | no |
| eclipse-010 | OS-ECS-SUG-00.3 | yes | yes | 5/5 | no |

`reference_valid` means the hidden audit test fails on the vulnerable commit, the named preservation tests pass there, and both pass after `reference/fix.patch`. `historical_b_passes` means the hidden audit test passes on the historical remediation commit. Logs are in `results/validation/`. Per-attempt rows are in `results/individual_runs.jsonl`. Trajectories are in `results/trajectories/`.

## Agent runs

| Item | Value |
|---|---|
| Agent | SWE-agent 1.1.0 (`3ea751c087f32b16e039a2233dd6eefecef325d5`) |
| Runtime | SWE-ReX 1.4.0 in `eclipse-rl-pilot:foundry` (Forge 1.5.1) |
| Model | `claude-sonnet-4-5` (Anthropic id `claude-sonnet-4-5-20250929`) |
| Sampling | temperature 0.5, `top_p` omitted |
| Limits | 60 minutes and $12 per attempt |
| Timeouts | 0 |
| Agent time | 9,555 seconds across 50 attempts, run sequentially |
| Inference cost | $22.22 |

Tasks 001–004 ran first (about 56 minutes of agent time). The first launch of 005–010 exited in a few seconds because deleting the tracked `.env` left the checkout dirty, so SWE-agent refused to start. Those rows were discarded and not scored. The sandbox now writes an orphan commit that includes the Foundry remapping fix and excludes those secret files. The rerun of 005–010 then scored all 30 attempts (about 103 minutes of agent time, about 110 minutes of wall clock).

## Rejected candidates

See `results/rejected_findings.md`.
