#!/usr/bin/env bash
# gate_budget_check_test.sh
# Deterministic tests for gate-budget-check.sh.
# Uses hand-authored manifest + kickoff fixtures; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/gate-budget-check.sh"

PASS=0
FAIL=0

pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1: $2"; FAIL=$((FAIL+1)); }

require_gate() {
  if [[ ! -x "$GATE" ]]; then
    echo "FAIL setup: $GATE not found or not executable"
    exit 1
  fi
}

# ── shared fixture helpers ────────────────────────────────────────────────────

make_kickoff() {
  local path="$1"
  local wall="${2:-30}"
  local lines="${3:-100}"
  local files="${4:-5}"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "spec_path": "/tmp/spec.md",
  "baseline_ref": "abc1234",
  "budget": {
    "wall_clock_minutes_per_goal": $wall,
    "diff_lines_per_goal": $lines,
    "files_touched_per_goal": $files
  },
  "worktree_path": "/tmp/worktree"
}
EOF
}

make_manifest() {
  local path="$1"
  local files_touched="${2:-3}"
  local lines_added="${3:-42}"
  local lines_removed="${4:-0}"
  local started="${5:-2026-05-21T10:05:00Z}"
  local completed="${6:-2026-05-21T10:20:00Z}"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "/tmp/worktree",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "$started",
  "completed_at": "$completed",
  "diff_stats": {
    "files_touched": $files_touched,
    "lines_added": $lines_added,
    "lines_removed": $lines_removed
  }
}
EOF
}

# ── Test 1: all under budget → pass ──────────────────────────────────────────

test_under_budget() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # budget: 30min, 100 lines, 5 files
  make_kickoff "$kickoff" 30 100 5
  # actual: 15min, 42 lines, 3 files — all under
  make_manifest "$manifest" 3 42 0 "2026-05-21T10:05:00Z" "2026-05-21T10:20:00Z"

  local out
  out="$("$GATE" "$manifest" "$kickoff")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "budget-check-under-budget"
  else
    fail "budget-check-under-budget" "expected pass, got: $result (raw: $out)"
  fi
}

# ── Test 2: lines over budget → fail ─────────────────────────────────────────

test_lines_over_budget() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # budget: 100 lines
  make_kickoff "$kickoff" 30 100 5
  # actual: 80 added + 30 removed = 110 total lines → over
  make_manifest "$manifest" 3 80 30 "2026-05-21T10:05:00Z" "2026-05-21T10:20:00Z"

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "budget-check-lines-over"
  else
    fail "budget-check-lines-over" "expected fail, got: $result (raw: $out)"
  fi

  # Also verify the raw has lines info
  local total
  total="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("total_lines","missing"))')"
  if [[ "$total" == "110" ]]; then
    pass "budget-check-lines-over-raw-total"
  else
    fail "budget-check-lines-over-raw-total" "expected total_lines=110, got: $total"
  fi
}

# ── Test 3: files over budget → fail ─────────────────────────────────────────

test_files_over_budget() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # budget: 5 files
  make_kickoff "$kickoff" 30 100 5
  # actual: 7 files, 40 lines — files over, lines ok
  make_manifest "$manifest" 7 40 0 "2026-05-21T10:05:00Z" "2026-05-21T10:20:00Z"

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "budget-check-files-over"
  else
    fail "budget-check-files-over" "expected fail, got: $result (raw: $out)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_under_budget
test_lines_over_budget
test_files_over_budget

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
