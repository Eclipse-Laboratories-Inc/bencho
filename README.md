# bencho: Eclipse bridge audits as agent benchmarks

Harbor tasks built from five published security audits (Zellic, OtterSec, Halborn) of the Eclipse canonical bridge. Each task is a snapshot of the code the auditors reviewed. An agent either fixes the defects, graded by hidden Forge tests plus the project's own test suite, or writes an audit report, graded by a judge model against the auditors' findings.

- [`harbor/README.md`](harbor/README.md): the tasks, reward keys, and verifier hardening
- [`results/report.md`](results/report.md): Claude Sonnet 4.5 and Inkling results
- [`results/rejected_findings.md`](results/rejected_findings.md): auditor findings that have no fix grader

## Layout

```
audits/<audit>/audit.toml      audited commits, scope, and every auditor finding (the report rubric)
audits/<audit>/eclipse-NNN/    per graded finding: hidden Forge test, ticket, reference fix.patch
audits/<audit>/redact.patch    optional: removes in-tree notes that state a finding
templates/                     Dockerfile, verifiers, and instructions shared by every task
scripts/export_harbor.py       generates harbor/ from audits/ and templates/
scripts/run_harbor_eval.sh     runs one agent on one format
scripts/summarize_results.py   writes results/report.md, results/rewards.csv, and results/judged-reports/
harbor/                        generated Harbor tasks (committed)
```

Every evaluation runs through Harbor; there is no other harness. `repos/` holds local clones of `syzygy` and `eclipse-programs`, which the exporter reads. It is gitignored.

## Workflow

```bash
.venv/bin/python scripts/export_harbor.py            # regenerate harbor/
scripts/run_harbor_eval.sh oracle fix                # validate: every finding scores 1
scripts/run_harbor_eval.sh nop report                # validate: empty report scores 0
scripts/run_harbor_eval.sh claude fix                # 5 attempts per task
scripts/run_harbor_eval.sh inkling fix-ticketed
scripts/run_harbor_eval.sh claude report
.venv/bin/python scripts/summarize_results.py
```

The agents are `claude` (Claude Sonnet 4.5), `inkling` (Thinking Machines Inkling through its Anthropic-compatible API), `oracle`, and `nop`. The formats are `fix`, `report`, and `fix-ticketed`. `fix-ticketed` is the fix task with each finding's ticket added to the instruction; it is generated into `.work/` when run and not committed. Keys are read from the gitignored `.env` (`ANTHROPIC_API_KEY`, `TINKER_API_KEY`), and the report judge always uses `ANTHROPIC_API_KEY`.

To add a finding, add an `[[findings]]` entry to the audit's `audit.toml`. If it has a deterministic fix, also add `task = "eclipse-NNN"` and a directory with the Forge test, `ticket.md`, and a `fix.patch` that applies on top of the earlier patches of that audit. Then regenerate and rerun the oracle and nop checks.
