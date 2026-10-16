# Candidate findings that were not used as tasks

The ten tasks are code defects with a commit that fixes them and a test that fails on the audited tree and passes on the fix. These candidates were reviewed and left out.

| Finding | Why it was rejected |
|---|---|
| Zellic 3.2, missing relayer check on the SVM withdraw | The July 2024 program already constrains `relayer` to `RELAYER_PUBKEY`. No separate remediation commit changes that check. |
| Zellic 3.4, improve the test suite | Process finding, not a behavior change. |
| OtterSec OS-ECB-ADV-01, bump passed as an instruction argument | `eclipse-programs` PR #7 removes the argument but stores `receipt.bump = receipt.bump`, so the canonical bump is still not written. A test that the stored bump equals the PDA bump fails on the remediated commit. |
| OtterSec OS-ECB-SUG-00, Solana log truncation | The suggested change is to switch to CPI events. There is no small deterministic assertion that fails only on the audited tree. |
| OtterSec OS-ECB-SUG-01 items 1–4 and OS-ECB-SUG-02 | Nonce width, empty-array checks, custody design, initializer disabling, and `invoke_signed` style. Halborn later accepted the nonce construction. The others are design notes without an isolated behavioral fix used here. |
| Halborn 7.1, `generateRandomNonce` | Eclipse accepted the risk. No remediation commit. |
| Halborn 7.2–7.4, custom errors and centralization | Acknowledged. No code change. |
| Zellic withdraw 3.1, relayer insolvency on small authorizations | Remediation `46d7612` changes when the fee is taken. It is an economic change, not a unit-testable predicate on a single transaction. |
| Zellic withdraw 3.2, 64-bit withdraw id collisions | Eclipse said production ids are unique. A later uniqueness check is real, but the ten tasks above already cover distinct failure modes. |
| Zellic withdraw 3.3, missing `WITHDRAW_AUTHORITY_ROLE` in `DeployV1` | Eclipse said that script was not used in production. |
| OtterSec October OS-ECS-SUG-01.2, unused variables | No behavior change. |
| `solar-eclipse` and `agave` | Not in the published audits under `Eclipse-Laboratories-Inc/audits`. |
