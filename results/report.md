# Evaluation report

All 50 Inkling repair attempts, given an engineering ticket for one finding, returned reward 1. No task qualifies on that setup. A task qualifies when fewer than 3 of 5 independent attempts score reward 1. A later discovery run, with no finding in the prompt, is in `results/discovery/inkling/report.md` for Inkling and `results/discovery/claude-sonnet-4-5/report.md` for Claude Sonnet 4.5. Inkling fixed only eclipse-001. Claude fixed eclipse-001 and eclipse-007 on all five audits, eclipse-009 and eclipse-010 on three, and eclipse-008 on two.

The finished Claude Sonnet 4.5 evaluation, also 5/5 on every task, is in `results/report-claude-sonnet-4-5.md`.

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

`reference_valid` means the hidden audit test fails on the vulnerable commit, the named preservation tests pass there, and both pass after `reference/fix.patch`. `historical_b_passes` means the hidden audit test passes on the historical remediation commit.

## Agent runs

| Item | Value |
|---|---|
| Agent | SWE-agent 1.1.0 (`3ea751c087f32b16e039a2233dd6eefecef325d5`) |
| Runtime | SWE-ReX 1.4.0 in `eclipse-rl-pilot:foundry` |
| Model | `thinkingmachines/Inkling` via Tinker's Anthropic-compatible API |
| Sampling | temperature 0.5, thinking effort `medium`, `top_p` omitted |
| Limits | 60 minutes and $12 per attempt |
| Timeouts | 0 |
| Agent time | 3,081 seconds across 50 scored attempts |
| Inference cost | $19.19 |

Docker stopped during the first eclipse-009 attempt, before a score was recorded. Those unscored rows were discarded. After Docker was restarted, eclipse-009 and eclipse-010 were run again and both scored 5/5. That rerun took about 11 minutes and $2.35 of the total above.

Per-attempt rows are in `results/individual_runs.jsonl`. Trajectories are in `results/trajectories/`.

## Rejected candidates

See `results/rejected_findings.md`.
