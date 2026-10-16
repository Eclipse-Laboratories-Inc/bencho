"""Run SWE-agent against a historical Eclipse task.

Each attempt gets a fresh checkout of the vulnerable commit with later
history removed, so the remediation commit is not reachable. Hidden tests
and reference patches are not mounted. Wall clock is capped at 60 minutes.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import ROOT, ensure_foundry_remappings, grade, load_task, strip_future_history, worktree  # noqa: E402

ATTEMPT_SECONDS = 60 * 60
MODEL = os.environ.get("ECLIPSE_RL_MODEL", "claude-sonnet-4-5")
SWEAGENT = os.environ.get("SWEAGENT", str(ROOT / ".venv" / "bin" / "sweagent"))
COST_LIMIT = os.environ.get("ECLIPSE_RL_COST_LIMIT", "12")
AGENT_CONFIGS = [
    ROOT / "repos" / "SWE-agent" / "config" / "default.yaml",
    ROOT / "environment" / "agent.yaml",
]
if "claude" in MODEL:
    AGENT_CONFIGS.append(ROOT / "environment" / "claude.yaml")
if "Inkling" in MODEL or "inkling" in MODEL:
    AGENT_CONFIGS.append(ROOT / "environment" / "inkling.yaml")


def agent_checkout(task: dict, attempt: int) -> Path:
    source = worktree(task["base_commit"])
    dest = ROOT / "results" / "work" / task["id"] / f"attempt-{attempt}"
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "--no-local", str(source), str(dest)], check=True)
    subprocess.run(["git", "-C", str(dest), "checkout", "--detach", task["base_commit"]], check=True)
    strip_future_history(dest)
    ensure_foundry_remappings(dest)
    # SWE-agent refuses a dirty tree. An orphan commit keeps the remapping edits
    # and the removal of tracked secret files, and drops the parent commit that
    # still contained those files. Origin is a bare repo of only this commit, so
    # `git fetch` during reset cannot see the later remediation.
    subprocess.run(["git", "-C", str(dest), "checkout", "--orphan", "sandbox"], check=True)
    subprocess.run(["git", "-C", str(dest), "add", "-A"], check=True)
    subprocess.run(
        ["git", "-C", str(dest), "rm", "-r", "--cached", "--ignore-unmatch", ".env", ".envrc"],
        check=True,
    )
    subprocess.run(
        [
            "git",
            "-c",
            "user.email=eclipse-rl@local",
            "-c",
            "user.name=Eclipse RL",
            "-C",
            str(dest),
            "commit",
            "-m",
            "sandbox: vulnerable tree with Foundry remappings",
        ],
        check=True,
    )
    subprocess.run(["git", "-C", str(dest), "checkout", "--detach", "HEAD"], check=True)
    subprocess.run(["git", "-C", str(dest), "branch", "-D", "sandbox"], check=True)
    subprocess.run(["git", "-C", str(dest), "reflog", "expire", "--expire=now", "--all"], check=True)
    subprocess.run(["git", "-C", str(dest), "gc", "--prune=now"], check=True)
    bare = dest / ".origin-base.git"
    subprocess.run(["git", "init", "--bare", str(bare)], check=True)
    subprocess.run(["git", "-C", str(bare), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
    subprocess.run(["git", "-C", str(dest), "remote", "add", "origin", "./.origin-base.git"], check=True)
    subprocess.run(["git", "-C", str(dest), "push", "origin", "HEAD:refs/heads/main"], check=True)
    return dest


def run_attempt(task: dict, attempt: int) -> dict:
    checkout = agent_checkout(task, attempt)
    out = ROOT / "results" / "trajectories" / task["id"] / f"attempt-{attempt}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    issue = task["dir"] / "issue.md"
    started = time.time()
    problem_id = f"{task['id']}-attempt-{attempt}"
    cmd = [
        SWEAGENT,
        "run",
        *[arg for path in AGENT_CONFIGS for arg in ("--config", str(path))],
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
        str(issue),
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
    log_text = log_path.read_text(errors="replace") if log_path.exists() else ""
    pred = out / problem_id / f"{problem_id}.pred"
    patch_path = out / "model.patch"
    submission = None
    if pred.exists():
        submission = json.loads(pred.read_text()).get("model_patch")
        if submission:
            patch_path.write_text(submission)
    reward = None
    if submission:
        report = grade(task, task["base_commit"], patch_path)
        reward = report["reward"]
        (out / "grade.json").write_text(json.dumps({k: v for k, v in report.items() if k != "log"}, indent=2) + "\n")
        (out / "grade.log").write_text(report["log"])
    return {
        "task": task["id"],
        "attempt": attempt,
        "model": MODEL,
        "seconds": round(elapsed, 1),
        "exit_code": proc.returncode,
        "timed_out": False,
        "patch": str(patch_path) if submission else None,
        "reward": reward,
        "log_tail": log_text[-2000:],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Run SWE-agent on Eclipse audit tasks")
    parser.add_argument("--task", action="append", help="Task id. Repeatable. Default: all 10.")
    parser.add_argument("--attempts", type=int, default=5)
    args = parser.parse_args()
    if not Path(SWEAGENT).exists() and shutil.which(SWEAGENT) is None:
        raise SystemExit(f"sweagent not found at {SWEAGENT}. Install SWE-agent into .venv first.")
    tasks = [load_task(task_id) for task_id in args.task] if args.task else [
        load_task(path.parent.name) for path in sorted(ROOT.glob("tasks/eclipse-*/task.json"))
    ]
    rows = []
    out_path = ROOT / "results" / "individual_runs.jsonl"
    with out_path.open("a") as handle:
        for task in tasks:
            for attempt in range(1, args.attempts + 1):
                print(f"{task['id']} attempt {attempt}")
                try:
                    row = run_attempt(task, attempt)
                except subprocess.TimeoutExpired:
                    row = {
                        "task": task["id"],
                        "attempt": attempt,
                        "model": MODEL,
                        "seconds": ATTEMPT_SECONDS,
                        "timed_out": True,
                        "patch": None,
                    }
                rows.append(row)
                handle.write(json.dumps(row) + "\n")
                handle.flush()
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
