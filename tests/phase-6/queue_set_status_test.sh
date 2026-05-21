#!/usr/bin/env bash
# queue_set_status_test.sh
# Deterministic tests for bin/queue-set-status.sh.
# No claude -p. All assertions operate on hand-authored queue.yaml fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/agentic-dev/bin/queue-set-status.sh"

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

make_queue() {
  local path="$1"
  cat > "$path" <<'YAML'
schema_version: "0.2"
goals:
  - id: "2026-05-21-test-alpha"
    status: approved
    added_at: "2026-05-21T09:00:00Z"
    spec_path: ".claude/agentic/specs/2026-05-21-test-alpha.md"
    intent_path: ".claude/agentic/intents/2026-05-21-test-alpha.md"
    started_at: null
    completed_at: null
    halted_at: null
    baseline_ref: null
    head_ref: null
    worktree_path: null
    manifest_path: null
  - id: "2026-05-21-test-beta"
    status: drafted
    added_at: "2026-05-21T09:30:00Z"
    spec_path: null
    intent_path: null
    started_at: null
    completed_at: null
    halted_at: null
    baseline_ref: null
    head_ref: null
    worktree_path: null
    manifest_path: null
YAML
}

# ── Test 1: Happy path — approved → running, started_at populated ─────────────

test_happy_path_running() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue "$agentic_dir/queue.yaml"

  local out exit_code=0
  out="$(cd "$tmp" && "$SCRIPT" "2026-05-21-test-alpha" running \
    started_at="2026-05-21T11:00:00Z" \
    baseline_ref="abc1234" 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "happy-path-running-exit0" "expected exit 0, got $exit_code. output: $out"
    return
  fi
  pass "happy-path-running-exit0"

  # Verify queue.yaml updated (status=running)
  local new_status
  new_status="$(python3 -c "
import yaml
q = yaml.safe_load(open('$agentic_dir/queue.yaml'))
goal = next(g for g in q['goals'] if g['id'] == '2026-05-21-test-alpha')
print(goal['status'])
")"
  if [[ "$new_status" == "running" ]]; then
    pass "happy-path-status-updated"
  else
    fail "happy-path-status-updated" "expected running, got: $new_status"
  fi

  # Verify started_at populated
  local started_at
  started_at="$(python3 -c "
import yaml
q = yaml.safe_load(open('$agentic_dir/queue.yaml'))
goal = next(g for g in q['goals'] if g['id'] == '2026-05-21-test-alpha')
print(goal.get('started_at', 'MISSING'))
")"
  if [[ "$started_at" == "2026-05-21T11:00:00Z" ]]; then
    pass "happy-path-started-at-populated"
  else
    fail "happy-path-started-at-populated" "expected 2026-05-21T11:00:00Z, got: $started_at"
  fi

  # Verify schema-valid result
  local schema_ok
  schema_ok="$(python3 -c "
import yaml, json, jsonschema
schema = json.load(open('$REPO_ROOT/agentic-dev/schemas/queue.schema.json'))
q = yaml.safe_load(open('$agentic_dir/queue.yaml'))
try:
    jsonschema.validate(q, schema)
    print('VALID')
except Exception as e:
    print('INVALID:', e)
")"
  if [[ "$schema_ok" == "VALID" ]]; then
    pass "happy-path-schema-valid"
  else
    fail "happy-path-schema-valid" "schema validation failed: $schema_ok"
  fi
}

# ── Test 2: Bad new-status → exit 1, queue.yaml unchanged ────────────────────

test_bad_status_refused() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue "$agentic_dir/queue.yaml"

  local original_md5
  original_md5="$(md5 -q "$agentic_dir/queue.yaml" 2>/dev/null || md5sum "$agentic_dir/queue.yaml" | awk '{print $1}')"

  local exit_code=0
  cd "$tmp" && "$SCRIPT" "2026-05-21-test-alpha" nonsense 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "bad-status-exits-one"
  else
    fail "bad-status-exits-one" "expected exit 1, got $exit_code"
  fi

  # Queue must be unchanged
  local after_md5
  after_md5="$(md5 -q "$agentic_dir/queue.yaml" 2>/dev/null || md5sum "$agentic_dir/queue.yaml" | awk '{print $1}')"
  if [[ "$original_md5" == "$after_md5" ]]; then
    pass "bad-status-queue-unchanged"
  else
    fail "bad-status-queue-unchanged" "queue.yaml was modified despite invalid status"
  fi
}

# ── Test 3: Unknown goal-id → exit 1 ─────────────────────────────────────────

test_unknown_goal_id_refused() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue "$agentic_dir/queue.yaml"

  local exit_code=0
  cd "$tmp" && "$SCRIPT" "2026-05-21-nonexistent" running 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "unknown-goal-id-exits-one"
  else
    fail "unknown-goal-id-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 4: key=value extra fields work ───────────────────────────────────────

test_extra_fields_via_kv_syntax() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue "$agentic_dir/queue.yaml"

  local exit_code=0
  out="$(cd "$tmp" && "$SCRIPT" "2026-05-21-test-alpha" running \
    started_at="2026-05-21T11:00:00Z" \
    baseline_ref="deadbeef" \
    worktree_path=".worktrees/goal-2026-05-21-test-alpha" 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "extra-fields-kv-exit0" "expected exit 0, got $exit_code. output: $out"
    return
  fi
  pass "extra-fields-kv-exit0"

  local baseline_ref
  baseline_ref="$(python3 -c "
import yaml
q = yaml.safe_load(open('$agentic_dir/queue.yaml'))
goal = next(g for g in q['goals'] if g['id'] == '2026-05-21-test-alpha')
print(goal.get('baseline_ref', 'MISSING'))
")"
  if [[ "$baseline_ref" == "deadbeef" ]]; then
    pass "extra-fields-baseline-ref-set"
  else
    fail "extra-fields-baseline-ref-set" "expected deadbeef, got: $baseline_ref"
  fi

  local worktree_path
  worktree_path="$(python3 -c "
import yaml
q = yaml.safe_load(open('$agentic_dir/queue.yaml'))
goal = next(g for g in q['goals'] if g['id'] == '2026-05-21-test-alpha')
print(goal.get('worktree_path', 'MISSING'))
")"
  if [[ "$worktree_path" == ".worktrees/goal-2026-05-21-test-alpha" ]]; then
    pass "extra-fields-worktree-path-set"
  else
    fail "extra-fields-worktree-path-set" "expected worktree path, got: $worktree_path"
  fi
}

# ── Test 5: Atomic write — .tmp file doesn't linger after success ─────────────

test_atomic_write_no_tmp_linger() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_queue "$agentic_dir/queue.yaml"

  local exit_code=0
  cd "$tmp" && "$SCRIPT" "2026-05-21-test-alpha" running \
    started_at="2026-05-21T11:30:00Z" 2>/dev/null || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "atomic-no-tmp-exit0" "expected exit 0, got $exit_code"
    return
  fi
  pass "atomic-no-tmp-exit0"

  # No .tmp file should linger
  if [[ ! -f "$agentic_dir/queue.yaml.tmp" ]]; then
    pass "atomic-no-tmp-lingers"
  else
    fail "atomic-no-tmp-lingers" "queue.yaml.tmp still exists after successful write"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_script

test_happy_path_running
test_bad_status_refused
test_unknown_goal_id_refused
test_extra_fields_via_kv_syntax
test_atomic_write_no_tmp_linger

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
