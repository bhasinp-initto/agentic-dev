#!/usr/bin/env bash
# End-to-end test of /agentic-dev:status against known state.
# Drives Claude Code via --plugin-dir + headless -p.
set -euo pipefail

# Source API key for headless testing (Max subscription blocked from -p until June 15 2026).
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"

TMP_PROJECT="$(mktemp -d -t agentic-status-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"

# Set up known state directly (not via init — we want isolated testing of status).
mkdir -p .claude/agentic/intents .claude/agentic/specs
cat > .claude/agentic/state.json <<'JSON'
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "running",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": "2026-05-20-example-goal",
  "last_updated": "2026-05-20T15:30:00Z"
}
JSON

cat > .claude/agentic/queue.yaml <<'YAML'
schema_version: "0.1"
goals:
  - id: 2026-05-20-example-goal
    spec_path: .claude/agentic/specs/2026-05-20-example-goal.md
    intent_path: null
    status: running
    added_at: "2026-05-20T15:25:00Z"
  - id: 2026-05-20-second-goal
    spec_path: .claude/agentic/specs/2026-05-20-second-goal.md
    intent_path: null
    status: approved
    added_at: "2026-05-20T15:26:00Z"
  - id: 2026-05-20-third-intent
    spec_path: null
    intent_path: .claude/agentic/intents/2026-05-20-third-intent.md
    status: intent_only
    added_at: "2026-05-20T15:27:00Z"
YAML

cat > .claude/agentic/config.yaml <<'YAML'
schema_version: "0.1"
project:
  name: example-host-project
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
telegram: null
push_policy: hold
YAML

# Note: --dangerously-skip-permissions is required because Claude in headless mode
# blocks reads of .claude/ paths without it. Safe in the tmp project.
# stdout AND stderr are captured (2>&1) into $output so grep assertions see the
# full output and the on-failure dump (status_output.txt) shows error messages.
output=$(claude --plugin-dir "$PLUGIN_DIR" --dangerously-skip-permissions -p "/agentic-dev:status" 2>&1 || true)
echo "$output" > status_output.txt

ok=1
must_contain() {
  if ! grep -qE "$1" status_output.txt; then
    echo "FAIL missing-pattern: $1" >&2
    ok=0
  else
    echo "PASS contains: $1"
  fi
}

must_contain "circuit.*breaker.*running"
must_contain "current.*goal.*2026-05-20-example-goal"
must_contain "approved.*1"
must_contain "intent_only.*1"
must_contain "running.*1"
must_contain "example-host-project"

if [[ $ok -ne 1 ]]; then
  echo "--- Captured output was: ---" >&2
  cat status_output.txt >&2
  exit 1
fi

# --- Not-initialized case ---
TMP_EMPTY="$(mktemp -d -t agentic-status-empty-XXXXXX)"
cd "$TMP_EMPTY"
empty_output=$(claude --plugin-dir "$PLUGIN_DIR" --dangerously-skip-permissions -p "/agentic-dev:status" 2>&1 || true)
if echo "$empty_output" | grep -q "not initialized"; then
  echo "PASS not-initialized message present"
else
  echo "FAIL not-initialized: expected 'not initialized' message; got:" >&2
  echo "$empty_output" >&2
  rm -rf "$TMP_EMPTY"
  exit 1
fi
rm -rf "$TMP_EMPTY"

echo "status_test: OK"
