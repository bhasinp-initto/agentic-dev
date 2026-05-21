#!/usr/bin/env bash
# Phase 5 test aggregator. All deterministic (no claude -p).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== reviewer_verdict_schema_test ==="
python3 "$DIR/reviewer_verdict_schema_test.py"

echo
echo "=== escalation_packet_schema_test ==="
python3 "$DIR/escalation_packet_schema_test.py"

echo
echo "=== hardened_reviewer_structure_test ==="
python3 "$DIR/hardened_reviewer_structure_test.py"

echo
echo "=== reviewer_adversary_structure_test ==="
python3 "$DIR/reviewer_adversary_structure_test.py"

echo
echo "=== telegram_notify_test ==="
bash "$DIR/telegram_notify_test.sh"

echo
echo "=== generate_escalation_test ==="
bash "$DIR/generate_escalation_test.sh"

echo
echo "=== run_reviewer_skill_structure_test ==="
python3 "$DIR/run_reviewer_skill_structure_test.py"

echo
echo "All Phase 5 tests passed (deterministic; no claude -p)."
