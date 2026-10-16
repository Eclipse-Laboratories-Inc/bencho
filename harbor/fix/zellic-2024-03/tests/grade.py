"""Grade a fix-format Eclipse audit trial.

Runs the project's whole Forge suite with the hidden graders installed and
writes /logs/verifier/reward.json:

- one key per finding: 1 when every test in its grader passes and nothing regressed
- regression: 1 when every test that passed on the vulnerable snapshot still passes
- reward: the mean of the finding keys
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "/tests")
from sandbox import LOGS, prepare  # noqa: E402

PROJECT = Path("/app/smart-contracts")
AUDIT_DIR = PROJECT / "test" / "audit"
TESTS = Path("/tests")
STATE = Path("/opt/eclipse")
FORGE = "/usr/local/bin/forge"
PROTECTED_DIRS = ("test", "script", "lib")
ENV_FILES = (".env", ".envrc")
CHEATCODE_MARKERS = ("7109709ecfa91a80626ff3989d68f67f5b1dd12d", "hevm cheat code", "forge-std")


def read_manifest(path: Path) -> dict[str, str]:
    digests = {}
    for line in path.read_text().splitlines():
        digest, rel = line.split(maxsplit=1)
        digests[rel] = digest
    return digests


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_tree() -> str | None:
    """Return why the submission is invalid, after removing files added under protected dirs."""
    for directory in (PROJECT.parent, PROJECT):
        for name in ENV_FILES:
            if (directory / name).exists():
                return f"{directory / name} is not allowed"
    protected = read_manifest(STATE / "protected.sha256")
    for name in PROTECTED_DIRS:
        for path in sorted((PROJECT / name).rglob("*")):
            rel = path.relative_to(PROJECT).as_posix()
            if path.is_symlink():
                return f"symlink at {rel}"
            if path.is_file() and rel not in protected:
                path.unlink()
    for rel, digest in protected.items():
        path = PROJECT / rel
        if path.is_symlink() or not path.is_file() or sha256(path) != digest:
            return f"{rel} was modified or removed"
    for path in sorted((PROJECT / "src").rglob("*")):
        rel = path.relative_to(PROJECT).as_posix()
        if path.is_symlink():
            return f"symlink at {rel}"
        if not path.is_file():
            continue
        original = STATE / rel
        text = path.read_text(errors="ignore").lower()
        before = original.read_text(errors="ignore").lower() if original.is_file() else ""
        for marker in CHEATCODE_MARKERS:
            if text.count(marker) > before.count(marker):
                return f"{rel} adds a reference to {marker!r}"
    return None


def forge_test(home: str, *args: str) -> tuple[dict | None, str]:
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": home,
        "FOUNDRY_DISABLE_NIGHTLY_WARNING": "1",
        "FOUNDRY_FFI": "false",
        "FOUNDRY_FUZZ_SEED": "0x1",
        "FOUNDRY_OFFLINE": "true",
    }
    proc = subprocess.run(
        [FORGE, "test", "--json", *args],
        cwd=PROJECT,
        env=env,
        capture_output=True,
        text=True,
        timeout=900,
    )
    log = proc.stdout + "\n" + proc.stderr
    start = proc.stdout.find("{")
    if start < 0:
        return None, log
    try:
        return json.loads(proc.stdout[start:]), log
    except json.JSONDecodeError:
        return None, log


def outcomes(results: dict) -> dict[str, str]:
    return {
        f"{suite}::{name}": result["status"]
        for suite, data in results.items()
        for name, result in data.get("test_results", {}).items()
    }


def install_graders(findings: list[dict]) -> None:
    shutil.rmtree(AUDIT_DIR, ignore_errors=True)
    AUDIT_DIR.mkdir(parents=True)
    for finding in findings:
        shutil.copyfile(TESTS / "graders" / finding["grader"], AUDIT_DIR / finding["grader"])


def run_suite(findings: list[dict], logs: list[str]) -> dict[str, str] | None:
    """Test statuses for the whole suite plus graders, or None if the project does not compile."""
    for build_dir in ("cache", "out"):
        shutil.rmtree(PROJECT / build_dir, ignore_errors=True)
    with tempfile.TemporaryDirectory() as home:
        (Path(home) / ".svm").symlink_to(STATE / "svm")
        install_graders(findings)
        results, log = forge_test(home)
        logs.append(log)
        if results is not None:
            return outcomes(results)
        # A grader that does not compile against the patched tree must not hide the others.
        install_graders([])
        results, log = forge_test(home)
        logs.append(log)
        if results is None:
            return None
        status = outcomes(results)
        for finding in findings:
            install_graders([finding])
            results, log = forge_test(home, "--match-path", f"test/audit/{finding['grader']}")
            logs.append(log)
            if results is not None:
                status.update(outcomes(results))
        return status


def main() -> None:
    prepare()
    config = json.loads((TESTS / "findings.json").read_text())
    findings = config["findings"]
    keys = [finding["key"] for finding in findings]
    rewards: dict[str, float] = {key: 0 for key in keys}
    rewards["regression"] = 0
    details: dict = {}
    logs: list[str] = []

    invalid = check_tree()
    status = None if invalid else run_suite(findings, logs)
    if invalid:
        details["invalid"] = invalid
    elif status is None:
        details["invalid"] = "the project does not compile"
    else:
        baseline = outcomes(json.loads((STATE / "baseline.json").read_text()))
        excluded = set(config.get("regression_exclude", []))
        expected = sorted(test for test, result in baseline.items() if result == "Success" and test not in excluded)
        regressions = [test for test in expected if status.get(test) != "Success"]
        rewards["regression"] = int(not regressions)
        details["regressions"] = regressions
        for finding in findings:
            prefix = f"test/audit/{finding['grader']}:"
            tests = {test: result for test, result in status.items() if test.startswith(prefix)}
            fixed = bool(tests) and all(result == "Success" for result in tests.values())
            rewards[finding["key"]] = int(fixed and not regressions)
            details[finding["key"]] = tests
    rewards["reward"] = sum(rewards[key] for key in keys) / len(keys)

    (LOGS / "forge.log").write_text("\n".join(logs))
    (LOGS / "grade.json").write_text(json.dumps({"rewards": rewards, **details}, indent=2) + "\n")
    (LOGS / "reward.json").write_text(json.dumps(rewards) + "\n")
    print(json.dumps(rewards))


if __name__ == "__main__":
    main()
