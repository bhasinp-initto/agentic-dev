#!/usr/bin/env bash
# circuit-breaker.sh <new-state> [halted_reason=...] [halted_goal_id=...]
#
# Atomically updates circuit_breaker.state in .claude/agentic/state.json.
# Also updates last_updated to the current UTC ISO 8601 timestamp.
#
# new-state enum: idle | running | halted | completed
#
# When new-state=halted, halted_reason and halted_goal_id are REQUIRED.
# halted_at is populated automatically with the current UTC time.
#
# Validates result against state.schema.json BEFORE writing; on failure
# → error to stderr + exit 1 + original file untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NEW_STATE="${1:-}"
if [[ -z "$NEW_STATE" ]]; then
  echo "Usage: circuit-breaker.sh <new-state> [halted_reason=...] [halted_goal_id=...]" >&2
  exit 1
fi

shift
EXTRA_ARGS=("$@")

STATE_FILE=".claude/agentic/state.json"
SCHEMA_FILE="$SCRIPT_DIR/../schemas/state.schema.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

# Parse extra key=value args
EXTRA_JSON="$(python3 -c "
import json, sys
args = sys.argv[1:]
d = {}
for arg in args:
    if '=' in arg:
        k, v = arg.split('=', 1)
        d[k] = v
    else:
        print(f'ERROR: invalid key=value arg: {arg!r}', file=sys.stderr)
        sys.exit(1)
print(json.dumps(d))
" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")" || { echo "ERROR parsing extra args" >&2; exit 1; }

export NEW_STATE EXTRA_JSON STATE_FILE SCHEMA_FILE

python3 - <<'PY'
import os, sys, json, jsonschema
from datetime import datetime, timezone

new_state   = os.environ["NEW_STATE"]
extra_json  = os.environ["EXTRA_JSON"]
state_file  = os.environ["STATE_FILE"]
schema_file = os.environ["SCHEMA_FILE"]

# ── Validate new_state enum early ─────────────────────────────────────────────
VALID_STATES = {"idle", "running", "halted", "completed"}
if new_state not in VALID_STATES:
    print(f"ERROR: invalid state {new_state!r}. "
          f"Must be one of: {', '.join(sorted(VALID_STATES))}", file=sys.stderr)
    sys.exit(1)

extra = json.loads(extra_json)

# ── When halted: require halted_reason and halted_goal_id ────────────────────
if new_state == "halted":
    missing = [k for k in ("halted_reason", "halted_goal_id") if k not in extra]
    if missing:
        print(f"ERROR: new-state=halted requires: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

# ── Load state.json ───────────────────────────────────────────────────────────
with open(state_file) as fh:
    state = json.load(fh)

# ── Apply changes ─────────────────────────────────────────────────────────────
now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

state["circuit_breaker"]["state"] = new_state
state["last_updated"] = now_iso

if new_state == "halted":
    state["circuit_breaker"]["halted_reason"]  = extra["halted_reason"]
    state["circuit_breaker"]["halted_goal_id"] = extra["halted_goal_id"]
    state["circuit_breaker"]["halted_at"]      = now_iso
else:
    # Clear halt fields when transitioning away from halted
    state["circuit_breaker"]["halted_reason"]  = None
    state["circuit_breaker"]["halted_at"]      = None
    state["circuit_breaker"]["halted_goal_id"] = None

# ── Load schema ───────────────────────────────────────────────────────────────
with open(schema_file) as fh:
    schema = json.load(fh)

# ── Validate BEFORE writing ───────────────────────────────────────────────────
try:
    jsonschema.validate(state, schema)
except jsonschema.ValidationError as exc:
    print(f"ERROR: schema validation failed: {exc.message}", file=sys.stderr)
    sys.exit(2)

# ── Atomic write: .tmp → mv ───────────────────────────────────────────────────
tmp_file = state_file + ".tmp"
try:
    with open(tmp_file, "w") as fh:
        json.dump(state, fh, indent=2)
        fh.write("\n")
    os.replace(tmp_file, state_file)
except Exception as exc:
    try:
        os.remove(tmp_file)
    except FileNotFoundError:
        pass
    print(f"ERROR: write failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(f"circuit-breaker: state → {new_state}")
sys.exit(0)
PY

exit $?
