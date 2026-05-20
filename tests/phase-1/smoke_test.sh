#!/usr/bin/env bash
# Full init → status workflow on a single throwaway project.
set -euo pipefail

# Source API key for headless testing (Max subscription blocked from -p until June 15 2026).
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
FIXTURE_INPUT="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-smoke-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Step 1: init
# Same flags as init_test.sh (Task 3): --add-dir to allow reading fixture from
# outside CWD; --dangerously-skip-permissions to allow writes to .claude/ paths.
claude \
  --plugin-dir "$PLUGIN_DIR" \
  --add-dir "$(dirname "$FIXTURE_INPUT")" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null || true

if [[ ! -f .claude/agentic/state.json ]]; then
  echo "FAIL smoke: init did not produce state.json" >&2
  exit 1
fi

# Step 2: status
# --dangerously-skip-permissions needed for the read of .claude/ paths.
output=$(claude \
  --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:status" 2>&1 || true)

# Init creates an idle, empty queue. Status must reflect that.
if ! echo "$output" | grep -qE "circuit.*breaker.*idle"; then
  echo "FAIL smoke: status missing 'circuit breaker: idle'. Got:" >&2
  echo "$output" >&2
  exit 1
fi
if ! echo "$output" | grep -qE "queue is empty"; then
  echo "FAIL smoke: status missing 'queue is empty'. Got:" >&2
  echo "$output" >&2
  exit 1
fi
if ! echo "$output" | grep -qE "example-host-project"; then
  echo "FAIL smoke: status missing project name. Got:" >&2
  echo "$output" >&2
  exit 1
fi

echo "smoke_test: OK"
