#!/bin/bash
# Validate the fix tasks the way an external recipient would: no Eclipse
# secrets, no repo .env, no model keys. Requires Docker and Harbor 0.24.0
# on PATH (or HARBOR=/path/to/harbor). Oracle must score every finding 1
# and nop every finding 0 with regression 1.
set -euo pipefail
cd "$(dirname "$0")/.."

HARBOR="${HARBOR:-harbor}"
command -v "$HARBOR" >/dev/null || { echo "harbor not found (set HARBOR=/path/to/harbor; need 0.24.0)" >&2; exit 2; }
version="$("$HARBOR" --version 2>/dev/null || true)"
echo "harbor: $version (tasks validated with 0.24.0)"
docker info >/dev/null 2>&1 || { echo "docker is not running" >&2; exit 2; }

out="$(mktemp -d)"
echo "output: $out"
env -i PATH="$PATH" HOME="$HOME" "$HARBOR" run -p harbor/fix -a oracle -y -o "$out" --job-name oracle
env -i PATH="$PATH" HOME="$HOME" "$HARBOR" run -p harbor/fix -a nop -y -o "$out" --job-name nop

python3 - "$out" << 'PY'
import json, sys
from pathlib import Path

ok = True
for job, want_reward in (("oracle", 1.0), ("nop", 0.0)):
    for result in sorted((Path(sys.argv[1]) / job).glob("*/result.json")):
        data = json.loads(result.read_text())
        rewards = (data.get("verifier_result") or {}).get("rewards") or {}
        good = rewards.get("reward") == want_reward and (job == "nop" or rewards.get("regression") == 1)
        ok &= good
        print(f"{job} {data['task_name']}: reward={rewards.get('reward')} regression={rewards.get('regression')} {'OK' if good else 'MISMATCH'}")
print("EXTERNAL VALIDATION PASSED" if ok else "EXTERNAL VALIDATION FAILED")
sys.exit(0 if ok else 1)
PY
