"""Confirm each hidden test fails on A and passes on the isolated fix.

Also reruns the hidden tests on the historical remediated commit when that
tree still builds the grader.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import ROOT, grade, list_tasks  # noqa: E402


def expect(label: str, report: dict, audit: str, preservation: str) -> list[str]:
    errors = []
    for name, status in report["audit"].items():
        if status != audit:
            errors.append(f"{label} audit {name}: got {status}, want {audit}")
    for name, status in report["preservation"].items():
        if status != preservation:
            errors.append(f"{label} preservation {name}: got {status}, want {preservation}")
    return errors


def main() -> None:
    rows = []
    failures = []
    log_dir = ROOT / "results" / "validation"
    log_dir.mkdir(parents=True, exist_ok=True)
    for task in list_tasks():
        task_id = task["id"]
        print(f"== {task_id} on A ==")
        broken = grade(task, task["base_commit"], None)
        (log_dir / f"{task_id}.A.log").write_text(broken["log"])
        failures.extend(expect(f"{task_id} A", broken, "fail", "pass"))

        print(f"== {task_id} reference ==")
        fixed = grade(task, task["base_commit"], task["dir"] / "reference" / "fix.patch")
        (log_dir / f"{task_id}.reference.log").write_text(fixed["log"])
        failures.extend(expect(f"{task_id} reference", fixed, "pass", "pass"))

        print(f"== {task_id} historical B ==")
        historical = grade(task, task["remediated_commit"], None)
        (log_dir / f"{task_id}.B.log").write_text(historical["log"])
        historical_ok = all(status == "pass" for status in historical["audit"].values())
        if not historical_ok:
            failures.append(f"{task_id} B audit statuses {historical['audit']}")

        rows.append(
            {
                "task": task_id,
                "finding": task["finding_id"],
                "reference_valid": all(status == "pass" for status in fixed["audit"].values()),
                "historical_b_passes": historical_ok,
                "a_audit": broken["audit"],
                "reference_reward": fixed["reward"],
            }
        )
        print(json.dumps(rows[-1]))

    summary = ROOT / "results" / "validation.json"
    summary.write_text(json.dumps(rows, indent=2) + "\n")
    if failures:
        print("\n".join(failures))
        raise SystemExit(1)
    print(f"validated {len(rows)} tasks")


if __name__ == "__main__":
    main()
