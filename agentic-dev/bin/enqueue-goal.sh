#!/usr/bin/env bash
# Append a goal to .claude/agentic/queue.yaml from an approved spec.
#
# Usage: enqueue-goal.sh <goal-id>
#
# Reads .claude/agentic/specs/<goal-id>.md, verifies approved=true, checks
# the goal isn't already in queue.yaml, then appends a goal entry with
# status=approved. Schema-validates before writing. Atomic.
#
# Called by /agentic-dev:_check-approval on the clean verdict path so an
# approved spec enters the queue automatically without a separate user step.
# Can also be invoked manually if a spec was approved before this helper
# shipped.
set -euo pipefail

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: enqueue-goal.sh <goal-id>" >&2
  exit 1
fi

if [[ ! "$GOAL_ID" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$ ]]; then
  echo "ERROR: goal-id must match YYYY-MM-DD-<slug>; got: $GOAL_ID" >&2
  exit 1
fi

SPEC_PATH=".claude/agentic/specs/${GOAL_ID}.md"
QUEUE_PATH=".claude/agentic/queue.yaml"

if [[ ! -f "$SPEC_PATH" ]]; then
  echo "ERROR: spec file not found: $SPEC_PATH" >&2
  exit 1
fi

if [[ ! -f "$QUEUE_PATH" ]]; then
  echo "ERROR: queue.yaml not found at $QUEUE_PATH (project not initialized?)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SCRIPT_DIR/../schemas/queue.schema.json"

python3 - "$GOAL_ID" "$SPEC_PATH" "$QUEUE_PATH" "$SCHEMA" <<'PY'
import sys, os, datetime
import yaml, json

try:
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    sys.stderr.write(f"ERROR: missing python dep ({e.name}). Install with:\n")
    sys.stderr.write("  python3 -m pip install --break-system-packages pyyaml 'jsonschema[format-nongpl]'\n")
    sys.exit(1)

goal_id, spec_path, queue_path, schema_path = sys.argv[1:5]

# Parse spec frontmatter
spec_text = open(spec_path).read()
if not spec_text.startswith("---"):
    sys.stderr.write(f"ERROR: spec has no frontmatter: {spec_path}\n")
    sys.exit(1)
parts = spec_text.split("---", 2)
if len(parts) < 3:
    sys.stderr.write(f"ERROR: spec frontmatter not parseable: {spec_path}\n")
    sys.exit(1)
fm = yaml.safe_load(parts[1])

if not fm.get("approved"):
    sys.stderr.write(f"ERROR: spec is not approved (approved: false). Cannot enqueue.\n")
    sys.exit(1)

intent_path = fm.get("intent_path")
spec_id_in_frontmatter = fm.get("id")
if spec_id_in_frontmatter != goal_id:
    sys.stderr.write(f"ERROR: spec frontmatter id ({spec_id_in_frontmatter}) does not match goal-id arg ({goal_id})\n")
    sys.exit(1)

# Load queue
queue = yaml.safe_load(open(queue_path))
if not queue or not isinstance(queue, dict):
    sys.stderr.write(f"ERROR: queue.yaml is empty or malformed: {queue_path}\n")
    sys.exit(1)

goals = queue.get("goals", [])
if not isinstance(goals, list):
    goals = []

# Check if already in queue
existing = next((g for g in goals if g.get("id") == goal_id), None)
if existing:
    status = existing.get("status")
    if status == "approved":
        print(f"enqueue-goal: {goal_id} already in queue with status=approved; no-op")
        sys.exit(0)
    elif status in ("running", "completed", "halted", "abandoned"):
        sys.stderr.write(f"ERROR: {goal_id} already in queue with status={status}; refusing to re-enqueue (would clobber lifecycle state)\n")
        sys.exit(1)
    else:
        # status=intent_only or drafted — promote to approved
        existing["status"] = "approved"
        existing["spec_path"] = spec_path
        if intent_path:
            existing["intent_path"] = intent_path
        existing.setdefault("added_at", datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))
        action = "promoted"
else:
    # Append fresh
    new_goal = {
        "id": goal_id,
        "spec_path": spec_path,
        "intent_path": intent_path,
        "status": "approved",
        "added_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    goals.append(new_goal)
    action = "appended"

queue["goals"] = goals

# Validate before writing
schema = json.load(open(schema_path))
try:
    jsonschema.validate(queue, schema, format_checker=jsonschema.FormatChecker())
except jsonschema.ValidationError as e:
    sys.stderr.write(f"ERROR: resulting queue.yaml fails schema validation: {e.message}\n")
    sys.exit(1)

# Atomic write
tmp_path = queue_path + ".tmp"
with open(tmp_path, "w") as f:
    yaml.safe_dump(queue, f, default_flow_style=False, sort_keys=False)
os.replace(tmp_path, queue_path)

print(f"enqueue-goal: {action} {goal_id} (status=approved); queue now has {len(goals)} goal(s)")
PY
