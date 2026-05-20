#!/usr/bin/env bash
# End-to-end test: /agentic-dev:intent "<text>" produces an intent file and
# a draft spec file with QUESTION-N blocks and approved=false.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-intent-fresh-XXXXXX)"
# Set KEEP_TMP=1 to preserve the tmp project on exit for debugging.
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Init the project first (uses P1's init skill + fixture)
init_out="$TMP_PROJECT/_init_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >"$init_out" 2>&1 || true

if [[ ! -f .claude/agentic/state.json ]]; then
  echo "FAIL setup: init did not produce state.json" >&2
  cat "$init_out" >&2
  exit 1
fi

# Now run the intent skill
intent_out="$TMP_PROJECT/_intent_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent Add rate limiting per-tenant to the API" >"$intent_out" 2>&1 || true

ok=1
must_exist() {
  if [[ ! -e "$1" ]]; then
    echo "FAIL missing: $1" >&2
    ok=0
  else
    echo "PASS exists: $1"
  fi
}

# An intent file should have been created under .claude/agentic/intents/
intent_files=(.claude/agentic/intents/*.md)
if [[ "${intent_files[0]}" == ".claude/agentic/intents/*.md" ]]; then
  echo "FAIL missing: .claude/agentic/intents/*.md" >&2
  ok=0
else
  echo "PASS exists: ${intent_files[0]}"
fi

# A spec file should have been created under .claude/agentic/specs/
spec_files=(.claude/agentic/specs/*.md)
if [[ "${spec_files[0]}" == ".claude/agentic/specs/*.md" ]]; then
  echo "FAIL missing: .claude/agentic/specs/*.md" >&2
  ok=0
else
  echo "PASS exists: ${spec_files[0]}"
fi

if [[ $ok -ne 1 ]]; then
  echo "--- Intent claude output was: ---" >&2
  cat "$intent_out" >&2
  exit 1
fi

SPEC_FILE="${spec_files[0]}"
INTENT_FILE="${intent_files[0]}"

# Frontmatter checks via the deterministic validator
"$PLUGIN_DIR/bin/validate-spec.sh" "$SPEC_FILE"

# Approved should be false
if ! grep -qE '^approved:\s*false' "$SPEC_FILE"; then
  echo "FAIL: spec frontmatter does not have approved: false" >&2
  cat "$SPEC_FILE" >&2
  exit 1
fi
echo "PASS spec has approved: false"

# At least one QUESTION-N block should be present
question_count=$(grep -cE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" || echo "0")
if [[ "$question_count" -lt 1 ]]; then
  echo "FAIL: spec has 0 QUESTION-N blocks (expected at least 1)" >&2
  cat "$SPEC_FILE" >&2
  exit 1
fi
echo "PASS spec has $question_count QUESTION-N block(s)"

# QUESTION-N blocks must be well-formed: each QUESTION marker should be
# followed by **Your answer:** somewhere within ~20 lines.
your_answer_count=$(grep -cE '^\*\*Your answer:\*\*' "$SPEC_FILE" || echo "0")
if [[ "$your_answer_count" -lt "$question_count" ]]; then
  echo "FAIL: spec has $question_count QUESTION-N markers but only $your_answer_count **Your answer:** lines (every QUESTION must have an answer placeholder)" >&2
  cat "$SPEC_FILE" >&2
  exit 1
fi
echo "PASS each QUESTION-N has a matching **Your answer:** placeholder ($your_answer_count placeholders)"

# The required sections should all be present
for section in "# Intent" "# Scope — In" "# Scope — Out" "# Files in scope" "# Architectural decisions" "# ADR candidates" "# Test strategy" "# Completion criteria" "# Diff budget"; do
  if ! grep -qF "$section" "$SPEC_FILE"; then
    echo "FAIL: spec missing section: $section" >&2
    cat "$SPEC_FILE" >&2
    exit 1
  fi
done
echo "PASS spec has all 9 required sections"

# Intent file should contain the human's text verbatim
if ! grep -qF "Add rate limiting per-tenant to the API" "$INTENT_FILE"; then
  echo "FAIL: intent file does not contain the original text" >&2
  cat "$INTENT_FILE" >&2
  exit 1
fi
echo "PASS intent file contains original text"

# --- Idempotency check ---
# Re-running with the same intent text must NOT re-draft. The skill should
# detect the existing intent file and print the existing path.
idempotency_out="$TMP_PROJECT/_idempotency_output.txt"
spec_mtime_before=$(stat -f "%m" "$SPEC_FILE" 2>/dev/null || stat -c "%Y" "$SPEC_FILE")
sleep 1
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent Add rate limiting per-tenant to the API" >"$idempotency_out" 2>&1 || true
spec_mtime_after=$(stat -f "%m" "$SPEC_FILE" 2>/dev/null || stat -c "%Y" "$SPEC_FILE")

if [[ "$spec_mtime_before" != "$spec_mtime_after" ]]; then
  echo "FAIL idempotency: spec file was re-written on duplicate /agentic-dev:intent invocation" >&2
  cat "$idempotency_out" >&2
  exit 1
fi
echo "PASS idempotency: spec file untouched on duplicate invocation"

echo "intent_fresh_test: OK"
