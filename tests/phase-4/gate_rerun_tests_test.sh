#!/usr/bin/env bash
# gate_rerun_tests_test.sh
# Deterministic tests for gate-rerun-tests.sh.
# Uses mock test runner scripts that echo known output; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/gate-rerun-tests.sh"

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

# ── fixture helpers ────────────────────────────────────────────────────────────

make_mock_runner() {
  # Creates a mock test runner at $1 that prints $2 to stdout and exits with $3
  local path="$1"
  local output="$2"
  local exitcode="${3:-0}"
  cat > "$path" <<EOF
#!/usr/bin/env bash
echo "$output"
exit $exitcode
EOF
  chmod +x "$path"
}

make_kickoff() {
  local path="$1"
  local test_cmd="$2"
  local worktree="$3"
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
  "project_commands": { "test": "$test_cmd", "lint": null, "typecheck": null, "build": null },
  "worktree_path": "$worktree",
  "baseline": {
    "test_counts": { "passed": 5, "failed": 0, "skipped": 0 }
  }
}
EOF
}

make_manifest() {
  local path="$1"
  local worktree="$2"
  local tests_passed="${3:-5}"
  local tests_failed="${4:-0}"
  local tests_ran="${5:-5}"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$worktree",
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
    "logs_path": "/tmp/test-output.log"
  }
}
EOF
}

# ── Test 1: mock outputs "5 passed", manifest claims 5 passed → pass ──────────

test_match_pass() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local runner="$tmp/mock-test.sh"
  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  make_mock_runner "$runner" "Tests: 5 passed" 0
  make_kickoff "$kickoff" "bash $runner" "$tmp"
  # manifest: 5 passed, 0 failed — matches mock output
  make_manifest "$manifest" "$tmp" 5 0 5

  local out
  out="$("$GATE" "$manifest" "$kickoff")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "rerun-match-passes"
  else
    fail "rerun-match-passes" "expected pass, got: $result (raw: $out)"
  fi
}

# ── Test 2: mock outputs "5 passed", manifest claims 7 passed → fail ──────────

test_mismatch_fail() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local runner="$tmp/mock-test.sh"
  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  make_mock_runner "$runner" "Tests: 5 passed" 0
  make_kickoff "$kickoff" "bash $runner" "$tmp"
  # manifest claims 7 passed but mock only outputs 5 → mismatch
  make_manifest "$manifest" "$tmp" 7 0 7

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "rerun-mismatch-fails"
  else
    fail "rerun-mismatch-fails" "expected fail, got: $result (raw: $out)"
  fi

  # Also verify severity is blocking
  local severity
  severity="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["severity"])')"
  if [[ "$severity" == "blocking" ]]; then
    pass "rerun-mismatch-severity-blocking"
  else
    fail "rerun-mismatch-severity-blocking" "expected blocking, got: $severity (raw: $out)"
  fi
}

# ── Test 3: mock outputs unparseable text → inconclusive warning ───────────────

test_unparseable_inconclusive() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local runner="$tmp/mock-test.sh"
  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  make_mock_runner "$runner" "Sometimes something weird that doesn't parse" 0
  make_kickoff "$kickoff" "bash $runner" "$tmp"
  make_manifest "$manifest" "$tmp" 5 0 5

  local out
  out="$("$GATE" "$manifest" "$kickoff")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "inconclusive" ]]; then
    pass "rerun-unparseable-inconclusive"
  else
    fail "rerun-unparseable-inconclusive" "expected inconclusive, got: $result (raw: $out)"
  fi

  # Severity should be warning (not blocking) for inconclusive
  local severity
  severity="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["severity"])')"
  if [[ "$severity" == "warning" ]]; then
    pass "rerun-unparseable-severity-warning"
  else
    fail "rerun-unparseable-severity-warning" "expected warning, got: $severity (raw: $out)"
  fi
}

# ── Test 4: mock "3 passed", manifest claims 3 passed + 1 failed; verify both ─

test_failed_count_checked() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local runner="$tmp/mock-test.sh"
  local kickoff="$tmp/kickoff.json"
  local manifest="$tmp/manifest.json"

  # Mock outputs "3 passed, 1 failed"
  make_mock_runner "$runner" "Tests: 3 passed, 1 failed" 1
  make_kickoff "$kickoff" "bash $runner" "$tmp"
  # manifest: 3 passed, 1 failed — matches mock output exactly
  make_manifest "$manifest" "$tmp" 3 1 4

  local out
  out="$("$GATE" "$manifest" "$kickoff")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "rerun-passed-and-failed-match-passes"
  else
    fail "rerun-passed-and-failed-match-passes" "expected pass, got: $result (raw: $out)"
  fi

  # Verify raw has actual_passed and actual_failed
  local actual_passed
  actual_passed="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("actual_passed","missing"))')"
  if [[ "$actual_passed" == "3" ]]; then
    pass "rerun-raw-actual-passed"
  else
    fail "rerun-raw-actual-passed" "expected raw.actual_passed=3, got: $actual_passed (raw: $out)"
  fi

  local actual_failed
  actual_failed="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("actual_failed","missing"))')"
  if [[ "$actual_failed" == "1" ]]; then
    pass "rerun-raw-actual-failed"
  else
    fail "rerun-raw-actual-failed" "expected raw.actual_failed=1, got: $actual_failed (raw: $out)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_match_pass
test_mismatch_fail
test_unparseable_inconclusive
test_failed_count_checked

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
