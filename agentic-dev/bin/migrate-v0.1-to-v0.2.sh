#!/usr/bin/env bash
# Migrate .claude/agentic/queue.yaml from schema v0.1 to v0.2.
#
# v0.2 adds optional fields to goal items (started_at, completed_at, halted_at,
# baseline_ref, head_ref, worktree_path, manifest_path, budget_overrides). Since
# they're optional, existing v0.1 goal items are valid in v0.2 — the only
# required change is bumping schema_version.
#
# Idempotent. Validates the result against queue.schema.json before writing.
set -euo pipefail

QUEUE_FILE="${1:-.claude/agentic/queue.yaml}"
if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "ERROR: queue file not found: $QUEUE_FILE" >&2
  exit 1
fi

# Detect plugin directory (we need queue.schema.json)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEMA="$PLUGIN_ROOT/schemas/queue.schema.json"

# Read current schema_version
CURRENT_VERSION="$(python3 -c "
import yaml, sys
data = yaml.safe_load(open('$QUEUE_FILE'))
print(data.get('schema_version', 'unknown'))
")"

if [[ "$CURRENT_VERSION" == "0.2" ]]; then
  echo "queue.yaml already at v0.2; no migration needed"
  exit 0
fi

if [[ "$CURRENT_VERSION" != "0.1" ]]; then
  echo "ERROR: queue.yaml has unexpected schema_version: $CURRENT_VERSION" >&2
  echo "  expected 0.1 (to migrate) or 0.2 (already migrated)" >&2
  exit 1
fi

# Migration: bump schema_version to "0.2". Existing fields stay; new fields
# remain absent (they're all optional).
python3 <<PY
import yaml, json, jsonschema
data = yaml.safe_load(open("$QUEUE_FILE"))
data["schema_version"] = "0.2"
# Validate before writing
schema = json.load(open("$SCHEMA"))
jsonschema.validate(data, schema, format_checker=jsonschema.FormatChecker())
# Write back with stable formatting
with open("$QUEUE_FILE", "w") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
PY

echo "migrated $QUEUE_FILE from v0.1 to v0.2"
