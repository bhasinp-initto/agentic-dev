#!/usr/bin/env bash
# queue-set-status.sh <goal-id> <new-status> [field1=value1 ...]
#
# Atomically updates a goal's status (and optional extra fields) in
# .claude/agentic/queue.yaml. Validates the result against queue.schema.json
# BEFORE writing; on failure → error + exit 1 + original file untouched.
#
# Supported new-status values (queue.schema.json v0.2):
#   intent_only | drafted | approved | running | completed | halted | abandoned
#
# Extra fields (key=value pairs): any nullable field on a goal entry, e.g.
#   started_at=<ISO8601>  baseline_ref=<sha>  head_ref=<sha>
#   manifest_path=<path>  worktree_path=<path>  completed_at=<ISO8601>
#   halted_at=<ISO8601>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GOAL_ID="${1:-}"
NEW_STATUS="${2:-}"

if [[ -z "$GOAL_ID" || -z "$NEW_STATUS" ]]; then
  echo "Usage: queue-set-status.sh <goal-id> <new-status> [field=value ...]" >&2
  exit 1
fi

# Collect extra key=value pairs from remaining args
shift 2
EXTRA_ARGS=("$@")

QUEUE_FILE=".claude/agentic/queue.yaml"
SCHEMA_FILE="$SCRIPT_DIR/../schemas/queue.schema.json"

if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "ERROR: queue file not found: $QUEUE_FILE" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

# Encode extra args as JSON string for passing to Python
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

export GOAL_ID NEW_STATUS EXTRA_JSON QUEUE_FILE SCHEMA_FILE

python3 - <<'PY'
import os, sys, yaml, json, jsonschema

goal_id     = os.environ["GOAL_ID"]
new_status  = os.environ["NEW_STATUS"]
extra_json  = os.environ["EXTRA_JSON"]
queue_file  = os.environ["QUEUE_FILE"]
schema_file = os.environ["SCHEMA_FILE"]

# ── Validate new_status against enum early (cheap check before I/O) ──────────
VALID_STATUSES = {"intent_only", "drafted", "approved", "running",
                  "completed", "halted", "abandoned"}
if new_status not in VALID_STATUSES:
    print(f"ERROR: invalid status {new_status!r}. "
          f"Must be one of: {', '.join(sorted(VALID_STATUSES))}", file=sys.stderr)
    sys.exit(1)

# ── Load extra key=value fields ───────────────────────────────────────────────
extra = json.loads(extra_json)

# ── Load queue.yaml ───────────────────────────────────────────────────────────
with open(queue_file) as fh:
    queue = yaml.safe_load(fh)

# ── Find goal ─────────────────────────────────────────────────────────────────
goals = queue.get("goals", [])
goal_index = None
for i, g in enumerate(goals):
    if g.get("id") == goal_id:
        goal_index = i
        break

if goal_index is None:
    print(f"ERROR: goal id {goal_id!r} not found in {queue_file}", file=sys.stderr)
    sys.exit(1)

# ── Apply changes ─────────────────────────────────────────────────────────────
queue["goals"][goal_index]["status"] = new_status
for k, v in extra.items():
    queue["goals"][goal_index][k] = v

# ── Load schema ───────────────────────────────────────────────────────────────
with open(schema_file) as fh:
    schema = json.load(fh)

# ── Validate BEFORE writing ───────────────────────────────────────────────────
try:
    jsonschema.validate(queue, schema)
except jsonschema.ValidationError as exc:
    print(f"ERROR: schema validation failed: {exc.message}", file=sys.stderr)
    sys.exit(2)

# ── Atomic write: .tmp → mv ───────────────────────────────────────────────────
tmp_file = queue_file + ".tmp"
try:
    with open(tmp_file, "w") as fh:
        yaml.dump(queue, fh, default_flow_style=False, allow_unicode=True, sort_keys=False)
    os.replace(tmp_file, queue_file)
except Exception as exc:
    # Clean up .tmp on failure
    try:
        os.remove(tmp_file)
    except FileNotFoundError:
        pass
    print(f"ERROR: write failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(f"queue-set-status: goal {goal_id!r} → {new_status}")
sys.exit(0)
PY

exit $?
