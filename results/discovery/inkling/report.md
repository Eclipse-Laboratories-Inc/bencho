# Discovery evaluation

The prompt did not name a finding or include a hidden test. Inkling was told to audit the smart contracts and fix the security defects it found. After each submission, every historical finding on that commit was graded with its hidden test. Reward 1 means that test passed and the named existing tests still passed.

Five audits of each of the six vulnerable commits. Model `thinkingmachines/Inkling`, SWE-agent 1.1.0, temperature 0.5, thinking effort `medium`, 60-minute and $12 limits. No timeouts. Agent time 2,897 seconds, about 58 minutes of wall clock. Recorded inference cost $40.78.

| Task | Finding | Passed audits | Qualifies |
|---|---|---|---|
| eclipse-001 | Zellic 3.1 | 5/5 | no |
| eclipse-002 | Zellic 3.3 | 0/5 | yes |
| eclipse-003 | Zellic 3.5 | 0/5 | yes |
| eclipse-004 | Zellic 3.6 | 0/5 | yes |
| eclipse-005 | OS-ECB-ADV-00 | 0/5 | yes |
| eclipse-006 | OS-ECB-ADV-02 | 0/5 | yes |
| eclipse-007 | OS-ECS-SUG-00.1 | 0/5 | yes |
| eclipse-008 | OS-ECS-SUG-00.2 | 0/5 | yes |
| eclipse-009 | OS-ECS-SUG-01.1 | 0/5 | yes |
| eclipse-010 | OS-ECS-SUG-00.3 | 0/5 | yes |

A task qualifies when fewer than 3 of 5 audits fix it.

On `70b57c23`, every attempt changed `message.amount` to `amount` in `EtherBridge.deposit` and then submitted. That is eclipse-001. The other three findings on that commit were untouched. The other commits each got one small patch, such as a duplicate-nonce check or a `feeWei > amountWei` guard, and those patches did not satisfy the hidden tests.

Per-attempt grades are in `results/discovery/individual_runs.jsonl`.
