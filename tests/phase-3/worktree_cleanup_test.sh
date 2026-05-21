#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKTREE_INIT="$REPO_ROOT/agentic-dev/bin/worktree-init.sh"
WORKTREE_CLEANUP="$REPO_ROOT/agentic-dev/bin/worktree-cleanup.sh"

TMP_PROJECT="$(mktemp -d -t agentic-cleanup-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo x > x.txt
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Set up minimal project state
mkdir -p .claude/agentic/{intents,specs}
echo '{"schema_version":"0.1","circuit_breaker":{"state":"idle","halted_reason":null,"halted_at":null,"halted_goal_id":null},"current_goal":null,"last_updated":"2026-05-21T10:00:00Z"}' > .claude/agentic/state.json

SPEC=.claude/agentic/specs/2026-05-21-cleanup-goal.md
cat > "$SPEC" <<'SPEC_EOF'
---
id: 2026-05-21-cleanup-goal
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-21-cleanup-goal.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test.

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC_EOF
echo stub > .claude/agentic/intents/2026-05-21-cleanup-goal.md

cat > .claude/agentic/config.yaml <<'CFG'
schema_version: "0.1"
project:
  name: t
  primary_language: javascript
commands:
  test: "npm test"
  lint: "npm run lint"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 100
  files_touched_per_goal: 5
sensitive_paths: ["auth/**"]
telegram: null
push_policy: hold
CFG

# Create a worktree first
"$WORKTREE_INIT" 2026-05-21-cleanup-goal > /dev/null

if [[ ! -d .worktrees/goal-2026-05-21-cleanup-goal ]]; then
  echo "FAIL setup: worktree not created" >&2
  exit 1
fi
echo "PASS setup: worktree exists"

# Run cleanup
"$WORKTREE_CLEANUP" 2026-05-21-cleanup-goal

if [[ -d .worktrees/goal-2026-05-21-cleanup-goal ]]; then
  echo "FAIL: worktree still exists after cleanup" >&2
  exit 1
fi
echo "PASS worktree removed after cleanup"

# Refuses unknown goal-id
if "$WORKTREE_CLEANUP" no-such-goal 2>/dev/null; then
  echo "FAIL: cleanup did not error on unknown goal-id" >&2
  exit 1
fi
echo "PASS cleanup errors on unknown goal-id"

echo "worktree_cleanup_test: OK"
