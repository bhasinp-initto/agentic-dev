#!/usr/bin/env bash
# circuit_breaker_test.sh
# Deterministic tests for bin/circuit-breaker.sh.
# No claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/agentic-dev/bin/circuit-breaker.sh"

PASS=0
FAIL=0

pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1: $2"; FAIL=$((FAIL+1)); }

require_script() {
  if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL setup: $SCRIPT not found or not executable"
    exit 1
  fi
}

# ── fixture helper ────────────────────────────────────────────────────────────

make_state() {
  local path="$1"
  local cb_state="${2:-idle}"
  cat > "$path" <<EOF
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "$cb_state",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": null,
  "last_updated": "2026-05-21T09:00:00Z"
}
EOF
}

make_halted_state() {
  local path="$1"
  cat > "$path" <<'EOF'
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "running",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": "2026-05-21-test-alpha",
  "last_updated": "2026-05-21T10:00:00Z"
}
EOF
}

# ── Test 1: idle → running; state.json updated, last_updated bumped ───────────

test_idle_to_running() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_state "$agentic_dir/state.json" idle

  local out exit_code=0
  out="$(cd "$tmp" && "$SCRIPT" running 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "idle-to-running-exit0" "expected exit 0, got $exit_code. output: $out"
    return
  fi
  pass "idle-to-running-exit0"

  local new_state
  new_state="$(python3 -c "
import json
s = json.load(open('$agentic_dir/state.json'))
print(s['circuit_breaker']['state'])
")"
  if [[ "$new_state" == "running" ]]; then
    pass "idle-to-running-state-updated"
  else
    fail "idle-to-running-state-updated" "expected running, got: $new_state"
  fi

  # Verify last_updated was bumped (should differ from original 2026-05-21T09:00:00Z)
  local last_updated
  last_updated="$(python3 -c "
import json
s = json.load(open('$agentic_dir/state.json'))
print(s['last_updated'])
")"
  if [[ "$last_updated" != "2026-05-21T09:00:00Z" ]]; then
    pass "idle-to-running-last-updated-bumped"
  else
    fail "idle-to-running-last-updated-bumped" "last_updated was not bumped (still: $last_updated)"
  fi
}

# ── Test 2: running → halted with required fields; halted_at populated ────────

test_running_to_halted() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_state "$agentic_dir/state.json" running

  local out exit_code=0
  out="$(cd "$tmp" && "$SCRIPT" halted \
    halted_reason="gate-budget-exceeded" \
    halted_goal_id="2026-05-21-test-alpha" 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "running-to-halted-exit0" "expected exit 0, got $exit_code. output: $out"
    return
  fi
  pass "running-to-halted-exit0"

  local new_state
  new_state="$(python3 -c "
import json
s = json.load(open('$agentic_dir/state.json'))
print(s['circuit_breaker']['state'])
")"
  if [[ "$new_state" == "halted" ]]; then
    pass "running-to-halted-state-updated"
  else
    fail "running-to-halted-state-updated" "expected halted, got: $new_state"
  fi

  local halted_at
  halted_at="$(python3 -c "
import json
s = json.load(open('$agentic_dir/state.json'))
print(s['circuit_breaker'].get('halted_at', 'MISSING'))
")"
  if [[ "$halted_at" != "null" && "$halted_at" != "MISSING" && -n "$halted_at" ]]; then
    pass "running-to-halted-halted-at-populated"
  else
    fail "running-to-halted-halted-at-populated" "halted_at not populated, got: $halted_at"
  fi

  local halted_reason
  halted_reason="$(python3 -c "
import json
s = json.load(open('$agentic_dir/state.json'))
print(s['circuit_breaker'].get('halted_reason', 'MISSING'))
")"
  if [[ "$halted_reason" == "gate-budget-exceeded" ]]; then
    pass "running-to-halted-reason-set"
  else
    fail "running-to-halted-reason-set" "expected gate-budget-exceeded, got: $halted_reason"
  fi
}

# ── Test 3: halted without required args → exit 1 ────────────────────────────

test_halted_without_required_args() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_state "$agentic_dir/state.json" running

  local exit_code=0
  # Missing halted_reason and halted_goal_id
  cd "$tmp" && "$SCRIPT" halted 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "halted-without-args-exits-one"
  else
    fail "halted-without-args-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 4: Invalid new-state → exit 1 ───────────────────────────────────────

test_invalid_new_state() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_state "$agentic_dir/state.json" idle

  local exit_code=0
  cd "$tmp" && "$SCRIPT" bogus-state 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "invalid-state-exits-one"
  else
    fail "invalid-state-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_script

test_idle_to_running
test_running_to_halted
test_halted_without_required_args
test_invalid_new_state

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
