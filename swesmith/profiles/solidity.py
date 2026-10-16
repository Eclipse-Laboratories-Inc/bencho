"""SWE-smith profile for the Eclipse syzygy Foundry contracts.

Copy this module into a checkout of SWE-smith at the pin in ../PIN and
register it from swesmith/profiles/__init__.py. Historical tasks do not use
SWE-smith's bug-injection patches; scripts/evaluate.py checks out the
vulnerable commit directly.
"""

from dataclasses import dataclass, field

from swebench.harness.constants import TestStatus

from swesmith.profiles.base import RepoProfile, registry


@dataclass
class SolidityProfile(RepoProfile):
    test_cmd: str = "forge test -vv"
    exts: list[str] = field(default_factory=lambda: [".sol"])
    timeout: int = 600

    def log_parser(self, log: str) -> dict[str, str]:
        status: dict[str, str] = {}
        for line in log.splitlines():
            if "[PASS]" in line:
                name = line.split("[PASS]", 1)[1].strip().split()[0]
                status[name.split("(")[0]] = TestStatus.PASSED.value
            elif "[FAIL" in line:
                name = line.split("]", 1)[1].strip().split()[0]
                status[name.split("(")[0]] = TestStatus.FAILED.value
        return status

    @property
    def dockerfile(self) -> str:
        return """FROM ghcr.io/foundry-rs/foundry:stable
USER root
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates patch \\
    && rm -rf /var/lib/apt/lists/*
WORKDIR /testbed
"""


@dataclass
class EclipseSyzygy70b57c23(SolidityProfile):
    owner: str = "Eclipse-Laboratories-Inc"
    repo: str = "syzygy"
    commit: str = "70b57c23334778c4072cb8e60b4e2bbf23a034ed"
    test_cmd: str = "cd smart-contracts && forge test -vv"


for _name, _obj in list(globals().items()):
    if isinstance(_obj, type) and issubclass(_obj, SolidityProfile) and _obj.__name__ != "SolidityProfile":
        registry.register_profile(_obj)
