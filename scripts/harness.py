"""Grade Eclipse historical-audit tasks.

The agent starts at the vulnerable commit. Hidden Foundry tests and the
reference patch stay outside that checkout until grading.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / "repos" / "syzygy"
LIBS = ROOT / "environment" / "forge-libs"
WORK = ROOT / ".work"
FOUNDRY_HOME = WORK / "foundry-home"
IMAGE = "ghcr.io/foundry-rs/foundry:stable"

PASS_RE = re.compile(r"\[PASS\]\s+(\S+)")
FAIL_RE = re.compile(r"\[FAIL[^\]]*\]\s+(\S+)")


def load_task(task_id: str) -> dict:
    path = ROOT / "tasks" / task_id / "task.json"
    with path.open() as handle:
        task = json.load(handle)
    task["dir"] = path.parent
    return task


def list_tasks() -> list[dict]:
    return [load_task(path.parent.name) for path in sorted(ROOT.glob("tasks/eclipse-*/task.json"))]


def worktree(commit: str) -> Path:
    if not (REPO / ".git").exists() and not (REPO / "HEAD").exists():
        # A linked worktree's .git is a file; the main clone has a .git directory.
        git_entry = REPO / ".git"
        if not git_entry.exists():
            raise SystemExit(f"Missing syzygy clone at {REPO}. Clone Eclipse-Laboratories-Inc/syzygy there.")
    dest = WORK / f"wt-{commit[:12]}"
    if not dest.exists():
        WORK.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "-C", str(REPO), "worktree", "add", "--detach", str(dest), commit],
            check=True,
        )
        lib_dest = dest / "smart-contracts" / "lib"
        if not lib_dest.exists():
            shutil.copytree(LIBS, lib_dest)
    return dest


def reset_worktree(dest: Path, commit: str) -> None:
    subprocess.run(["git", "-C", str(dest), "reset", "--hard", commit], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(dest), "clean", "-fd"], check=True, capture_output=True)
    lib_dest = dest / "smart-contracts" / "lib"
    if not lib_dest.exists():
        shutil.copytree(LIBS, lib_dest)


def apply_patch(dest: Path, patch: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(dest), "apply", "--whitespace=nowarn", str(patch)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git apply failed for {patch}:\n{result.stderr}")


LIB_NAMES = (
    "forge-std",
    "openzeppelin-contracts",
    "openzeppelin-contracts-upgradeable",
    "openzeppelin-foundry-upgrades",
    "solidity-stringutils",
)


def ensure_foundry_remappings(dest: Path) -> None:
    """Make the audited tree compile against the pinned libraries.

    The committed remappings.txt maps ``@openzeppelin/`` onto
    ``.../contracts`` with no trailing slash, so
    ``@openzeppelin/contracts/X`` resolves to ``.../contracts/contracts/X``.
    ``openzeppelin-foundry-upgrades`` also lives under ``src/``.
    """
    lib_dest = dest / "smart-contracts" / "lib"
    lib_dest.mkdir(parents=True, exist_ok=True)
    for name in LIB_NAMES:
        source = LIBS / name
        target = lib_dest / name
        if source.exists() and not target.exists():
            shutil.copytree(source, target)

    remappings = dest / "smart-contracts" / "remappings.txt"
    if not remappings.exists():
        return
    text = remappings.read_text()
    text = text.replace(
        "@openzeppelin/=lib/openzeppelin-contracts/contracts",
        "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    )
    lines = []
    for line in text.splitlines():
        if line.startswith("openzeppelin-foundry-upgrades/="):
            line = "openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/"
        lines.append(line)
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    if "openzeppelin-foundry-upgrades/=" not in text:
        text += "openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/\n"
    if "solidity-stringutils/=" not in text:
        text += "solidity-stringutils/=lib/solidity-stringutils/\n"
    remappings.write_text(text)


def install_grader(dest: Path, task: dict) -> None:
    source = task["dir"] / task["grader"]
    target = dest / task["test_relpath"]
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def forge_test(dest: Path, tests: list[str]) -> tuple[int, str]:
    match = "|".join(tests)
    FOUNDRY_HOME.mkdir(parents=True, exist_ok=True)
    cmd = [
        "docker",
        "run",
        "--rm",
        "-v",
        f"{dest}:/repo",
        "-v",
        f"{FOUNDRY_HOME}:/root",
        "-w",
        "/repo/smart-contracts",
        "-e",
        "FOUNDRY_DISABLE_NIGHTLY_WARNING=1",
        "--entrypoint",
        "bash",
        IMAGE,
        "-lc",
        f"forge test --match-test '{match}' -vv",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1200)
    log = result.stdout + "\n" + result.stderr
    return result.returncode, log


def parse_forge(log: str) -> dict[str, str]:
    status: dict[str, str] = {}
    for match in PASS_RE.finditer(log):
        status[match.group(1).split("(")[0]] = "pass"
    for match in FAIL_RE.finditer(log):
        status[match.group(1).split("(")[0]] = "fail"
    return status


def judge(task: dict, status: dict[str, str]) -> dict:
    audit = {}
    preservation = {}
    for name in task["audit_tests"]:
        audit[name] = status.get(name, "missing")
    for name in task["preservation_tests"]:
        preservation[name] = status.get(name, "missing")
    reward = int(
        all(value == "pass" for value in audit.values())
        and all(value == "pass" for value in preservation.values())
    )
    return {"reward": reward, "audit": audit, "preservation": preservation}


def prepare(task: dict, commit: str, patch: Path | None) -> Path:
    dest = worktree(commit)
    reset_worktree(dest, commit)
    if patch is not None:
        apply_patch(dest, patch)
    ensure_foundry_remappings(dest)
    install_grader(dest, task)
    return dest


def grade(task: dict, commit: str, patch: Path | None = None) -> dict:
    dest = prepare(task, commit, patch)
    tests = task["audit_tests"] + task["preservation_tests"]
    code, log = forge_test(dest, tests)
    status = parse_forge(log)
    report = judge(task, status)
    report.update({"exit_code": code, "commit": commit, "log": log, "status": status})
    return report


def strip_future_history(dest: Path) -> None:
    """Drop commits that are not ancestors of HEAD, including the later fix."""
    subprocess.run(["git", "-C", str(dest), "remote", "remove", "origin"], check=False, capture_output=True)
    subprocess.run(
        ["git", "-C", str(dest), "for-each-ref", "--format=%(refname)", "refs/heads", "refs/tags"],
        check=True,
        capture_output=True,
        text=True,
    )
    refs = subprocess.run(
        ["git", "-C", str(dest), "for-each-ref", "--format=%(refname)", "refs/heads", "refs/tags", "refs/remotes"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    for ref in refs:
        subprocess.run(["git", "-C", str(dest), "update-ref", "-d", ref], check=False, capture_output=True)
    subprocess.run(["git", "-C", str(dest), "reflog", "expire", "--expire=now", "--all"], check=True)
    subprocess.run(["git", "-C", str(dest), "gc", "--prune=now"], check=True)
    for secret in dest.rglob(".env"):
        secret.unlink(missing_ok=True)
    envrc = dest / ".envrc"
    if envrc.exists():
        envrc.unlink()
