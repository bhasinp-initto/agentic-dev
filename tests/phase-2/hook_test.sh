#!/usr/bin/env bash
# tests/phase-2/hook_test.sh
#
# Verifies that:
#   1. agentic-dev/hooks/hooks.json is structurally valid and references
#      validate-spec.sh as a PostToolUse hook on Write|Edit.
#   2. validate-spec.sh, when invoked in hook mode (JSON on stdin
#      describing a Write|Edit tool_input), produces the correct output
#      for the two key scenarios:
#         a. approved=true with an unresolved QUESTION block → exits 1
#            with "spec validation failed" on stdout (Claude Code's hook
#            transcript captures stdout).
#         b. approved=true with all QUESTIONs resolved → exits 0 with
#            "state: approved" + "_check-approval" next-step on stdout.
#
# Why direct stdin piping instead of `claude -p`:
#   Earlier iterations of this test invoked `claude -p` and asked the LLM
#   to use the Edit tool. That coupled the test to (a) LLM determinism on
#   tool selection (Edit vs Write vs narration), and (b) Claude Code CLI
#   flag stability (--output-format=stream-json --include-hook-events).
#   Both are real fragilities orthogonal to what we built.
#
#   The HOOK FIRING ITSELF is Claude Code platform contract — when a
#   matching Write|Edit happens, the hook fires. We can trust the
#   platform on that. What we OWN and need to test is the hook script's
#   behavior on the inputs Claude Code will deliver.
#
#   The full intent → spec → edit → hook chain is exercised incidentally
#   by tests/phase-2/intent_fresh_test.sh, which now (with the hook
#   wired) writes specs through claude -p and the hook fires as a side
#   effect. That test's hook-side-effect output appears in its
#   _intent_output.txt for diagnostic purposes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
VALIDATOR="$PLUGIN_DIR/bin/validate-spec.sh"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"

TMP_PROJECT="$(mktemp -d -t agentic-hook-XXXXXX)"
# Set KEEP_TMP=1 to preserve the tmp project on exit for debugging.
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"

# ---------------------------------------------------------------------------
# Section 1: Static checks on hooks.json
# ---------------------------------------------------------------------------

if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "FAIL: hooks.json not found at $HOOKS_JSON" >&2
  exit 1
fi
echo "PASS hooks.json exists at $HOOKS_JSON"

# Valid JSON
if ! python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null; then
  echo "FAIL: hooks.json is not valid JSON" >&2
  python3 -c "import json; json.load(open('$HOOKS_JSON'))" >&2 || true
  exit 1
fi
echo "PASS hooks.json is valid JSON"

# Structure: PostToolUse with matcher Write|Edit and command referencing validate-spec.sh
STRUCTURE_CHECK="$(python3 - <<PY
import json, sys
h = json.load(open("$HOOKS_JSON"))
post = h.get("hooks", {}).get("PostToolUse", [])
if not post:
    print("FAIL: hooks.json has no PostToolUse entries")
    sys.exit(0)
match_found = False
cmd_ok = False
for entry in post:
    matcher = entry.get("matcher", "")
    if "Write" in matcher and "Edit" in matcher:
        match_found = True
        for h2 in entry.get("hooks", []):
            cmd = h2.get("command", "")
            if "validate-spec.sh" in cmd and "\${CLAUDE_PLUGIN_ROOT}" in cmd:
                cmd_ok = True
if not match_found:
    print("FAIL: no PostToolUse entry with Write|Edit matcher")
elif not cmd_ok:
    print("FAIL: validate-spec.sh command using \${CLAUDE_PLUGIN_ROOT} not found")
else:
    print("OK")
PY
)"

if [[ "$STRUCTURE_CHECK" != "OK" ]]; then
  echo "$STRUCTURE_CHECK" >&2
  exit 1
fi
echo "PASS hooks.json has PostToolUse on Write|Edit referencing \${CLAUDE_PLUGIN_ROOT}/bin/validate-spec.sh"

# ---------------------------------------------------------------------------
# Section 2: Validator hook-mode behavior on a spec with unresolved QUESTION
#
# Simulates the hook input Claude Code passes to a PostToolUse hook: JSON
# on stdin with a tool_input.file_path. Validator must read the file at
# that path, validate it, and emit failure messages to stdout (so Claude
# Code's hook transcript captures them).
# ---------------------------------------------------------------------------

mkdir -p .claude/agentic/intents .claude/agentic/specs

cat > .claude/agentic/intents/2026-05-20-test.md <<'INTENT'
---
id: 2026-05-20-test
created_at: "2026-05-20T15:30:00Z"
---

Test intent
INTENT

SPEC_BAD=.claude/agentic/specs/2026-05-20-test-bad.md
cat > "$SPEC_BAD" <<'SPEC_BAD_EOF'
---
id: 2026-05-20-test-bad
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-test.md
approved: true
created_at: "2026-05-20T15:30:00Z"
---

# Intent
Test.

<!-- QUESTION-1 (architectural-decision) -->
**Q:** Test?
**Your answer:** [REPLACE THIS LINE]

# Diff budget
- Wall clock: 90 minutes
- Diff lines: 800
- Files touched: 25
SPEC_BAD_EOF

# Construct the hook input JSON: simulates Claude Code's PostToolUse payload
SPEC_BAD_ABS="$TMP_PROJECT/$SPEC_BAD"
HOOK_INPUT_BAD="$(python3 -c '
import json, sys
payload = {"tool_input": {"file_path": sys.argv[1]}}
print(json.dumps(payload))
' "$SPEC_BAD_ABS")"

# Invoke the validator in hook mode (stdin = JSON, no CLI arg).
# `set +e` before the call because the validator is EXPECTED to exit 1
# here (approved=true with unresolved QUESTION), and `set -euo pipefail`
# would otherwise kill the script.
hook_out_bad="$TMP_PROJECT/_hook_out_bad.txt"
set +e
echo "$HOOK_INPUT_BAD" | "$VALIDATOR" >"$hook_out_bad" 2>&1
hook_exit_bad=$?
set -e

if [[ $hook_exit_bad -ne 1 ]]; then
  echo "FAIL: validator hook-mode on approved+unresolved-QUESTION expected exit 1, got $hook_exit_bad" >&2
  echo "--- output: ---" >&2
  cat "$hook_out_bad" >&2
  exit 1
fi
echo "PASS validator hook-mode exits 1 on approved=true with unresolved QUESTION"

if ! grep -qE 'spec validation failed' "$hook_out_bad"; then
  echo "FAIL: validator hook-mode did not emit 'spec validation failed' on stdout" >&2
  cat "$hook_out_bad" >&2
  exit 1
fi
echo "PASS validator hook-mode emits 'spec validation failed' on stdout"

if ! grep -qE 'QUESTION-1' "$hook_out_bad"; then
  echo "FAIL: validator hook-mode did not name the unresolved QUESTION-1 in its output" >&2
  cat "$hook_out_bad" >&2
  exit 1
fi
echo "PASS validator hook-mode names QUESTION-1 in failure output"

# ---------------------------------------------------------------------------
# Section 3: Validator hook-mode behavior on a clean approved spec
# ---------------------------------------------------------------------------

SPEC_GOOD=.claude/agentic/specs/2026-05-20-test-good.md
cat > "$SPEC_GOOD" <<'SPEC_GOOD_EOF'
---
id: 2026-05-20-test-good
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-test.md
approved: true
created_at: "2026-05-20T15:30:00Z"
---

# Intent
Test.

# Diff budget
- Wall clock: 90 minutes
- Diff lines: 800
- Files touched: 25
SPEC_GOOD_EOF

SPEC_GOOD_ABS="$TMP_PROJECT/$SPEC_GOOD"
HOOK_INPUT_GOOD="$(python3 -c '
import json, sys
payload = {"tool_input": {"file_path": sys.argv[1]}}
print(json.dumps(payload))
' "$SPEC_GOOD_ABS")"

hook_out_good="$TMP_PROJECT/_hook_out_good.txt"
set +e
echo "$HOOK_INPUT_GOOD" | "$VALIDATOR" >"$hook_out_good" 2>&1
hook_exit_good=$?
set -e

if [[ $hook_exit_good -ne 0 ]]; then
  echo "FAIL: validator hook-mode on clean approved spec expected exit 0, got $hook_exit_good" >&2
  cat "$hook_out_good" >&2
  exit 1
fi
echo "PASS validator hook-mode exits 0 on clean approved spec"

if ! grep -qE 'state: approved' "$hook_out_good"; then
  echo "FAIL: validator hook-mode did not emit 'state: approved' on clean approved spec" >&2
  cat "$hook_out_good" >&2
  exit 1
fi
echo "PASS validator hook-mode emits 'state: approved' on clean approved spec"

if ! grep -qE '_check-approval' "$hook_out_good"; then
  echo "FAIL: validator hook-mode did not mention /agentic-dev:_check-approval next step" >&2
  cat "$hook_out_good" >&2
  exit 1
fi
echo "PASS validator hook-mode emits _check-approval next-step instruction"

# ---------------------------------------------------------------------------
# Section 4: Validator hook-mode silently skips non-spec paths
# ---------------------------------------------------------------------------

NONSPEC=.claude/agentic/intents/some-other-file.md
echo "not a spec" > "$NONSPEC"
NONSPEC_ABS="$TMP_PROJECT/$NONSPEC"
HOOK_INPUT_NONSPEC="$(python3 -c '
import json, sys
payload = {"tool_input": {"file_path": sys.argv[1]}}
print(json.dumps(payload))
' "$NONSPEC_ABS")"

hook_out_nonspec="$TMP_PROJECT/_hook_out_nonspec.txt"
set +e
echo "$HOOK_INPUT_NONSPEC" | "$VALIDATOR" >"$hook_out_nonspec" 2>&1
nonspec_exit=$?
set -e

if [[ $nonspec_exit -ne 0 ]]; then
  echo "FAIL: validator hook-mode on non-spec path expected exit 0, got $nonspec_exit" >&2
  cat "$hook_out_nonspec" >&2
  exit 1
fi
if [[ -s "$hook_out_nonspec" ]]; then
  echo "FAIL: validator hook-mode emitted output on non-spec path (should be silent)" >&2
  cat "$hook_out_nonspec" >&2
  exit 1
fi
echo "PASS validator hook-mode silently skips non-spec paths"

echo "hook_test: OK"
