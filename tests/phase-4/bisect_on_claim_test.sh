#!/usr/bin/env bash
# bisect_on_claim_test.sh
# Deterministic tests for bisect-on-claim.sh.
# Uses a real local git repo + mock test runner to avoid any claude -p calls.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/bisect-on-claim.sh"

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

# Create a minimal git repo at $1 with one commit and return its SHA
setup_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  echo "initial" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit --quiet -m "initial commit"
  git -C "$dir" rev-parse HEAD
}

make_manifest_no_deferrals() {
  local path="$1"
  local worktree="$2"
  local baseline_ref="$3"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$worktree",
  "baseline_ref": "$baseline_ref",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "deferrals": [],
  "tests": {
    "ran": 5, "passed": 5, "failed": 0, "skipped": 0,
    "logs_path": "/tmp/test-output.log"
  },
  "project_commands": { "test": "echo passed", "lint": null, "typecheck": null, "build": null }
}
EOF
}

make_manifest_with_preexisting() {
  local path="$1"
  local worktree="$2"
  local baseline_ref="$3"
  local test_cmd="$4"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$worktree",
  "baseline_ref": "$baseline_ref",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "deferrals": [
    {
      "id": "D-001",
      "reason": "pre-existing failure in auth suite; not introduced by this goal",
      "details": "auth.test.ts fails on baseline"
    }
  ],
  "tests": {
    "ran": 5, "passed": 4, "failed": 1, "skipped": 0,
    "logs_path": "/tmp/test-output.log"
  },
  "project_commands": { "test": "$test_cmd", "lint": null, "typecheck": null, "build": null }
}
EOF
}

# ── Test 1: no deferrals mentioning pre-existing → pass (nothing to check) ────

test_no_deferrals_pass() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  local baseline_ref
  baseline_ref="$(setup_git_repo "$repo")"

  local manifest="$tmp/manifest.json"
  make_manifest_no_deferrals "$manifest" "$repo" "$baseline_ref"

  local out
  out="$("$GATE" "$manifest")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "bisect-no-deferrals-pass"
  else
    fail "bisect-no-deferrals-pass" "expected pass, got: $result (raw: $out)"
  fi

  # Details should mention "no pre-existing claims"
  local details
  details="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["details"])')"
  if echo "$details" | grep -qi "no pre-existing"; then
    pass "bisect-no-deferrals-details"
  else
    fail "bisect-no-deferrals-details" "expected 'no pre-existing' in details, got: $details"
  fi
}

# ── Test 2: pre-existing claim + mock test fails on baseline → confirmed (pass) ─

test_preexisting_confirmed_pass() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  # Create a mock runner that FAILS (exit 1) — simulating a test that fails on baseline
  local runner="$tmp/mock-fail.sh"
  cat > "$runner" <<'SCRIPT'
#!/usr/bin/env bash
echo "1 test failed"
exit 1
SCRIPT
  chmod +x "$runner"

  local repo="$tmp/repo"
  local baseline_ref
  baseline_ref="$(setup_git_repo "$repo")"

  local manifest="$tmp/manifest.json"
  make_manifest_with_preexisting "$manifest" "$repo" "$baseline_ref" "bash $runner"

  local out
  out="$("$GATE" "$manifest")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "bisect-preexisting-confirmed-pass"
  else
    fail "bisect-preexisting-confirmed-pass" "expected pass (confirmed pre-existing), got: $result (raw: $out)"
  fi

  # Details should mention "confirmed" or "pre-existing"
  local details
  details="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["details"])')"
  if echo "$details" | grep -qi "confirm"; then
    pass "bisect-preexisting-confirmed-details"
  else
    fail "bisect-preexisting-confirmed-details" "expected 'confirm' in details, got: $details"
  fi
}

# ── Test 3: pre-existing claim + mock test passes on baseline → false claim (fail) ─

test_false_preexisting_claim_fail() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  # Create a mock runner that PASSES (exit 0) — baseline is green; claim is false
  local runner="$tmp/mock-pass.sh"
  cat > "$runner" <<'SCRIPT'
#!/usr/bin/env bash
echo "5 passed"
exit 0
SCRIPT
  chmod +x "$runner"

  local repo="$tmp/repo"
  local baseline_ref
  baseline_ref="$(setup_git_repo "$repo")"

  local manifest="$tmp/manifest.json"
  make_manifest_with_preexisting "$manifest" "$repo" "$baseline_ref" "bash $runner"

  local out
  out="$("$GATE" "$manifest")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "bisect-false-claim-fails"
  else
    fail "bisect-false-claim-fails" "expected fail (false pre-existing claim), got: $result (raw: $out)"
  fi

  # Severity should be blocking
  local severity
  severity="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["severity"])')"
  if [[ "$severity" == "blocking" ]]; then
    pass "bisect-false-claim-severity-blocking"
  else
    fail "bisect-false-claim-severity-blocking" "expected blocking, got: $severity (raw: $out)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_no_deferrals_pass
test_preexisting_confirmed_pass
test_false_preexisting_claim_fail

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
