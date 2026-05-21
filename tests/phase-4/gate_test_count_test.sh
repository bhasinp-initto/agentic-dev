#!/usr/bin/env bash
# gate_test_count_test.sh
# Deterministic tests for gate-test-count-check.sh.
# Uses hand-authored manifest + kickoff fixtures; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/gate-test-count-check.sh"

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

# ── shared fixture helpers ─────────────────────────────────────────────────────

make_kickoff() {
  local path="$1"
  local baseline_passed="${2:-10}"
  local baseline_failed="${3:-0}"
  local baseline_skipped="${4:-0}"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "spec_path": "/tmp/spec.md",
  "baseline_ref": "abc1234",
  "budget": {
    "wall_clock_minutes_per_goal": 30,
    "diff_lines_per_goal": 100,
    "files_touched_per_goal": 5
  },
  "sensitive_paths": ["auth/**"],
  "project_commands": { "test": "echo passed", "lint": null, "typecheck": null, "build": null },
  "worktree_path": "/tmp/worktree",
  "baseline": {
    "test_counts": { "passed": $baseline_passed, "failed": $baseline_failed, "skipped": $baseline_skipped }
  }
}
EOF
}

make_kickoff_null_baseline() {
  local path="$1"
  cat > "$path" <<'EOF'
{
  "goal_id": "2026-05-21-test-goal",
  "spec_path": "/tmp/spec.md",
  "baseline_ref": "abc1234",
  "budget": {
    "wall_clock_minutes_per_goal": 30,
    "diff_lines_per_goal": 100,
    "files_touched_per_goal": 5
  },
  "sensitive_paths": ["auth/**"],
  "project_commands": { "test": "echo passed", "lint": null, "typecheck": null, "build": null },
  "worktree_path": "/tmp/worktree",
  "baseline": {
    "test_counts": null
  }
}
EOF
}

make_manifest() {
  local path="$1"
  local tests_passed="${2:-15}"
  local tests_failed="${3:-0}"
  local tests_ran="${4:-15}"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "/tmp/worktree",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "tests": {
    "ran": $tests_ran,
    "passed": $tests_passed,
    "failed": $tests_failed,
    "skipped": 0,
    "logs_path": "/tmp/worktree/test-output.log"
  }
}
EOF
}

# ── Test 1: test counts increased (pass) ──────────────────────────────────────

test_counts_increased() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # baseline: 10 passed; manifest: 12 passed — counts increased
  make_kickoff "$kickoff" 10 0 0
  make_manifest "$manifest" 12 0 12

  local out
  out="$("$GATE" "$manifest" "$kickoff")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "test-count-increased-passes"
  else
    fail "test-count-increased-passes" "expected pass, got: $result (raw: $out)"
  fi
}

# ── Test 2: test counts decreased (fail) ─────────────────────────────────────

test_counts_decreased() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # baseline: 10 passed; manifest: 8 passed — drop of 2 tests
  make_kickoff "$kickoff" 10 0 0
  make_manifest "$manifest" 8 2 10

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "test-count-decreased-fails"
  else
    fail "test-count-decreased-fails" "expected fail, got: $result (raw: $out)"
  fi

  # Verify raw has baseline_passed and manifest_passed
  local bp
  bp="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("baseline_passed","missing"))')"
  if [[ "$bp" == "10" ]]; then
    pass "test-count-raw-baseline-passed"
  else
    fail "test-count-raw-baseline-passed" "expected raw.baseline_passed=10, got: $bp"
  fi
}

# ── Test 3: baseline null → inconclusive warning ──────────────────────────────

test_baseline_null_inconclusive() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # baseline.test_counts is null
  make_kickoff_null_baseline "$kickoff"
  make_manifest "$manifest" 12 0 12

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "inconclusive" ]]; then
    pass "test-count-null-baseline-inconclusive"
  else
    fail "test-count-null-baseline-inconclusive" "expected inconclusive, got: $result (raw: $out)"
  fi

  # Severity should be warning (not blocking) for inconclusive
  local severity
  severity="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["severity"])')"
  if [[ "$severity" == "warning" ]]; then
    pass "test-count-null-baseline-severity-warning"
  else
    fail "test-count-null-baseline-severity-warning" "expected severity=warning, got: $severity (raw: $out)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_counts_increased
test_counts_decreased
test_baseline_null_inconclusive

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
