#!/usr/bin/env bash
set -euo pipefail

mix test --cover | tee coverage_output.log
coverage=$(grep -E "[0-9]+\.[0-9]+% \| Total" coverage_output.log | awk '{print $1}' | tr -d '%')
coverage=${coverage:-0}

anybadge --value="${coverage}" --label=coverage \
  --file=coverage.svg \
  --overwrite \
  0=red 80=yellow 90=green >/dev/null

echo "Generated coverage.svg with ${coverage}% coverage"
