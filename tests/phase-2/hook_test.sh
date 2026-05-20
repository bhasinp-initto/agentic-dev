#!/usr/bin/env bash
# Verify the validate-spec.sh hook fires on Write|Edit of a spec file and
# emits the expected messages.
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

# Helper: extract hook output text from stream-json.
# Claude Code delivers PostToolUse hook stdout via hook_response.output in the
# stream-json event log. Use --output-format=stream-json --include-hook-events
# --verbose to surface these events, then extract the output strings.
extract_hook_output() {
  python3 - "$1" <<'PY'
import json, sys
result = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        # Collect hook_response outputs and the final result text
        if d.get("type") == "system" and d.get("subtype") == "hook_response":
            out = d.get("output", "")
            if out:
                result.append(out)
        # Also include the final assistant result text for completeness
        if d.get("type") == "result":
            result.append(d.get("result", ""))
print("\n".join(result))
PY
}

# Ask claude -p to Edit the spec file. This should fire PostToolUse on Edit.
# Use stream-json output with hook events enabled so we can inspect hook stdout.
stream_out="$TMP_PROJECT/_stream1.json"
hook_out="$TMP_PROJECT/_hook_output.txt"

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --output-format=stream-json \
  --include-hook-events \
  --verbose \
  -p "Use the Edit tool to change the approved field in $SPEC from false to true. Then exit." \
  >"$stream_out" 2>&1 || true

extract_hook_output "$stream_out" > "$hook_out"

# After the edit, the hook should have fired and emitted a validation failure
# because the spec has approved=true but a QUESTION-1 block remains.
if ! grep -qE 'spec validation failed' "$hook_out"; then
  echo "FAIL: hook did not produce 'spec validation failed' message" >&2
  echo "--- extracted hook output was: ---" >&2
  cat "$hook_out" >&2
  echo "--- raw stream (non-json lines): ---" >&2
  grep -v '^{' "$stream_out" | head -20 >&2 || true
  exit 1
fi
echo "PASS hook fired validation failure on approved=true with unresolved QUESTION"

# Now resolve the question: remove the QUESTION-N comment line (which is what
# the validator checks) and replace the placeholder with an actual answer.
# The validator considers a QUESTION "unresolved" if the <!-- QUESTION-N -->
# HTML comment is still present in the file; filling in the answer alone is
# not sufficient — the comment block must be removed.
sed -i.bak '/^<!-- QUESTION-[0-9]/d' "$SPEC"
sed -i.bak 's/\[REPLACE THIS LINE\]/A/' "$SPEC"
rm -f "$SPEC.bak"

stream_out2="$TMP_PROJECT/_stream2.json"
hook_out2="$TMP_PROJECT/_hook_output2.txt"

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --output-format=stream-json \
  --include-hook-events \
  --verbose \
  -p "Use the Edit tool to make any trivial whitespace-only edit to $SPEC (such as adding a trailing newline). Then exit." \
  >"$stream_out2" 2>&1 || true

extract_hook_output "$stream_out2" > "$hook_out2"

if ! grep -qE 'state: approved' "$hook_out2"; then
  echo "FAIL: hook did not emit 'state: approved' on clean approved spec" >&2
  cat "$hook_out2" >&2
  exit 1
fi
if ! grep -qE '_check-approval' "$hook_out2"; then
  echo "FAIL: hook did not mention /agentic-dev:_check-approval next step" >&2
  cat "$hook_out2" >&2
  exit 1
fi
echo "PASS hook emits _check-approval next-step on clean approved spec"

echo "hook_test: OK"
