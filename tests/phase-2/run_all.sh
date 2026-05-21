#!/usr/bin/env bash
# Run all Phase 2 tests in order. Exit non-zero on any failure.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== spec_schema_test ==="
python3 "$DIR/spec_schema_test.py"

echo
echo "=== validate_spec_test ==="
python3 "$DIR/validate_spec_test.py"

echo
echo "=== intent_fresh_test ==="
bash "$DIR/intent_fresh_test.sh"

echo
echo "=== hook_test ==="
bash "$DIR/hook_test.sh"

echo
echo "=== intent_refine_test ==="
bash "$DIR/intent_refine_test.sh"

echo
echo "=== approval_gate_test ==="
bash "$DIR/approval_gate_test.sh"

echo
echo "All Phase 2 tests passed."
