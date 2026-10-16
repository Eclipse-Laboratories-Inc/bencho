"""Shared by the verifiers: remove what the agent could leave behind to influence grading."""

from __future__ import annotations

import os
import signal
from pathlib import Path

AGENT_UID = 1000
LOGS = Path("/logs/verifier")


def agent_processes() -> list[int]:
    """Live processes owned by the agent user. Zombies are skipped: the container's init may never reap them."""
    pids = []
    for entry in Path("/proc").iterdir():
        try:
            if not entry.name.isdigit() or entry.stat().st_uid != AGENT_UID:
                continue
            state = (entry / "stat").read_text().rsplit(")", 1)[1].split()[0]
        except (OSError, IndexError):
            continue
        if state not in ("Z", "X"):
            pids.append(int(entry.name))
    return pids


def prepare() -> None:
    """Kill every agent process and delete any reward file it planted."""
    if os.geteuid() != 0:
        raise SystemExit("the verifier must run as root")
    for _ in range(100):
        pids = agent_processes()
        if not pids:
            break
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
    else:
        raise SystemExit("agent processes kept respawning")
    LOGS.mkdir(parents=True, exist_ok=True)
    for name in ("reward.json", "reward.txt"):
        (LOGS / name).unlink(missing_ok=True)
