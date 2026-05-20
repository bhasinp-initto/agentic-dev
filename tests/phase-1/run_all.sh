#!/usr/bin/env bash
# Run all Phase 1 tests in order. Exit non-zero on any failure.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== schema_test ==="
python3 "$DIR/schema_test.py"

echo
echo "=== init_test ==="
bash "$DIR/init_test.sh"

echo
echo "=== status_test ==="
bash "$DIR/status_test.sh"

echo
echo "=== smoke_test ==="
bash "$DIR/smoke_test.sh"

echo
echo "All Phase 1 tests passed."
