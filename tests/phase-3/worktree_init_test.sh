#!/usr/bin/env bash
# Tests for bin/worktree-init.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKTREE_INIT="$REPO_ROOT/agentic-dev/bin/worktree-init.sh"

TMP_PROJECT="$(mktemp -d -t agentic-worktree-init-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Create required project state
mkdir -p .claude/agentic/{intents,specs}
echo '{"schema_version":"0.1","circuit_breaker":{"state":"idle","halted_reason":null,"halted_at":null,"halted_goal_id":null},"current_goal":null,"last_updated":"2026-05-21T10:00:00Z"}' > .claude/agentic/state.json

# Create a spec file
SPEC=.claude/agentic/specs/2026-05-21-test-goal.md
cat > "$SPEC" <<'SPEC_EOF'
---
id: 2026-05-21-test-goal
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-21-test-goal.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test goal.

# Files in scope
- src/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC_EOF

echo "stub" > .claude/agentic/intents/2026-05-21-test-goal.md

# Create a minimal config.yaml (worktree-init reads project commands)
cat > .claude/agentic/config.yaml <<'CFG_EOF'
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
telegram: null
push_policy: hold
CFG_EOF

# Run worktree-init
WORKTREE_PATH="$("$WORKTREE_INIT" 2026-05-21-test-goal)"
echo "Created worktree at: $WORKTREE_PATH"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "FAIL: worktree directory not created" >&2
  exit 1
fi
echo "PASS worktree directory created at expected path"

if [[ "$WORKTREE_PATH" != *".worktrees/goal-2026-05-21-test-goal"* ]]; then
  echo "FAIL: worktree path doesn't match .worktrees/goal-<id> pattern: $WORKTREE_PATH" >&2
  exit 1
fi
echo "PASS worktree path follows .worktrees/goal-<id>/ pattern"

# Kickoff file should exist
KICKOFF="$WORKTREE_PATH/.agentic-kickoff.json"
if [[ ! -f "$KICKOFF" ]]; then
  echo "FAIL: kickoff file not created at $KICKOFF" >&2
  exit 1
fi
echo "PASS kickoff file created"

# Kickoff should have required fields
python3 <<PY
import json
k = json.load(open("$KICKOFF"))
required = ["goal_id", "spec_path", "baseline_ref", "budget", "sensitive_paths", "project_commands"]
missing = [r for r in required if r not in k]
if missing:
    print(f"FAIL: kickoff missing fields: {missing}")
    import sys; sys.exit(1)
print("PASS kickoff has all required fields")

# Specific value checks
assert k["goal_id"] == "2026-05-21-test-goal", f"goal_id mismatch: {k['goal_id']}"
assert k["spec_path"].endswith(".claude/agentic/specs/2026-05-21-test-goal.md"), f"spec_path: {k['spec_path']}"
assert k["budget"]["wall_clock_minutes_per_goal"] == 90, f"budget: {k['budget']}"
assert k["project_commands"]["test"] == "npm test", f"commands: {k['project_commands']}"
print("PASS kickoff field values are correct")
PY

# Refuses to create duplicate worktree
if "$WORKTREE_INIT" 2026-05-21-test-goal 2>/dev/null; then
  echo "FAIL: worktree-init did not refuse on duplicate goal-id" >&2
  exit 1
fi
echo "PASS worktree-init refuses on duplicate goal-id"

echo "worktree_init_test: OK"
