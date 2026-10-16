# Leakage sweep (2026-10-16)

Method: for every generated task tree (3 fix + 5 report), grepped all
Markdown, Solidity, and Rust sources (excluding vendored `lib/`) for auditor
names (Zellic/OtterSec/Halborn), graded-finding ids (`eclipse-NNN`), and
phrasings that state a finding outright ("bug where", "does not behave this
way", "not yet resolved", "known issues", TODO/FIXME in `src/`), then manually
read every README "issues" section, spec note, and in-scope TODO the grep hit.

Findings:

1. `zellic-2024-03` (fix + report): the pre-existing `redact.patch` removed
   the EtherBridge/Treasury note, but the README "issues that are not yet
   resolved" list still contained "Withdraws have not been unit tested" and
   "The project only has a simple integration test for deposits and needs
   more thorough integration testing" — a near-verbatim statement of Zellic
   finding 3.4 (test suite coverage), which is graded in the report task.
   **Fixed:** `audits/zellic-2024-03/redact.patch` now removes those two
   bullets as well.
2. All other trees: no auditor names, finding ids, or notes stating a graded
   finding. `zellic-2024-10`'s "Known Issues and Limitations" covers only a
   coverage-tooling quirk, which is not a rubric item.
3. Reviewed and kept as legitimate auditor context (present in the original
   code a real auditor would receive, not notes about the audit):
   - `specs/` describing *intended* behaviour (e.g. "lock ether in a
     treasury") — the gap between spec and code is the task.
   - `// TODO: optimize here` above `1024`-byte size functions in
     `canonical_bridge/src/state.rs` — an original code comment; the
     allocation size itself is visible in the code.

After regenerating, re-grep the generated trees to confirm finding 1 is gone.
