"""Grade an agent patch against one Eclipse audit task.

Reward is 1 only when every finding-specific test and every preservation
test passes. Compile errors, a missing test, or a failing test score 0.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import grade, load_task  # noqa: E402


def grade_patch(task_id: str, patch: Path, commit: str | None = None) -> dict:
    task = load_task(task_id)
    report = grade(task, commit or task["base_commit"], patch)
    public = {key: value for key, value in report.items() if key != "log"}
    return public


def main() -> None:
    parser = argparse.ArgumentParser(description="Grade one agent patch")
    parser.add_argument("--task", required=True)
    parser.add_argument("--patch", type=Path, required=True)
    parser.add_argument("--commit", help="Override the vulnerable commit")
    parser.add_argument("--log", type=Path, help="Write the raw forge log here")
    args = parser.parse_args()
    task = load_task(args.task)
    report = grade(task, args.commit or task["base_commit"], args.patch)
    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_text(report["log"])
    public = {key: value for key, value in report.items() if key != "log"}
    json.dump(public, sys.stdout, indent=2)
    sys.stdout.write("\n")
    raise SystemExit(0 if report["reward"] == 1 else 1)


if __name__ == "__main__":
    main()
