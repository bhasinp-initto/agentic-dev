#!/usr/bin/env bash
# cleanup_completed_goal_test.sh
# Deterministic tests for bin/cleanup-completed-goal.sh.
# No claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/agentic-dev/bin/cleanup-completed-goal.sh"

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

make_queue_with_status() {
  local path="$1"
  local goal_status="$2"
  cat > "$path" <<EOF
schema_version: "0.2"
goals:
  - id: "2026-05-21-test-alpha"
    status: $goal_status
    added_at: "2026-05-21T09:00:00Z"
    spec_path: ".claude/agentic/specs/2026-05-21-test-alpha.md"
    intent_path: null
    started_at: "2026-05-21T10:00:00Z"
    completed_at: "2026-05-21T11:00:00Z"
    halted_at: null
    baseline_ref: "abc1234"
    head_ref: "def5678"
    worktree_path: null
    manifest_path: null
EOF
}

# ── Test 1: Completed goal with worktree → worktree removed, success message ──

test_completed_goal_cleanup() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue_with_status "$agentic_dir/queue.yaml" completed

  # Set up a fake git repo + worktree so worktree-cleanup.sh doesn't fail
  # We mock the worktree-cleanup.sh by injecting a mock bin directory into PATH
  local mock_bin="$tmp/mock-bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/worktree-cleanup.sh" <<'MOCK'
#!/usr/bin/env bash
# Mock worktree-cleanup.sh — just confirms it was called and succeeds
echo "removed worktree: .worktrees/goal-${1}"
exit 0
MOCK
  chmod +x "$mock_bin/worktree-cleanup.sh"

  # Override SCRIPT_DIR so cleanup-completed-goal.sh finds our mock
  # We do this by symlinking the mock into a temp bin alongside the script
  local fake_bin="$tmp/fake-bin"
  mkdir -p "$fake_bin"
  # symlink the real scripts, but override worktree-cleanup.sh
  for f in "$REPO_ROOT/agentic-dev/bin/"*.sh; do
    fname="$(basename "$f")"
    if [[ "$fname" != "worktree-cleanup.sh" ]]; then
      ln -sf "$f" "$fake_bin/$fname"
    fi
  done
  cp "$mock_bin/worktree-cleanup.sh" "$fake_bin/worktree-cleanup.sh"

  # Patch PATH so our mock worktree-cleanup.sh is found
  local out exit_code=0
  out="$(cd "$tmp" && PATH="$fake_bin:$PATH" \
    AGENTIC_BIN_DIR="$fake_bin" \
    "$SCRIPT" "2026-05-21-test-alpha" 2>&1)" || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    pass "cleanup-completed-exit0"
  else
    fail "cleanup-completed-exit0" "expected exit 0, got $exit_code. output: $out"
    return
  fi

  # Output should mention removal / success
  if echo "$out" | grep -qi "removed\|cleaned\|success\|completed"; then
    pass "cleanup-completed-success-message"
  else
    fail "cleanup-completed-success-message" "expected success message in output, got: $out"
  fi
}

# ── Test 2: Goal not completed → refused with clear error ─────────────────────

test_non_completed_goal_refused() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue_with_status "$agentic_dir/queue.yaml" running

  local exit_code=0
  local out
  out="$(cd "$tmp" && "$SCRIPT" "2026-05-21-test-alpha" 2>&1)" || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "non-completed-refused-exit1"
  else
    fail "non-completed-refused-exit1" "expected exit 1, got $exit_code"
  fi

  if echo "$out" | grep -qi "not completed\|must be completed\|status.*running\|running.*status\|expected.*completed"; then
    pass "non-completed-refused-message"
  else
    fail "non-completed-refused-message" "expected clear error about non-completed status, got: $out"
  fi
}

# ── Test 3: Unknown goal-id → refused ────────────────────────────────────────

test_unknown_goal_id_refused() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue_with_status "$agentic_dir/queue.yaml" completed

  local exit_code=0
  local out
  out="$(cd "$tmp" && "$SCRIPT" "2026-05-21-nonexistent-goal" 2>&1)" || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "unknown-goal-id-refused-exit1"
  else
    fail "unknown-goal-id-refused-exit1" "expected exit 1, got $exit_code"
  fi

  if echo "$out" | grep -qi "not found\|unknown\|no goal\|missing"; then
    pass "unknown-goal-id-refused-message"
  else
    fail "unknown-goal-id-refused-message" "expected clear error about unknown goal, got: $out"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_script

test_completed_goal_cleanup
test_non_completed_goal_refused
test_unknown_goal_id_refused

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
