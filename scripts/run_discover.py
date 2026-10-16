"""Audit a vulnerable commit with no finding in the prompt.

One attempt can fix several historical findings that share a commit. Each
finding is graded afterwards with its own hidden test. Those tests are not
in the sandbox.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import ROOT, grade, load_task  # noqa: E402
from run_agent import (  # noqa: E402
    AGENT_CONFIGS,
    ATTEMPT_SECONDS,
    COST_LIMIT,
    MODEL,
    SWEAGENT,
    agent_checkout,
)

PROMPT = ROOT / "environment" / "discover.md"
DISCOVERY_CONFIG = ROOT / "environment" / "discover.yaml"
OUT_ROOT = ROOT / "results" / "discovery" / MODEL.replace("/", "-").replace(":", "-")


def commits() -> list[tuple[str, list[dict]]]:
    grouped: dict[str, list[dict]] = {}
    for path in sorted(ROOT.glob("tasks/eclipse-*/task.json")):
        task = load_task(path.parent.name)
        grouped.setdefault(task["base_commit"], []).append(task)
    return list(grouped.items())


def grade_patch(tasks: list[dict], patch: Path | None) -> list[dict]:
    rows = []
    for task in tasks:
        if patch is None:
            rows.append({"task": task["id"], "reward": None, "error": "no patch"})
            continue
        try:
            report = grade(task, task["base_commit"], patch)
        except RuntimeError as exc:
            rows.append({"task": task["id"], "reward": 0, "error": str(exc)[:500]})
            continue
        rows.append({
            "task": task["id"],
            "reward": report["reward"],
            "audit": report["audit"],
            "preservation": report["preservation"],
        })
    return rows


def run_attempt(commit: str, tasks: list[dict], attempt: int) -> dict:
    label = f"discover-{commit[:12]}"
    checkout = agent_checkout({"id": label, "base_commit": commit}, attempt)
    out = OUT_ROOT / "trajectories" / commit[:12] / f"attempt-{attempt}"
    if out.exists():
        import shutil
        shutil.rmtree(out)
    out.mkdir(parents=True)
    started = time.time()
    problem_id = f"{label}-attempt-{attempt}"
    configs = [*AGENT_CONFIGS, DISCOVERY_CONFIG]
    cmd = [
        SWEAGENT,
        "run",
        *[arg for path in configs for arg in ("--config", str(path))],
        "--agent.model.name",
        MODEL,
        "--agent.model.temperature",
        "0.5",
        "--agent.model.per_instance_cost_limit",
        COST_LIMIT,
        "--agent.model.per_instance_call_limit",
        "0",
        "--env.repo.path",
        str(checkout),
        "--problem_statement.path",
        str(PROMPT),
        "--problem_statement.id",
        problem_id,
        "--output_dir",
        str(out),
    ]
    if "Inkling" in MODEL or "inkling" in MODEL:
        cmd.extend(
            [
                "--agent.model.api_base",
                "https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api",
                "--agent.model.api_key",
                "$TINKER_API_KEY",
                "--agent.model.litellm_model_registry",
                str(ROOT / "environment" / "inkling-costs.json"),
            ]
        )
    log_path = out / "sweagent.log"
    with log_path.open("w") as log:
        proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=ATTEMPT_SECONDS)
    elapsed = time.time() - started
    pred = out / problem_id / f"{problem_id}.pred"
    patch_path = out / "model.patch"
    submission = None
    if pred.exists():
        submission = json.loads(pred.read_text()).get("model_patch")
        if submission:
            patch_path.write_text(submission)
    grades = grade_patch(tasks, patch_path if submission else None)
    (out / "grades.json").write_text(json.dumps(grades, indent=2) + "\n")
    return {
        "commit": commit,
        "attempt": attempt,
        "model": MODEL,
        "tasks": [task["id"] for task in tasks],
        "seconds": round(elapsed, 1),
        "exit_code": proc.returncode,
        "timed_out": False,
        "patch": str(patch_path) if submission else None,
        "grades": grades,
    }


def main() -> None:
    if not Path(SWEAGENT).exists():
        raise SystemExit(f"sweagent not found at {SWEAGENT}")
    rows = []
    out_path = OUT_ROOT / "individual_runs.jsonl"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("a") as handle:
        for commit, tasks in commits():
            names = ",".join(task["id"] for task in tasks)
            for attempt in range(1, 6):
                print(f"{commit[:12]} attempt {attempt} ({names})", flush=True)
                try:
                    row = run_attempt(commit, tasks, attempt)
                except subprocess.TimeoutExpired:
                    row = {
                        "commit": commit,
                        "attempt": attempt,
                        "model": MODEL,
                        "tasks": [task["id"] for task in tasks],
                        "seconds": ATTEMPT_SECONDS,
                        "timed_out": True,
                        "patch": None,
                        "grades": [{"task": task["id"], "reward": None, "error": "timeout"} for task in tasks],
                    }
                rows.append(row)
                handle.write(json.dumps(row) + "\n")
                handle.flush()
                for grade_row in row["grades"]:
                    print(f"  {grade_row['task']} reward={grade_row.get('reward')}", flush=True)
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
