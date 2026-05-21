#!/usr/bin/env bash
# cleanup-completed-goal.sh <goal-id>
#
# Post-success worktree removal for a completed goal.
# Verifies the goal has status=completed in queue.yaml; refuses otherwise.
# Delegates actual worktree removal to bin/worktree-cleanup.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: cleanup-completed-goal.sh <goal-id>" >&2
  exit 1
fi

QUEUE_FILE=".claude/agentic/queue.yaml"

if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "ERROR: queue file not found: $QUEUE_FILE" >&2
  exit 1
fi

# ── Look up the goal and verify status=completed ──────────────────────────────
export GOAL_ID QUEUE_FILE

LOOKUP="$(python3 - <<'PY'
import os, sys, yaml

goal_id    = os.environ["GOAL_ID"]
queue_file = os.environ["QUEUE_FILE"]

with open(queue_file) as fh:
    queue = yaml.safe_load(fh)

goals = queue.get("goals", [])
goal = None
for g in goals:
    if g.get("id") == goal_id:
        goal = g
        break

if goal is None:
    print(f"NOT_FOUND:{goal_id}")
    sys.exit(0)

status = goal.get("status", "")
if status != "completed":
    print(f"NOT_COMPLETED:{status}")
    sys.exit(0)

worktree = goal.get("worktree_path") or ""
print(f"OK:{worktree}")
PY
)"

case "$LOOKUP" in
  NOT_FOUND:*)
    echo "ERROR: goal not found in queue: ${GOAL_ID}" >&2
    exit 1
    ;;
  NOT_COMPLETED:*)
    current_status="${LOOKUP#NOT_COMPLETED:}"
    echo "ERROR: goal '${GOAL_ID}' must be completed before cleanup, but status is '${current_status}' (expected completed)" >&2
    exit 1
    ;;
  OK:*)
    WORKTREE_PATH="${LOOKUP#OK:}"
    ;;
  *)
    echo "ERROR: unexpected lookup result: $LOOKUP" >&2
    exit 1
    ;;
esac

# ── Delegate to worktree-cleanup.sh ──────────────────────────────────────────
# worktree-cleanup.sh lives alongside this script
WORKTREE_CLEANUP="${AGENTIC_BIN_DIR:-$SCRIPT_DIR}/worktree-cleanup.sh"

if [[ ! -x "$WORKTREE_CLEANUP" ]]; then
  # Try PATH as fallback
  if command -v worktree-cleanup.sh &>/dev/null; then
    WORKTREE_CLEANUP="worktree-cleanup.sh"
  else
    echo "ERROR: worktree-cleanup.sh not found" >&2
    exit 1
  fi
fi

"$WORKTREE_CLEANUP" "$GOAL_ID"

echo "cleanup-completed-goal: goal '${GOAL_ID}' cleaned up successfully"
if [[ -n "$WORKTREE_PATH" ]]; then
  echo "  worktree_path: $WORKTREE_PATH"
fi
