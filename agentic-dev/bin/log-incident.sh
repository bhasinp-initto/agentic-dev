#!/usr/bin/env bash
# log-incident.sh <type> <key=value> [<key=value> ...]
#
# Appends a new entry to .claude/agentic/<type>.yaml.
# type must be "checklist" or "memory".
#
# checklist: required keys  → rule, caught_by
#            optional key   → incident_ref (defaults to "<no-ref>")
# memory:    required keys  → observation, consequence
#
# Date is auto-populated from today's UTC (YYYY-MM-DD).
# Validates result against the schema before writing (atomic: .tmp → mv).
#
# Exit codes:
#   0 — success
#   1 — validation error, bad type, missing key, or file not found
#   2 — usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Usage check ──────────────────────────────────────────────────────────────

TYPE="${1:-}"
if [[ -z "$TYPE" ]]; then
  echo "Usage: log-incident.sh <type> <key=value> [<key=value> ...]" >&2
  echo "  type: checklist | memory" >&2
  exit 2
fi

# ── Validate type ─────────────────────────────────────────────────────────────

if [[ "$TYPE" != "checklist" && "$TYPE" != "memory" ]]; then
  echo "ERROR: invalid type '$TYPE'. Must be 'checklist' or 'memory'." >&2
  exit 1
fi

shift
KV_ARGS=("$@")

# ── Resolve paths ─────────────────────────────────────────────────────────────

YAML_FILE=".claude/agentic/${TYPE}.yaml"
SCHEMA_FILE="$SCRIPT_DIR/../schemas/${TYPE}.schema.json"

# ── File must exist (must be initialised by init skill) ──────────────────────

if [[ ! -f "$YAML_FILE" ]]; then
  echo "ERROR: $YAML_FILE not found. Run the init skill first." >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: schema file not found at $SCHEMA_FILE" >&2
  exit 1
fi

# ── Parse key=value pairs → JSON ─────────────────────────────────────────────

FIELDS_JSON="$(python3 -c "
import json, sys
args = sys.argv[1:]
d = {}
for arg in args:
    if '=' not in arg:
        print(f'ERROR: invalid key=value argument: {arg!r}', file=sys.stderr)
        sys.exit(1)
    k, v = arg.split('=', 1)
    d[k.strip()] = v.strip()
print(json.dumps(d))
" "${KV_ARGS[@]+"${KV_ARGS[@]}"}")" || {
  echo "ERROR: failed to parse key=value arguments" >&2
  exit 1
}

# ── Validate required keys and build + validate the entry ────────────────────

export TYPE YAML_FILE SCHEMA_FILE FIELDS_JSON

python3 - <<'PY'
import os, sys, json, yaml, jsonschema
from datetime import datetime, timezone

type_     = os.environ["TYPE"]
yaml_file = os.environ["YAML_FILE"]
schema_file = os.environ["SCHEMA_FILE"]
fields_json = os.environ["FIELDS_JSON"]

fields = json.loads(fields_json)

# ── Required-key validation ────────────────────────────────────────────────────

if type_ == "checklist":
    required_keys = {"rule", "caught_by"}
elif type_ == "memory":
    required_keys = {"observation", "consequence"}
else:
    print(f"ERROR: unknown type {type_!r}", file=sys.stderr)
    sys.exit(1)

missing = required_keys - set(fields.keys())
if missing:
    print(
        f"ERROR: missing required key(s) for {type_}: {', '.join(sorted(missing))}",
        file=sys.stderr,
    )
    sys.exit(1)

# ── Build entry ───────────────────────────────────────────────────────────────

today = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")

if type_ == "checklist":
    entry = {
        "date": today,
        "incident_ref": fields.get("incident_ref", "<no-ref>"),
        "rule": fields["rule"],
        "caught_by": fields["caught_by"],
    }
elif type_ == "memory":
    entry = {
        "date": today,
        "observation": fields["observation"],
        "consequence": fields["consequence"],
    }

# ── Load existing YAML ────────────────────────────────────────────────────────

with open(yaml_file) as fh:
    data = yaml.safe_load(fh)

if data is None:
    data = {}
if "entries" not in data or data["entries"] is None:
    data["entries"] = []

# ── Append entry ──────────────────────────────────────────────────────────────

data["entries"].append(entry)

# ── Validate against schema ───────────────────────────────────────────────────

with open(schema_file) as fh:
    schema = json.load(fh)

try:
    jsonschema.validate(instance=data, schema=schema,
                        format_checker=jsonschema.FormatChecker())
except jsonschema.ValidationError as exc:
    print(f"ERROR: schema validation failed: {exc.message}", file=sys.stderr)
    sys.exit(1)

# ── Atomic write ──────────────────────────────────────────────────────────────

tmp_file = yaml_file + ".tmp"
try:
    with open(tmp_file, "w") as fh:
        yaml.dump(data, fh, default_flow_style=False, allow_unicode=True,
                  sort_keys=False)
    os.replace(tmp_file, yaml_file)
except Exception as exc:
    try:
        os.remove(tmp_file)
    except FileNotFoundError:
        pass
    print(f"ERROR: write failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(f"log-incident: appended {type_} entry for date {today}")
sys.exit(0)
PY

exit $?
