#!/bin/bash
# Run the ten Harbor tasks once each. Keys stay in the gitignored .env.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
source .env
set +a
mkdir -p results/harbor-jobs

model="${1:?model: claude or inkling}"
if [[ "$model" == "claude" ]]; then
  unset ANTHROPIC_BASE_URL || true
  export ANTHROPIC_CUSTOM_HEADERS=$'anthropic-workspace-id: wrkspc_01F7W2SvkSGt156wCQHf7pu3'
  exec .venv/bin/harbor run \
    -p harbor \
    -a claude-code \
    -m claude-sonnet-4-5 \
    --effort medium \
    --allow-agent-host api.anthropic.com \
    -n 2 \
    -y \
    --job-name claude-sonnet-4-5 \
    -o results/harbor-jobs \
    --ae "ANTHROPIC_CUSTOM_HEADERS=${ANTHROPIC_CUSTOM_HEADERS}"
fi

if [[ "$model" == "inkling" ]]; then
  export ANTHROPIC_API_KEY="$TINKER_API_KEY"
  export ANTHROPIC_BASE_URL="https://tinker.thinkingmachines.dev/services/tinker-prod/anthropic/api"
  unset ANTHROPIC_CUSTOM_HEADERS || true
  exec .venv/bin/harbor run \
    -p harbor \
    -a claude-code \
    -m thinkingmachines/Inkling \
    --effort medium \
    --allow-agent-host tinker.thinkingmachines.dev \
    -n 2 \
    -y \
    --job-name inkling \
    -o results/harbor-jobs
fi

echo "unknown model: $model" >&2
exit 2
