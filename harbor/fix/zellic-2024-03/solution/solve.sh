#!/bin/bash
set -euo pipefail
cd /app
for patch in /solution/*.patch; do
  git apply --whitespace=nowarn "$patch"
done
