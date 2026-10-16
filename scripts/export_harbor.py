"""Generate the Harbor tasks under harbor/ from the audits under audits/.

Each audits/<audit>/audit.toml names the audited commit and lists the
auditors' findings. For every audit the exporter writes:

- harbor/report/<audit>: write an audit report; an LLM judge grades it
  against the auditors' findings.
- harbor/fix/<audit>, for audits with Forge graders: fix the code; hidden
  graders score each finding and the project's test suite checks regressions.

--ticketed writes only the fix tasks, with each graded finding's ticket in the
instruction, to a separate directory.
"""

from __future__ import annotations

import argparse
import io
import json
import shutil
import subprocess
import tarfile
import tempfile
import tomllib
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parents[1]
AUDITS = ROOT / "audits"
TEMPLATES = ROOT / "templates"
SYZYGY = ROOT / "repos" / "syzygy"
PROGRAMS = ROOT / "repos" / "eclipse-programs"
PROGRAM_PATHS = ["Anchor.toml", "Cargo.toml", "programs", "tests"]
# Relative to smart-contracts/: libraries are installed by the Dockerfile; the rest is build output.
NOT_SNAPSHOTTED = ["lib", "cache", "out", "coverage.sh", "test/coverage", "test/coverage_report"]
REMOVED_NAMES = {".env", ".envrc", ".gitignore"}
DEFAULT_JUDGE_MODEL = "claude-opus-5-5"


def load_audits() -> list[dict]:
    audits = []
    for path in sorted(AUDITS.glob("*/audit.toml")):
        audit = tomllib.loads(path.read_text())
        audit["id"] = path.parent.name
        audit["dir"] = path.parent
        audits.append(audit)
    return audits


def graded_findings(audit: dict) -> list[dict]:
    return [finding for finding in audit["findings"] if "task" in finding]


def extract(repo: Path, commit: str, paths: list[str], dest: Path) -> None:
    archive = subprocess.run(
        ["git", "-C", str(repo), "archive", "--format=tar", commit, *paths],
        check=True,
        capture_output=True,
    ).stdout
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(dest, filter="data")


def git_apply(patch: Path, cwd: Path) -> None:
    subprocess.run(["git", "apply", "--whitespace=nowarn", str(patch)], cwd=cwd, check=True)


def remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def is_keypair(path: Path) -> bool:
    if path.suffix != ".json" or path.stat().st_size > 1024:
        return False
    try:
        value = json.loads(path.read_text())
    except (UnicodeDecodeError, ValueError):
        return False
    return isinstance(value, list) and len(value) == 64 and all(isinstance(b, int) and 0 <= b <= 255 for b in value)


def rewrite_remappings(path: Path) -> None:
    """Point the audited remappings at the library layout the Dockerfile installs."""
    text = path.read_text().replace(
        "@openzeppelin/=lib/openzeppelin-contracts/contracts",
        "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    )
    lines = []
    for line in text.splitlines():
        if line.startswith("openzeppelin-foundry-upgrades/="):
            line = "openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/"
        lines.append(line)
    text = "\n".join(lines) + "\n"
    if "openzeppelin-foundry-upgrades/=" not in text:
        text += "openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/\n"
    if "solidity-stringutils/=" not in text:
        text += "solidity-stringutils/=lib/solidity-stringutils/\n"
    path.write_text(text)


def snapshot(audit: dict, app: Path, with_programs: bool) -> None:
    """Write the audited code to app/, minus build output, secrets, and the hints in redact.patch."""
    extract(SYZYGY, audit["syzygy_commit"], ["smart-contracts"], app)
    contracts = app / "smart-contracts"
    for rel in NOT_SNAPSHOTTED:
        remove(contracts / rel)
    rewrite_remappings(contracts / "remappings.txt")
    if with_programs and "eclipse_programs_commit" in audit:
        extract(PROGRAMS, audit["eclipse_programs_commit"], PROGRAM_PATHS, app / "eclipse-programs")
    redact = audit["dir"] / "redact.patch"
    if redact.exists():
        git_apply(redact, app)
    for path in sorted(app.rglob("*"), reverse=True):
        if path.is_symlink():
            raise SystemExit(f"{audit['id']}: unexpected symlink {path.relative_to(app)}")
        if path.name in REMOVED_NAMES or (path.is_file() and is_keypair(path)):
            path.unlink()


def render(template: str, **values: str) -> str:
    return Template((TEMPLATES / template).read_text()).substitute(**values)


def scope_list(audit: dict, prefix: str = "") -> str:
    return "\n".join(f"- `{path}`" for path in audit["scope"] if path.startswith(prefix))


def task_toml(audit: dict, name: str, fmt: str, description: str, keys: list[str], verifier: str) -> str:
    programs = audit.get("eclipse_programs_commit")
    return render(
        "task.toml",
        name=name,
        description=description,
        format=fmt,
        auditor=audit["auditor"],
        audit_title=audit["title"],
        audit_date=audit["date"],
        syzygy_commit=audit["syzygy_commit"],
        programs_commit=f'eclipse_programs_commit = "{programs}"' if programs and fmt == "report" else "",
        keys=", ".join(json.dumps(key) for key in keys),
        verifier=verifier,
    )


def copy_executable(src: Path, dst: Path) -> None:
    shutil.copyfile(src, dst)
    dst.chmod(0o755)


def write_task(dest: Path, app: Path, instruction: str, toml: str, fmt: str) -> None:
    """Lay out the parts every task shares; the caller adds format-specific tests and solution files."""
    remove(dest)
    (dest / "environment").mkdir(parents=True)
    shutil.copytree(app, dest / "environment" / "app")
    shutil.copyfile(TEMPLATES / "Dockerfile", dest / "environment" / "Dockerfile")
    (dest / "instruction.md").write_text(instruction)
    (dest / "task.toml").write_text(toml)
    (dest / "tests").mkdir()
    shutil.copyfile(TEMPLATES / "sandbox.py", dest / "tests" / "sandbox.py")
    copy_executable(TEMPLATES / fmt / "test.sh", dest / "tests" / "test.sh")
    (dest / "solution").mkdir()
    copy_executable(TEMPLATES / fmt / "solve.sh", dest / "solution" / "solve.sh")


def write_fix(audit: dict, app: Path, dest: Path, ticketed: bool) -> None:
    findings = graded_findings(audit)
    if ticketed:
        intro = "Fix the security defects described below, which the original audit of this code reported."
        tickets = "\nDefects to fix:\n\n" + "\n\n".join(
            (audit["dir"] / finding["task"] / "ticket.md").read_text().strip() for finding in findings
        ) + "\n"
    else:
        intro = (
            "Audit the smart contracts in this repository for security defects and fix every one you find. "
            "No specific bug has been identified for you."
        )
        tickets = ""
    fmt = "fix-ticketed" if ticketed else "fix"
    keys = [finding["task"] for finding in findings]
    write_task(
        dest,
        app,
        render("fix/instruction.md", intro=intro, scope=scope_list(audit, "smart-contracts/"), tickets=tickets),
        task_toml(
            audit,
            f"{fmt}-{audit['id']}",
            fmt,
            f"Fix the defects found by the {audit['auditor']} {audit['date']} audit of the Eclipse bridge contracts.",
            keys,
            "",
        ),
        "fix",
    )

    shutil.copyfile(TEMPLATES / "fix" / "grade.py", dest / "tests" / "grade.py")
    graders = dest / "tests" / "graders"
    graders.mkdir()
    config: dict = {"findings": [], "regression_exclude": audit.get("regression_exclude", [])}
    with tempfile.TemporaryDirectory() as scratch:
        patched = Path(scratch) / "app"
        shutil.copytree(app, patched)
        for finding in findings:
            source = audit["dir"] / finding["task"]
            (grader,) = source.glob("*.sol")
            shutil.copyfile(grader, graders / grader.name)
            config["findings"].append({"key": finding["task"], "grader": grader.name})
            patch = dest / "solution" / f"{finding['task']}.patch"
            shutil.copyfile(source / "fix.patch", patch)
            git_apply(patch, patched)
    (dest / "tests" / "findings.json").write_text(json.dumps(config, indent=2) + "\n")


def write_report(audit: dict, app: Path, dest: Path) -> None:
    rubric = [
        {
            "key": f"{audit['id']}/{finding['id']}",
            **{field: finding[field].strip() for field in ("id", "severity", "title", "location", "description")},
        }
        for finding in audit["findings"]
    ]
    if (app / "eclipse-programs").exists():
        tooling = (
            "The Foundry project is at `/app/smart-contracts` and `forge` is on PATH. "
            "The Solana program is at `/app/eclipse-programs`. No Rust or Anchor toolchain is installed, "
            "so review the program by reading its source."
        )
    else:
        tooling = "The Foundry project is at `/app/smart-contracts` and `forge` is on PATH. Run it from `/app/smart-contracts`."
    verifier = (
        'network_mode = "allowlist"\n'
        'allowed_hosts = ["api.anthropic.com"]\n\n'
        "[verifier.env]\n"
        'JUDGE_API_KEY = "${JUDGE_API_KEY}"\n'
        f'JUDGE_MODEL = "${{JUDGE_MODEL:-{DEFAULT_JUDGE_MODEL}}}"\n'
        'JUDGE_WORKSPACE_ID = "${JUDGE_WORKSPACE_ID:-}"'
    )
    write_task(
        dest,
        app,
        render("report/instruction.md", scope=scope_list(audit), tooling=tooling),
        task_toml(
            audit,
            f"report-{audit['id']}",
            "report",
            f"Audit the Eclipse bridge code that {audit['auditor']} audited on {audit['date']} and write a report.",
            [item["key"] for item in rubric],
            verifier,
        ),
        "report",
    )
    shutil.copyfile(TEMPLATES / "report" / "judge.py", dest / "tests" / "judge.py")
    (dest / "tests" / "rubric.json").write_text(json.dumps(rubric, indent=2) + "\n")
    report = [f"# {audit['auditor']} audit, {audit['date']}"]
    for item in rubric:
        report.append(f"## {item['severity']}: {item['title']}\n\nLocation: {item['location']}\n\n{item['description']}")
    (dest / "solution" / "audit-report.md").write_text("\n\n".join(report) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, help="output directory (default: harbor/, or .work/harbor-ticketed with --ticketed)")
    parser.add_argument("--ticketed", action="store_true", help="write only fix tasks, with the findings' tickets")
    args = parser.parse_args()
    out = args.out or (ROOT / ".work" / "harbor-ticketed" if args.ticketed else ROOT / "harbor")

    formats = ["fix"] if args.ticketed else ["fix", "report"]
    for fmt in formats:
        remove(out / fmt)
    for audit in load_audits():
        with tempfile.TemporaryDirectory() as scratch:
            if graded_findings(audit):
                app = Path(scratch) / "fix"
                snapshot(audit, app, with_programs=False)
                write_fix(audit, app, out / "fix" / audit["id"], args.ticketed)
            if not args.ticketed:
                app = Path(scratch) / "report"
                snapshot(audit, app, with_programs=True)
                write_report(audit, app, out / "report" / audit["id"])
        print(f"{audit['id']}: {len(graded_findings(audit))} graded findings, {len(audit['findings'])} rubric items")


if __name__ == "__main__":
    main()
