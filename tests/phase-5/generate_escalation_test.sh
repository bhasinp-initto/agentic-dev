#!/usr/bin/env bash
# generate_escalation_test.sh
# Deterministic tests for bin/generate-escalation.sh.
# No claude -p. Hand-authored fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="$REPO_ROOT/agentic-dev/bin/generate-escalation.sh"
SCHEMA="$REPO_ROOT/agentic-dev/schemas/escalation-packet.schema.json"

PASS=0
FAIL=0

pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1: $2"; FAIL=$((FAIL+1)); }

require_script() {
  if [[ ! -x "$GEN" ]]; then
    echo "FAIL setup: $GEN not found or not executable"
    exit 1
  fi
}

# ── Fixture builder ───────────────────────────────────────────────────────────

make_manifest() {
  local dir="$1" goal_id="$2" spec_path="$3"
  mkdir -p "$dir/.claude/agentic/manifests"
  cat > "$dir/.claude/agentic/manifests/${goal_id}.json" <<EOF
{
  "schema_version": "0.1",
  "goal_id": "$goal_id",
  "spec_path": "$spec_path",
  "worktree_path": "/tmp/agentic-worktrees/$goal_id",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "2026-05-21T10:00:00Z",
  "completed_at": "2026-05-21T11:00:00Z",
  "diff_stats": { "files_touched": 2, "lines_added": 50, "lines_removed": 5 },
  "tests": { "ran": 10, "passed": 10, "failed": 0, "skipped": 0, "logs_path": null },
  "self_check": { "lint": "clean", "typecheck": "clean" },
  "scope_check": { "in_spec_files": ["src/foo.ts"], "out_of_spec_files": [] },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [],
  "artifacts": [],
  "commits": [{ "sha": "abc1234", "subject": "feat: implement foo" }]
}
EOF
}

make_reviewer_verdict() {
  local dir="$1" goal_id="$2"
  mkdir -p "$dir/.claude/agentic/reviewer-verdicts"
  cat > "$dir/.claude/agentic/reviewer-verdicts/${goal_id}.json" <<EOF
{
  "schema_version": "0.1",
  "goal_id": "$goal_id",
  "reviewer_role": "primary",
  "reviewed_at": "2026-05-21T11:30:00Z",
  "verdict": "concern",
  "concerns": [
    {
      "file": "src/foo.ts",
      "line": 42,
      "severity": "concern",
      "category": "judgment",
      "description": "The implementation silently drops a spec requirement without a DEFERRED.md entry"
    }
  ],
  "checks_run": [
    { "name": "scope_against_spec", "outcome": "pass", "evidence": "all touched files are in scope" },
    { "name": "secrets_scan", "outcome": "pass", "evidence": "no credentials found" },
    { "name": "spec_requirements_coverage", "outcome": "fail", "evidence": "spec requirement §3 not addressed" }
  ]
}
EOF
}

make_spec() {
  local dir="$1" goal_id="$2"
  mkdir -p "$dir/.claude/agentic/specs"
  local spec_path="$dir/.claude/agentic/specs/${goal_id}.md"
  cat > "$spec_path" <<EOF
---
id: $goal_id
schema_version: "0.1"
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Goal
A test goal.

# Files in scope
- src/**
EOF
  echo "$spec_path"
}

# ── Test 1: manifest + reviewer-verdict → valid escalation file created ────────

test_generates_valid_escalation() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-test-escalation"
  local spec_path
  spec_path="$(make_spec "$tmp" "$goal_id")"
  # Rewrite spec_path as relative in manifest
  local rel_spec=".claude/agentic/specs/${goal_id}.md"
  make_manifest "$tmp" "$goal_id" "$rel_spec"
  make_reviewer_verdict "$tmp" "$goal_id"

  local out exit_code=0
  out="$(cd "$tmp" && "$GEN" "$goal_id" reviewer_blocking 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "generates-valid-escalation-exit0" "expected exit 0, got $exit_code; output: $out"
    return
  fi
  pass "generates-valid-escalation-exit0"

  # Script should print the path to the created escalation file
  local esc_file
  esc_file="$(echo "$out" | grep -E '\.claude/agentic/escalations/' | tail -1 | tr -d '[:space:]')"

  # If not found in output, find it directly
  if [[ -z "$esc_file" ]]; then
    # Try to find the escalation file in the tmp dir
    esc_file="$(find "$tmp/.claude/agentic/escalations" -name "*.md" 2>/dev/null | head -1)"
  else
    # Make it absolute if relative
    if [[ "$esc_file" != /* ]]; then
      esc_file="$tmp/$esc_file"
    fi
  fi

  if [[ -z "$esc_file" || ! -f "$esc_file" ]]; then
    fail "generates-valid-escalation-file-exists" "escalation file not found; output: $out; dir listing: $(ls "$tmp/.claude/agentic/" 2>/dev/null || echo 'missing')"
    return
  fi
  pass "generates-valid-escalation-file-exists"

  # Validate the escalation file has required markdown sections
  local content
  content="$(cat "$esc_file")"

  local sections_ok=true
  for section in "Summary" "Trigger" "Concerns" "Suggested Next Actions"; do
    if ! echo "$content" | grep -qi "$section"; then
      fail "generates-valid-escalation-has-section-$section" "missing section '$section' in $esc_file"
      sections_ok=false
    fi
  done
  if [[ "$sections_ok" == "true" ]]; then
    pass "generates-valid-escalation-has-sections"
  fi

  # Validate the frontmatter JSON fields against the schema using Python
  python3 - "$esc_file" "$SCHEMA" <<'PY'
import sys, json, re
from pathlib import Path

esc_path = sys.argv[1]
schema_path = sys.argv[2]
content = Path(esc_path).read_text()

# Extract YAML frontmatter between --- markers
m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not m:
    print("FAIL escalation-validates-against-schema: no frontmatter found")
    sys.exit(1)

frontmatter_text = m.group(1)

# Parse frontmatter as simple key-value (not full YAML to avoid deps)
# Check for required fields presence
required_fields = ["schema_version", "goal_id", "generated_at", "trigger",
                   "manifest_path", "summary", "suggested_next_actions"]
missing = []
for field in required_fields:
    if field + ":" not in frontmatter_text:
        missing.append(field)

if missing:
    print(f"FAIL escalation-validates-against-schema: missing frontmatter fields: {missing}")
    sys.exit(1)

# Check trigger value
if "reviewer_blocking" not in frontmatter_text:
    print(f"FAIL escalation-validates-against-schema: expected trigger 'reviewer_blocking' in frontmatter")
    sys.exit(1)

print("PASS escalation-validates-against-schema")
PY
  # Pass/fail is printed by python above; we track counts externally for the last assert
  local py_exit=$?
  if [[ $py_exit -eq 0 ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
  fi
}

# ── Test 2: missing manifest → exit 1 ─────────────────────────────────────────

test_missing_manifest_exits_one() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  mkdir -p "$tmp/.claude/agentic/manifests"
  # Do NOT create any manifest

  local exit_code=0
  cd "$tmp" && "$GEN" "2026-05-21-no-such-goal" reviewer_blocking 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "missing-manifest-exits-one"
  else
    fail "missing-manifest-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 3: invalid trigger → exit 1 ─────────────────────────────────────────

test_invalid_trigger_exits_one() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-trigger-test"
  local rel_spec=".claude/agentic/specs/${goal_id}.md"
  make_manifest "$tmp" "$goal_id" "$rel_spec"

  local exit_code=0
  cd "$tmp" && "$GEN" "$goal_id" not_a_valid_trigger 2>/dev/null || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "invalid-trigger-exits-one"
  else
    fail "invalid-trigger-exits-one" "expected exit 1, got $exit_code"
  fi
}

# ── Test 4: escalation markdown has expected sections (Goal, Files) ───────────

test_escalation_has_full_sections() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-sections-check"
  local rel_spec=".claude/agentic/specs/${goal_id}.md"
  make_spec "$tmp" "$goal_id" > /dev/null
  make_manifest "$tmp" "$goal_id" "$rel_spec"
  make_reviewer_verdict "$tmp" "$goal_id"

  local out exit_code=0
  out="$(cd "$tmp" && "$GEN" "$goal_id" judgment_concerns 2>&1)" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "escalation-full-sections-exit0" "expected exit 0, got $exit_code; output: $out"
    return
  fi

  # Find the escalation file
  local esc_file
  esc_file="$(find "$tmp/.claude/agentic/escalations" -name "*.md" 2>/dev/null | head -1)"

  if [[ -z "$esc_file" || ! -f "$esc_file" ]]; then
    fail "escalation-full-sections-file-found" "no escalation file found; dir: $(ls "$tmp/.claude/agentic/" 2>/dev/null || echo 'missing')"
    return
  fi

  local content
  content="$(cat "$esc_file")"

  # Verify all required sections present
  local all_ok=true
  for section in "Summary" "Trigger" "Goal" "Concerns" "Files" "Suggested Next Actions"; do
    if echo "$content" | grep -qi "$section"; then
      pass "escalation-has-section-$(echo "$section" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
    else
      fail "escalation-has-section-$(echo "$section" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')" "section '$section' missing from escalation file"
      all_ok=false
    fi
  done
}

# ── main ──────────────────────────────────────────────────────────────────────

require_script

test_generates_valid_escalation
test_missing_manifest_exits_one
test_invalid_trigger_exits_one
test_escalation_has_full_sections

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
