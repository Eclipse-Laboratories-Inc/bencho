"""Adapter: historical audit instances are a vulnerable commit, not a bug patch.

SWE-smith normally checks out a green repository and applies a patch that
introduces a synthetic bug. These tasks already contain the bug at
`base_commit`. Grading therefore:

1. Checks out that commit in a clean worktree.
2. Applies only the agent's patch.
3. Copies the hidden Foundry test into the tree.
4. Runs `forge test` for the finding and the preservation tests.
5. Returns reward 1 only if every selected test passes.

The implementation lives in `scripts/harness.py`.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness import grade, load_task  # noqa: E402


def grade_historical(task_id: str, patch_path: str) -> dict:
    task = load_task(task_id)
    report = grade(task, task["base_commit"], Path(patch_path))
    return {key: value for key, value in report.items() if key != "log"}
