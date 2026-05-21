#!/usr/bin/env bash
# Run Phase 2 E2E (claude -p) tests explicitly. Sets AGENTIC_E2E=1 so the
# gated tests actually execute.
#
# COST: This invokes claude -p ~10 times. Per docs/superpowers/test-cost-policy.md,
# this should burn ~$2–3 in Anthropic Console API credits.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
export AGENTIC_E2E=1

echo "=== intent_fresh_test (E2E) ==="
bash "$DIR/intent_fresh_test.sh"

echo
echo "=== intent_refine_test (E2E) ==="
bash "$DIR/intent_refine_test.sh"

echo
echo "=== approval_gate_test (E2E) ==="
bash "$DIR/approval_gate_test.sh"

echo
echo "All Phase 2 E2E tests passed."
