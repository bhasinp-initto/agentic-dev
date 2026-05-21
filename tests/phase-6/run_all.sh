#!/usr/bin/env bash
# Phase 6 test aggregator. All deterministic (no claude -p).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== queue_set_status_test ==="
bash "$DIR/queue_set_status_test.sh"

echo
echo "=== circuit_breaker_test ==="
bash "$DIR/circuit_breaker_test.sh"

echo
echo "=== cleanup_completed_goal_test ==="
bash "$DIR/cleanup_completed_goal_test.sh"

echo
echo "=== advance_goal_skill_structure_test ==="
python3 "$DIR/advance_goal_skill_structure_test.py"

echo
echo "=== run_orchestrator_skill_structure_test ==="
python3 "$DIR/run_orchestrator_skill_structure_test.py"

echo
echo "=== start_skill_structure_test ==="
python3 "$DIR/start_skill_structure_test.py"

echo
echo "=== resume_skill_structure_test ==="
python3 "$DIR/resume_skill_structure_test.py"

echo
echo "All Phase 6 tests passed (deterministic; no claude -p)."
