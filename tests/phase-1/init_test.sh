#!/usr/bin/env bash
# End-to-end test of /agentic-dev:init in a throwaway directory.
# Drives Claude Code via --plugin-dir + headless -p with pre-canned config input.
set -euo pipefail

# Source API key for headless testing (Max subscription blocked from -p until June 15 2026)
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
FIXTURE_INPUT="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-init-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Invoke the init skill with a pre-canned config path as $ARGUMENTS.
# --dangerously-skip-permissions: required because .claude/ is a protected path in headless mode.
# This test runs in a throwaway temp directory created above — no real project is at risk.
# --add-dir grants read access to the fixture directory (outside CWD).
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$FIXTURE_INPUT")" \
  -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null 2>&1 || true

# Assertions
ok=1
require() {
  if [[ ! -e "$1" ]]; then
    echo "FAIL missing: $1" >&2
    ok=0
  else
    echo "PASS exists: $1"
  fi
}

require .claude/agentic/state.json
require .claude/agentic/queue.yaml
require .claude/agentic/config.yaml
require .claude/agentic/checklist.yaml
require .claude/agentic/memory.yaml
require .claude/agentic/decisions.log
require .claude/agentic/intents
require .claude/agentic/specs
require .claude/agentic/manifests
require .claude/agentic/diffs
require .claude/agentic/artifacts
require .claude/agentic/escalations
require .claude/agentic/prompts

# Validate the written config against the schema
python3 - <<PY
import sys, json, yaml
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/config.schema.json").read_text())
data = yaml.safe_load(Path(".claude/agentic/config.yaml").read_text())
jsonschema.validate(instance=data, schema=schema, format_checker=jsonschema.FormatChecker())
print("PASS config.yaml validates against config.schema.json")
PY

# Validate state.json
python3 - <<PY
import sys, json
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/state.schema.json").read_text())
data = json.loads(Path(".claude/agentic/state.json").read_text())
jsonschema.validate(instance=data, schema=schema, format_checker=jsonschema.FormatChecker())
print("PASS state.json validates against state.schema.json")
PY

# Validate queue.yaml
python3 - <<PY
import sys, json, yaml
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/queue.schema.json").read_text())
data = yaml.safe_load(Path(".claude/agentic/queue.yaml").read_text())
jsonschema.validate(instance=data, schema=schema, format_checker=jsonschema.FormatChecker())
print("PASS queue.yaml validates against queue.schema.json")
PY

[[ $ok -eq 1 ]] || exit 1

# --- Idempotence check ---
# Re-running init must not overwrite or duplicate files.
state_mtime_before=$(stat -f "%m" .claude/agentic/state.json 2>/dev/null || stat -c "%Y" .claude/agentic/state.json)
sleep 1
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$FIXTURE_INPUT")" \
  -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null 2>&1 || true
state_mtime_after=$(stat -f "%m" .claude/agentic/state.json 2>/dev/null || stat -c "%Y" .claude/agentic/state.json)

if [[ "$state_mtime_before" != "$state_mtime_after" ]]; then
  echo "FAIL idempotence: state.json was modified on re-run" >&2
  exit 1
fi
echo "PASS idempotence: state.json untouched on re-run"

echo "init_test: OK"
