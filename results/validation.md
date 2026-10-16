# Validation (post-hardening, 2026-10-16)

Runs are Harbor jobs under `.work/` (not committed). Graders were hardened
(`audits/GRADER_AUDIT.md`) and task trees regenerated after the leakage sweep
(`audits/LEAKAGE_AUDIT.md`) before these runs.

| Check | Result |
|---|---|
| oracle, `harbor/fix` (3 tasks) | every finding 1, regression 1, reward 1.0 |
| nop, `harbor/fix` (3 tasks) | every finding 0, regression 1, reward 0.0 |
| oracle, `harbor/report` (5 tasks) | reward 1.0 on every task |
| nop, `harbor/report` (5 tasks) | reward 0.0 on every task |
| spot, Claude Sonnet 4.5, 1 attempt/fix audit | 001, 004, 007, 008, 010 fixed (5/10); no audit fully solved; no regressions |
| spot, Inkling, 1 attempt/fix audit | 001, 008 fixed (2/10); no audit fully solved; one regression on ottersec-2024-07 |

Commands: `scripts/run_harbor_eval.sh oracle|nop fix|report` (validation),
and Harbor `run -p harbor/fix -k 1` per model (spot, output `.work/spot/`).
