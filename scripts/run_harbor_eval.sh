#!/bin/bash
# Run one agent on one task format.
#
#   scripts/run_harbor_eval.sh <claude|inkling|oracle|nop> <fix|fix-ticketed|report> [attempts]
#
# Model jobs write to results/harbor-jobs/<format>-<model>; oracle and nop
# validation jobs write to .work/validation. Keys stay in the gitignored .env.
set -euo pipefail
cd "$(dirname "$0")/.."

agent="${1:?agent: claude, inkling, oracle, or nop}"
format="${2:?format: fix, fix-ticketed, or report}"

set -a
# shellcheck disable=SC1091
source .env
set +a
# The report judge always calls Anthropic, including when the agent uses another provider.
export JUDGE_API_KEY="$ANTHROPIC_API_KEY"
export JUDGE_WORKSPACE_ID="wrkspc_01F7W2SvkSGt156wCQHf7pu3"

case "$format" in
  fix | report) dataset="harbor/$format" ;;
  fix-ticketed)
    .venv/bin/python scripts/export_harbor.py --ticketed >/dev/null
    dataset=".work/harbor-ticketed/fix"
    ;;
  *) echo "unknown format: $format" >&2; exit 2 ;;
esac

args=(-p "$dataset" -n 4 -y)
case "$agent" in
  claude)
    unset ANTHROPIC_BASE_URL || true
    export ANTHROPIC_CUSTOM_HEADERS="anthropic-workspace-id: $JUDGE_WORKSPACE_ID"
    label="claude-sonnet-4-5"
    args+=(-a claude-code -m claude-sonnet-4-5 --effort medium --allow-agent-host api.anthropic.com
      --ae "ANTHROPIC_CUSTOM_HEADERS=$ANTHROPIC_CUSTOM_HEADERS")
    ;;
  inkling)
    export ANTHROPIC_API_KEY="$TINKER_API_KEY"
    export ANTHROPIC_BASE_URL="https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api"
    unset ANTHROPIC_CUSTOM_HEADERS || true
    label="inkling"
    args+=(-a claude-code -m thinkingmachines/Inkling --effort medium --allow-agent-host tinker.thinkingmachines.dev)
    ;;
  oracle | nop) label="$agent"; args+=(-a "$agent") ;;
  *) echo "unknown agent: $agent" >&2; exit 2 ;;
esac

if [[ "$agent" == oracle || "$agent" == nop ]]; then
  out=".work/validation"
  attempts="${3:-1}"
else
  out="results/harbor-jobs"
  attempts="${3:-5}"
fi
job="$format-$label"
rm -rf "${out:?}/$job"
mkdir -p "$out"
exec .venv/bin/harbor run "${args[@]}" -k "$attempts" --job-name "$job" -o "$out"
