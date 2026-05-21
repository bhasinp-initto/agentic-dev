#!/usr/bin/env bash
# gate_sensitive_path_test.sh
# Deterministic tests for gate-sensitive-path-check.sh.
# Sets up a real tmp git repo + worktree fixture; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/gate-sensitive-path-check.sh"

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

setup_git_repo() {
  local dir="$1"
  git init -q "$dir"
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
}

make_commit() {
  local repo="$1" file="$2" content="${3:-content}"
  mkdir -p "$(dirname "$repo/$file")"
  echo "$content" > "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -q -m "add $file"
}

make_config() {
  local path="$1"
  cat > "$path" <<'CFG'
schema_version: "0.1"
project:
  name: test-project
  primary_language: javascript
commands:
  test: "npm test"
  lint: "npm run lint"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 90
  diff_lines_per_goal: 800
  files_touched_per_goal: 25
sensitive_paths:
  - "auth/**"
  - "migrations/**"
  - "secrets/**"
telegram: null
push_policy: hold
CFG
}

make_manifest() {
  local path="$1" repo="$2" baseline="$3" head="$4"
  cat > "$path" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$repo",
  "baseline_ref": "$baseline",
  "head_ref": "$head",
  "status": "complete"
}
EOF
}

# ── Test 1: no sensitive paths touched → pass ──────────────────────────────────

test_no_sensitive_touched() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  # baseline commit
  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # head commits: only safe paths
  make_commit "$repo" "src/health.ts" "export const health = () => 'ok';"
  make_commit "$repo" "tests/health.test.ts" "test('health', () => {});"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local config="$tmp/config.yaml"
  make_config "$config"

  local manifest="$tmp/manifest.json"
  make_manifest "$manifest" "$repo" "$baseline" "$head"

  local out
  out="$("$GATE" "$manifest" "$config")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "sensitive-path-none-touched"
  else
    fail "sensitive-path-none-touched" "expected pass, got: $result (raw: $out)"
  fi
}

# ── Test 2: one auth/ file touched → fail ─────────────────────────────────────

test_auth_file_touched() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  # baseline commit
  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # head commits: one safe, one in auth/
  make_commit "$repo" "src/health.ts" "export const health = () => 'ok';"
  make_commit "$repo" "auth/session.ts" "export const session = {};"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local config="$tmp/config.yaml"
  make_config "$config"

  local manifest="$tmp/manifest.json"
  make_manifest "$manifest" "$repo" "$baseline" "$head"

  local out
  out="$("$GATE" "$manifest" "$config")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "sensitive-path-auth-fails"
  else
    fail "sensitive-path-auth-fails" "expected fail, got: $result (raw: $out)"
  fi
}

# ── Test 3: matched file listed in raw output ──────────────────────────────────

test_matched_file_in_raw() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  # baseline commit
  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # head commits: touch migrations/
  make_commit "$repo" "migrations/001_create_users.sql" "CREATE TABLE users (id INT);"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local config="$tmp/config.yaml"
  make_config "$config"

  local manifest="$tmp/manifest.json"
  make_manifest "$manifest" "$repo" "$baseline" "$head"

  local out
  out="$("$GATE" "$manifest" "$config")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "sensitive-path-migrations-fails"
  else
    fail "sensitive-path-migrations-fails" "expected fail, got: $result (raw: $out)"
  fi

  # Verify the matched file appears in raw.matched_files
  local matched
  matched="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("matched_files",[]))')"
  if echo "$matched" | grep -q "001_create_users.sql"; then
    pass "sensitive-path-matched-file-in-raw"
  else
    fail "sensitive-path-matched-file-in-raw" "001_create_users.sql not found in raw.matched_files: $matched"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_no_sensitive_touched
test_auth_file_touched
test_matched_file_in_raw

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
