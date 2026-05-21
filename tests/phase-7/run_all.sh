#!/usr/bin/env bash
# Phase 7 test aggregator. All deterministic (no claude -p).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== checklist_schema_test ==="
python3 "$DIR/checklist_schema_test.py"

echo
echo "=== memory_schema_test ==="
python3 "$DIR/memory_schema_test.py"

echo
echo "=== log_incident_test ==="
bash "$DIR/log_incident_test.sh"

echo
echo "All Phase 7 tests passed (deterministic; no claude -p)."
