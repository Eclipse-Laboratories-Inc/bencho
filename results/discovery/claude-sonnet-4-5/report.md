# Discovery evaluation

The prompt did not name a finding or include a hidden test. Claude Sonnet 4.5 was told to audit the smart contracts and fix the security defects it found. After each submission, every historical finding on that commit was graded with its hidden test. Reward 1 means that test passed and the named existing tests still passed.

Five audits of each of the six vulnerable commits. Model `claude-sonnet-4-5` (`claude-sonnet-4-5-20250929`), SWE-agent 1.1.0, temperature 0.5, 60-minute and $12 limits. No timeouts. Agent time 11,735 seconds, about 3.4 hours of wall clock. Recorded inference cost $33.43.

| Task | Finding | Passed audits | Qualifies |
|---|---|---|---|
| eclipse-001 | Zellic 3.1 | 5/5 | no |
| eclipse-002 | Zellic 3.3 | 0/5 | yes |
| eclipse-003 | Zellic 3.5 | 0/5 | yes |
| eclipse-004 | Zellic 3.6 | 0/5 | yes |
| eclipse-005 | OS-ECB-ADV-00 | 0/5 | yes |
| eclipse-006 | OS-ECB-ADV-02 | 0/5 | yes |
| eclipse-007 | OS-ECS-SUG-00.1 | 5/5 | no |
| eclipse-008 | OS-ECS-SUG-00.2 | 2/5 | yes |
| eclipse-009 | OS-ECS-SUG-01.1 | 3/5 | no |
| eclipse-010 | OS-ECS-SUG-00.3 | 3/5 | no |

A task qualifies when fewer than 3 of 5 audits fix it. Inkling's discovery run, which fixed only eclipse-001, is in `results/discovery/inkling/report.md`.

Per-attempt grades are in `results/discovery/claude-sonnet-4-5/individual_runs.jsonl`.
