#!/usr/bin/env bash
# Phase 8 test aggregator. Deterministic (no claude -p by default;
# E2E gated behind AGENTIC_E2E=1).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== marketplace_smoke_test ==="
bash "$DIR/marketplace_smoke_test.sh"

echo
echo "All Phase 8 tests passed."
