#!/usr/bin/env bash
# Run all phase-9 (Codex adversary) tests. Exit non-zero if any fail.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
fails=0

for t in \
  "python3 $DIR/config_review_schema_test.py" \
  "python3 $DIR/codex_adapter_test.py" \
  "python3 $DIR/codex_merge_test.py" \
  "python3 $DIR/codex_discovery_test.py" \
  "bash $DIR/codex_bridge_preflight_test.sh" \
  "bash $DIR/codex_bridge_review_test.sh" \
  "python3 $DIR/run_reviewer_codex_structure_test.py" \
  "python3 $DIR/init_codex_structure_test.py" \
; do
  echo "── $t"
  if ! $t; then echo "   ^ FAILED"; fails=$((fails+1)); fi
done

if [ "$fails" -eq 0 ]; then echo "phase-9: ALL PASS"; exit 0; else echo "phase-9: $fails FAILED"; exit 1; fi
