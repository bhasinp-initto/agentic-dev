#!/usr/bin/env bash
# Phase 3 test aggregator. Per docs/superpowers/test-cost-policy.md,
# all P3 tests are deterministic (no claude -p). Zero API cost.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== queue_schema_v02_test ==="
python3 "$DIR/queue_schema_v02_test.py"

echo
echo "=== manifest_schema_test ==="
python3 "$DIR/manifest_schema_test.py"

echo
echo "=== diff_envelope_schema_test ==="
python3 "$DIR/diff_envelope_schema_test.py"

echo
echo "=== migration_test ==="
bash "$DIR/migration_test.sh"

echo
echo "=== worktree_init_test ==="
bash "$DIR/worktree_init_test.sh"

echo
echo "=== worktree_cleanup_test ==="
bash "$DIR/worktree_cleanup_test.sh"

echo
echo "=== implementer_structure_test ==="
python3 "$DIR/implementer_structure_test.py"

echo
echo "=== run_implementer_skill_structure_test ==="
python3 "$DIR/run_implementer_skill_structure_test.py"

echo
echo "All Phase 3 tests passed (deterministic; no claude -p)."
