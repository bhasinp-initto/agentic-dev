#!/usr/bin/env bash
# Remove an agentic-dev goal's worktree.
# Usage: worktree-cleanup.sh <goal-id>
set -euo pipefail

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: worktree-cleanup.sh <goal-id>" >&2
  exit 1
fi

WORKTREE_PATH=".worktrees/goal-${GOAL_ID}"
if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree not found at $WORKTREE_PATH" >&2
  exit 1
fi

# Remove via git worktree (safer than rm -rf — handles git's bookkeeping)
git worktree remove "$WORKTREE_PATH" --force
git worktree prune

echo "removed worktree: $WORKTREE_PATH"
