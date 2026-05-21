#!/usr/bin/env bash
# Phase 4 test aggregator. All P4 tests deterministic (no claude -p).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== gate_verdict_schema_test ==="
python3 "$DIR/gate_verdict_schema_test.py"

echo
echo "=== gate_scope_check_test ==="
bash "$DIR/gate_scope_check_test.sh"

echo
echo "=== gate_budget_check_test ==="
bash "$DIR/gate_budget_check_test.sh"

echo
echo "=== gate_sensitive_path_test ==="
bash "$DIR/gate_sensitive_path_test.sh"

echo
echo "=== gate_test_count_test ==="
bash "$DIR/gate_test_count_test.sh"

echo
echo "=== run_implementer_skill_modified_test ==="
python3 "$DIR/run_implementer_skill_modified_test.py"

echo
echo "=== gate_rerun_tests_test ==="
bash "$DIR/gate_rerun_tests_test.sh"

echo
echo "=== bisect_on_claim_test ==="
bash "$DIR/bisect_on_claim_test.sh"

echo
echo "=== run_gates_test ==="
bash "$DIR/run_gates_test.sh"

echo
echo "=== run_gates_skill_structure_test ==="
python3 "$DIR/run_gates_skill_structure_test.py"

echo
echo "All Phase 4 tests passed (deterministic; no claude -p)."
