#!/usr/bin/env bash
# tests/phase-2/hook_test.sh
#
# Verifies the validate-spec.sh hook fires on Write|Edit of a spec file
# under .claude/agentic/specs/*.md and emits the expected messages.
#
# Scope: hook-firing only. Hand-writes the spec file (skipping the drafter)
# to isolate hook behavior from drafter LLM variance. The full
# intent → spec → edit → hook chain is exercised incidentally by
# tests/phase-2/intent_fresh_test.sh.
#
# Reliability notes:
#  - Uses --output-format=stream-json --include-hook-events to surface hook
#    output (claude's default --print only shows the assistant's final text).
#  - The test claude invocations rely on natural-language instructions to
#    trigger the Edit tool. LLM non-determinism is the principal failure
#    mode; the test detects this via verify_edit_used() and fails with a
#    clear diagnostic rather than a generic hook-not-fired message.
#  - The two assertions check hook-event stdout ONLY, never the assistant's
#    final response text (which could mention the trigger strings as prose
#    and produce false positives).
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-hook-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

# Init the project
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

# Hand-write a valid draft spec (skipping the drafter for hook isolation)
mkdir -p .claude/agentic/intents .claude/agentic/specs
cat > .claude/agentic/intents/2026-05-20-test.md <<'INTENT'
---
id: 2026-05-20-test
created_at: "2026-05-20T15:30:00Z"
---

Test intent
INTENT

SPEC=.claude/agentic/specs/2026-05-20-test.md
cat > "$SPEC" <<'SPEC_DRAFT'
---
id: 2026-05-20-test
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-test.md
approved: false
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
SPEC_DRAFT

# Extract hook-event content from a Claude Code stream-json output file.
# Returns: prints "HOOK_EVENT_COUNT=<n>" on first line, then the
# concatenated hook stdout strings (one per event) on subsequent lines.
# Exits non-zero if the file is empty or contains no JSON events at all.
extract_hook_output() {
  local stream_file="$1"
  if [[ ! -s "$stream_file" ]]; then
    echo "EXTRACT_ERROR: stream file is empty: $stream_file" >&2
    return 1
  fi
  python3 - "$stream_file" <<'PY'
import json, sys
path = sys.argv[1]
hook_events = []
any_json = False
with open(path, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        any_json = True
        t = d.get("type", "")
        if t == "hook_response" or t == "hook_event":
            # Different Claude Code versions use slightly different event
            # names; capture both. Hook stdout typically lives at
            # d["hook_response"]["output"] OR d["output"] OR d["stdout"].
            out = ""
            if isinstance(d.get("hook_response"), dict):
                out = d["hook_response"].get("output", "") or d["hook_response"].get("stdout", "")
            if not out:
                out = d.get("output", "") or d.get("stdout", "")
            if out:
                hook_events.append(out)
if not any_json:
    print("EXTRACT_ERROR: no JSON events found in stream", file=sys.stderr)
    sys.exit(2)
print(f"HOOK_EVENT_COUNT={len(hook_events)}")
for ev in hook_events:
    print(ev)
PY
}

# Verify the Edit (or Write) tool was invoked in the stream.
verify_edit_used() {
  local stream_file="$1"
  local found
  found=$(python3 - "$stream_file" <<'PY'
import json, sys
path = sys.argv[1]
seen = []
with open(path, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        # tool_use events: { type: "tool_use", ... } or {assistant: ...} with content blocks
        # Capture any string field anywhere that looks like a tool name from Write|Edit family.
        s = json.dumps(d)
        for name in ("Edit", "Write", "NotebookEdit"):
            if f'"name":"{name}"' in s or f'"tool_name":"{name}"' in s:
                seen.append(name)
                break
print(",".join(sorted(set(seen))))
PY
  )
  if [[ -z "$found" ]]; then
    return 1
  fi
  echo "$found"
}

# Ask claude -p to Edit the spec file. This should fire PostToolUse on Edit.
# Use stream-json output with hook events enabled so we can inspect hook stdout.
stream_out1="$TMP_PROJECT/_stream1.json"

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --output-format=stream-json \
  --include-hook-events \
  --verbose \
  -p "Use the Edit tool to change the approved field in $SPEC from false to true. Then exit." \
  >"$stream_out1" 2>&1 || true

edit_tools_1="$(verify_edit_used "$stream_out1")" || {
  echo "FAIL: claude did not invoke Edit/Write tool — no PostToolUse hook could have fired" >&2
  echo "  This is LLM non-determinism, not a hook bug. Retry the test; if it persists," >&2
  echo "  the prompt may need to be more explicit." >&2
  echo "--- stream content head: ---" >&2
  head -30 "$stream_out1" >&2 || true
  exit 1
}
echo "PASS claude invoked tools: $edit_tools_1"

hook_extract_1="$(extract_hook_output "$stream_out1")" || {
  echo "FAIL: hook_event extraction failed (stream-json flag may be broken)" >&2
  echo "--- stream content head: ---" >&2
  head -20 "$stream_out1" >&2 || true
  exit 1
}
hook_count_1=$(printf '%s\n' "$hook_extract_1" | head -1 | sed 's/^HOOK_EVENT_COUNT=//')
hook_body_1=$(printf '%s\n' "$hook_extract_1" | tail -n +2)

if [[ "$hook_count_1" -lt 1 ]]; then
  echo "FAIL: no hook_response events found in stream (hook did not fire)" >&2
  echo "--- stream content head: ---" >&2
  head -20 "$stream_out1" >&2 || true
  exit 1
fi

# After the edit, the hook should have fired and emitted a validation failure
# because the spec has approved=true but a QUESTION-1 block remains.
if ! grep -qE 'spec validation failed' <<< "$hook_body_1"; then
  echo "FAIL: hook fired but did not produce 'spec validation failed' message" >&2
  echo "--- hook body: ---" >&2
  echo "$hook_body_1" >&2
  exit 1
fi
echo "PASS hook fired validation failure on approved=true with unresolved QUESTION ($hook_count_1 hook events)"

# Now resolve the question: remove the QUESTION-N comment line (which is what
# the validator checks) and replace the placeholder with an actual answer.
# The validator considers a QUESTION "unresolved" if the <!-- QUESTION-N -->
# HTML comment is still present in the file; filling in the answer alone is
# not sufficient — the comment block must be removed.
sed -i.bak '/^<!-- QUESTION-[0-9]/d' "$SPEC"
sed -i.bak 's/\[REPLACE THIS LINE\]/A/' "$SPEC"
rm -f "$SPEC.bak"

stream_out2="$TMP_PROJECT/_stream2.json"

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --output-format=stream-json \
  --include-hook-events \
  --verbose \
  -p "Use the Edit tool to make any trivial whitespace-only edit to $SPEC (such as adding a trailing newline). Then exit." \
  >"$stream_out2" 2>&1 || true

edit_tools_2="$(verify_edit_used "$stream_out2")" || {
  echo "FAIL: claude did not invoke Edit/Write tool — no PostToolUse hook could have fired" >&2
  echo "  This is LLM non-determinism, not a hook bug. Retry the test; if it persists," >&2
  echo "  the prompt may need to be more explicit." >&2
  echo "--- stream content head: ---" >&2
  head -30 "$stream_out2" >&2 || true
  exit 1
}
echo "PASS claude invoked tools: $edit_tools_2"

hook_extract_2="$(extract_hook_output "$stream_out2")" || {
  echo "FAIL: hook_event extraction failed (stream-json flag may be broken)" >&2
  echo "--- stream content head: ---" >&2
  head -20 "$stream_out2" >&2 || true
  exit 1
}
hook_count_2=$(printf '%s\n' "$hook_extract_2" | head -1 | sed 's/^HOOK_EVENT_COUNT=//')
hook_body_2=$(printf '%s\n' "$hook_extract_2" | tail -n +2)

if [[ "$hook_count_2" -lt 1 ]]; then
  echo "FAIL: no hook_response events found in stream (hook did not fire)" >&2
  echo "--- stream content head: ---" >&2
  head -20 "$stream_out2" >&2 || true
  exit 1
fi

if ! grep -qE 'state: approved' <<< "$hook_body_2"; then
  echo "FAIL: hook fired but did not emit 'state: approved' on clean approved spec" >&2
  echo "--- hook body: ---" >&2
  echo "$hook_body_2" >&2
  exit 1
fi
if ! grep -qE '_check-approval' <<< "$hook_body_2"; then
  echo "FAIL: hook fired but did not mention /agentic-dev:_check-approval next step" >&2
  echo "--- hook body: ---" >&2
  echo "$hook_body_2" >&2
  exit 1
fi
echo "PASS hook emits _check-approval next-step on clean approved spec ($hook_count_2 hook events)"

echo "hook_test: OK"
