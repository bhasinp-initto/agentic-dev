#!/usr/bin/env bash
# End-to-end test of /agentic-dev:init in a throwaway directory.
# Drives Claude Code via --plugin-dir + headless -p with pre-canned config input.
set -euo pipefail

# Source API key for headless testing (Max subscription blocked from -p until June 15 2026)
# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
FIXTURE_INPUT="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-init-XXXXXX)"
# Set KEEP_TMP=1 to preserve the tmp project on exit for debugging.
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Note: do NOT redirect stderr — we want to see claude's error output if anything
# goes wrong (manifest parse error, missing key, etc.). The || true is intentional
# because `claude -p` may exit non-zero for legitimate reasons (timeout, partial
# completion); subsequent require() assertions detect actual failures.
# Capture init output to a file (like smoke_test.sh) so failure diagnostics include
# Claude's stdout/stderr instead of swallowing it.
init_out="$TMP_PROJECT/_init_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$FIXTURE_INPUT")" \
  -p "/agentic-dev:init $FIXTURE_INPUT" >"$init_out" 2>&1 || true

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

require .claude/agentic/intents/.gitkeep
require .claude/agentic/specs/.gitkeep
require .claude/agentic/manifests/.gitkeep
require .claude/agentic/diffs/.gitkeep
require .claude/agentic/artifacts/.gitkeep
require .claude/agentic/escalations/.gitkeep
require .claude/agentic/prompts/.gitkeep

if [[ $ok -ne 1 ]]; then
  echo "--- Init claude output was: ---" >&2
  cat "$init_out" >&2
  exit 1
fi

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

# --- Idempotence check ---
# Re-running init must not overwrite or duplicate the load-bearing files.
mtime() {
  stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1"
}

state_before=$(mtime .claude/agentic/state.json)
config_before=$(mtime .claude/agentic/config.yaml)
queue_before=$(mtime .claude/agentic/queue.yaml)
sleep 1

# Re-run claude with the same flags as the first invocation (see header comments).
claude \
  --plugin-dir "$PLUGIN_DIR" \
  --add-dir "$(dirname "$FIXTURE_INPUT")" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null || true

state_after=$(mtime .claude/agentic/state.json)
config_after=$(mtime .claude/agentic/config.yaml)
queue_after=$(mtime .claude/agentic/queue.yaml)

idempotent_ok=1
[[ "$state_before"  == "$state_after"  ]] || { echo "FAIL idempotence: state.json was modified on re-run" >&2; idempotent_ok=0; }
[[ "$config_before" == "$config_after" ]] || { echo "FAIL idempotence: config.yaml was modified on re-run" >&2; idempotent_ok=0; }
[[ "$queue_before"  == "$queue_after"  ]] || { echo "FAIL idempotence: queue.yaml was modified on re-run" >&2; idempotent_ok=0; }

[[ $idempotent_ok -eq 1 ]] || exit 1
echo "PASS idempotence: state.json, config.yaml, queue.yaml all untouched on re-run"

echo "init_test: OK"
