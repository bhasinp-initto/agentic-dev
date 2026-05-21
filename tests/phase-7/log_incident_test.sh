#!/usr/bin/env bash
# log_incident_test.sh
# Deterministic tests for agentic-dev/bin/log-incident.sh.
# No claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/agentic-dev/bin/log-incident.sh"

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

# ── fixture helpers ───────────────────────────────────────────────────────────

make_empty_checklist() {
  local path="$1"
  cat > "$path" <<'EOF'
schema_version: "0.1"
entries: []
EOF
}

make_empty_memory() {
  local path="$1"
  cat > "$path" <<'EOF'
schema_version: "0.1"
entries: []
EOF
}

count_entries() {
  # Returns number of entries in the yaml file via Python
  python3 -c "
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
print(len(data.get('entries', [])))
" "$1"
}

validate_against_schema() {
  # Returns 0 if valid, 1 if not
  python3 -c "
import yaml, json, jsonschema, sys
data = yaml.safe_load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    jsonschema.validate(data, schema)
    sys.exit(0)
except jsonschema.ValidationError as e:
    print(e.message, file=sys.stderr)
    sys.exit(1)
" "$1" "$2"
}

CHECKLIST_SCHEMA="$REPO_ROOT/agentic-dev/schemas/checklist.schema.json"
MEMORY_SCHEMA="$REPO_ROOT/agentic-dev/schemas/memory.schema.json"

# ── Test 1: append to checklist → one entry added, schema-valid ──────────────

test_append_checklist() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_empty_checklist "$agentic_dir/checklist.yaml"

  local exit_code=0
  (cd "$tmp" && "$SCRIPT" checklist \
    "rule=Always check tenant scope on every raw DB query path" \
    "caught_by=reviewer" \
    "incident_ref=ESC-2026-05-21-001" 2>&1) || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "checklist-append-exit0" "expected exit 0, got $exit_code"
    return
  fi
  pass "checklist-append-exit0"

  local count
  count="$(count_entries "$agentic_dir/checklist.yaml")"
  if [[ "$count" -eq 1 ]]; then
    pass "checklist-append-one-entry"
  else
    fail "checklist-append-one-entry" "expected 1 entry, got $count"
  fi

  if validate_against_schema "$agentic_dir/checklist.yaml" "$CHECKLIST_SCHEMA" 2>/dev/null; then
    pass "checklist-append-schema-valid"
  else
    fail "checklist-append-schema-valid" "result failed schema validation"
  fi
}

# ── Test 2: append to memory → one entry added, schema-valid ─────────────────

test_append_memory() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_empty_memory "$agentic_dir/memory.yaml"

  local exit_code=0
  (cd "$tmp" && "$SCRIPT" memory \
    "observation=Implementer guessed tenant_id when spec was silent on scoping" \
    "consequence=Added explicit rule to drafter calibration table for tenant specs" 2>&1) || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "memory-append-exit0" "expected exit 0, got $exit_code"
    return
  fi
  pass "memory-append-exit0"

  local count
  count="$(count_entries "$agentic_dir/memory.yaml")"
  if [[ "$count" -eq 1 ]]; then
    pass "memory-append-one-entry"
  else
    fail "memory-append-one-entry" "expected 1 entry, got $count"
  fi

  if validate_against_schema "$agentic_dir/memory.yaml" "$MEMORY_SCHEMA" 2>/dev/null; then
    pass "memory-append-schema-valid"
  else
    fail "memory-append-schema-valid" "result failed schema validation"
  fi
}

# ── Test 3: bad type → exit 1 ─────────────────────────────────────────────────

test_bad_type() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"

  local exit_code=0
  (cd "$tmp" && "$SCRIPT" garbage "rule=some rule here" 2>/dev/null) || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "bad-type-exits-one"
  else
    fail "bad-type-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 4: missing required key (checklist without rule=) → exit 1 ──────────

test_missing_required_key() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_empty_checklist "$agentic_dir/checklist.yaml"

  local exit_code=0
  (cd "$tmp" && "$SCRIPT" checklist "caught_by=reviewer" 2>/dev/null) || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "missing-required-key-exits-one"
  else
    fail "missing-required-key-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 5: schema-invalid input (rule too short) → exit 1 ───────────────────

test_schema_invalid_input() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_empty_checklist "$agentic_dir/checklist.yaml"

  local exit_code=0
  (cd "$tmp" && "$SCRIPT" checklist \
    "rule=short" \
    "caught_by=reviewer" 2>/dev/null) || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "schema-invalid-rule-exits-one"
  else
    fail "schema-invalid-rule-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 6: atomic — schema-invalid input → original file untouched ──────────

test_atomic_on_failure() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local agentic_dir="$tmp/.claude/agentic"
  mkdir -p "$agentic_dir"
  make_empty_checklist "$agentic_dir/checklist.yaml"

  # Record original content
  local orig
  orig="$(python3 -c "import yaml; print(yaml.safe_load(open('$agentic_dir/checklist.yaml')))" 2>&1)"

  # Attempt schema-invalid append (rule too short)
  (cd "$tmp" && "$SCRIPT" checklist \
    "rule=tiny" \
    "caught_by=human" 2>/dev/null) || true

  # Verify count is still 0 (original untouched)
  local count
  count="$(count_entries "$agentic_dir/checklist.yaml")"
  if [[ "$count" -eq 0 ]]; then
    pass "atomic-original-untouched"
  else
    fail "atomic-original-untouched" "expected 0 entries after failed write, got $count"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

require_script

test_append_checklist
test_append_memory
test_bad_type
test_missing_required_key
test_schema_invalid_input
test_atomic_on_failure

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
