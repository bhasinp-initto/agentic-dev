#!/usr/bin/env bash
# gate_scope_check_test.sh
# Deterministic tests for gate-scope-check.sh.
# Sets up a real tmp git repo + worktree fixture; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/agentic-dev/bin/gate-scope-check.sh"

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

# ── shared fixture setup ──────────────────────────────────────────────────────

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

make_spec() {
  local path="$1"
  cat > "$path" <<'SPEC'
# Goal

A test goal.

# Files in scope
- src/**
- tests/**

# Requirements

Do stuff.
SPEC
}

# ── Test 1: all files in scope → pass ────────────────────────────────────────

test_all_in_scope() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  # baseline commit
  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # head commit: files inside src/
  make_commit "$repo" "src/health.ts" "export const health = () => 'ok';"
  make_commit "$repo" "tests/health.test.ts" "test('health', () => {});"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local spec="$tmp/spec.md"
  make_spec "$spec"

  local manifest="$tmp/manifest.json"
  cat > "$manifest" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$repo",
  "baseline_ref": "$baseline",
  "head_ref": "$head",
  "scope_check": { "in_spec_files": ["src/health.ts", "tests/health.test.ts"], "out_of_spec_files": [] }
}
EOF

  local out
  out="$("$GATE" "$manifest" "$spec")"
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "pass" ]]; then
    pass "scope-check-all-in-scope"
  else
    fail "scope-check-all-in-scope" "expected pass, got: $result (raw: $out)"
  fi
}

# ── Test 2: out-of-scope file → fail ─────────────────────────────────────────

test_out_of_scope_file() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  # baseline commit
  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # head commits: one in-scope, one out-of-scope
  make_commit "$repo" "src/health.ts" "export const health = () => 'ok';"
  make_commit "$repo" "src/secrets/leaked.ts" "export const SECRET = 'shhh';"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local spec="$tmp/spec.md"
  make_spec "$spec"
  # spec only allows src/** and tests/** — but src/secrets/leaked.ts is out of scope
  # because globs like `src/**` DO match `src/secrets/leaked.ts`...
  # make spec more restrictive: only src/health.ts and tests/**
  cat > "$spec" <<'SPEC'
# Goal

A test goal.

# Files in scope
- src/health.ts
- tests/**

# Requirements

Do stuff.
SPEC

  local manifest="$tmp/manifest.json"
  cat > "$manifest" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$repo",
  "baseline_ref": "$baseline",
  "head_ref": "$head",
  "scope_check": { "in_spec_files": ["src/health.ts"], "out_of_spec_files": ["src/secrets/leaked.ts"] }
}
EOF

  local out
  out="$("$GATE" "$manifest" "$spec")" || true
  local result
  result="$(echo "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')"

  if [[ "$result" == "fail" ]]; then
    pass "scope-check-out-of-scope-fails"
  else
    fail "scope-check-out-of-scope-fails" "expected fail, got: $result (raw: $out)"
  fi

  # Also verify that the out_of_spec file is listed in raw
  local oos
  oos="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("computed_out_of_spec",[]))')"
  if echo "$oos" | grep -q "leaked.ts"; then
    pass "scope-check-out-of-scope-file-listed"
  else
    fail "scope-check-out-of-scope-file-listed" "leaked.ts not found in raw.computed_out_of_spec: $oos"
  fi
}

# ── Test 3: manifest's claimed out_of_spec matches actual → no discipline flag ──

test_no_discipline_issue_when_claims_match() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local repo="$tmp/repo"
  setup_git_repo "$repo"

  make_commit "$repo" "README.md" "readme"
  local baseline
  baseline="$(git -C "$repo" rev-parse HEAD)"

  # Touch one in-scope file
  make_commit "$repo" "src/health.ts" "export const health = () => 'ok';"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"

  local spec="$tmp/spec.md"
  make_spec "$spec"

  # Manifest correctly claims out_of_spec_files=[]
  local manifest="$tmp/manifest.json"
  cat > "$manifest" <<EOF
{
  "goal_id": "2026-05-21-test-goal",
  "worktree_path": "$repo",
  "baseline_ref": "$baseline",
  "head_ref": "$head",
  "scope_check": { "in_spec_files": ["src/health.ts"], "out_of_spec_files": [] }
}
EOF

  local out
  out="$("$GATE" "$manifest" "$spec")"
  local discipline
  discipline="$(echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("raw",{}).get("discipline_issue","n/a"))')"

  if [[ "$discipline" == "False" || "$discipline" == "n/a" ]]; then
    pass "scope-check-no-discipline-issue"
  else
    fail "scope-check-no-discipline-issue" "expected no discipline_issue, got: $discipline (raw: $out)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_gate

test_all_in_scope
test_out_of_scope_file
test_no_discipline_issue_when_claims_match

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
