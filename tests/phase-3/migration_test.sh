#!/usr/bin/env bash
# Tests for bin/migrate-v0.1-to-v0.2.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIGRATE="$REPO_ROOT/agentic-dev/bin/migrate-v0.1-to-v0.2.sh"
V01_FIXTURE="$REPO_ROOT/tests/phase-3/fixtures/sample-queue-v01.yaml"
SCHEMA="$REPO_ROOT/agentic-dev/schemas/queue.schema.json"

TMP_DIR="$(mktemp -d -t agentic-migrate-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_DIR" || rm -rf "$TMP_DIR"' EXIT

# Copy v0.1 fixture into tmp
cp "$V01_FIXTURE" "$TMP_DIR/queue.yaml"

# Run migration
"$MIGRATE" "$TMP_DIR/queue.yaml"

# Assert schema_version is now 0.2
NEW_VERSION="$(python3 -c "import yaml; print(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['schema_version'])")"
if [[ "$NEW_VERSION" != "0.2" ]]; then
  echo "FAIL: schema_version did not bump (got: $NEW_VERSION)" >&2
  exit 1
fi
echo "PASS schema_version bumped from 0.1 to 0.2"

# Assert result validates against v0.2 schema
python3 <<PY
import yaml, json, jsonschema
data = yaml.safe_load(open("$TMP_DIR/queue.yaml"))
schema = json.load(open("$SCHEMA"))
jsonschema.validate(data, schema, format_checker=jsonschema.FormatChecker())
print("PASS migrated queue.yaml validates against queue.schema.json")
PY

# Assert existing goal items preserved
GOAL_COUNT="$(python3 -c "import yaml; print(len(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['goals']))")"
if [[ "$GOAL_COUNT" != "1" ]]; then
  echo "FAIL: goal count changed (expected 1, got $GOAL_COUNT)" >&2
  exit 1
fi
echo "PASS goal items preserved through migration"

# Idempotency: re-run migration; should no-op
"$MIGRATE" "$TMP_DIR/queue.yaml"
VERSION_AFTER="$(python3 -c "import yaml; print(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['schema_version'])")"
if [[ "$VERSION_AFTER" != "0.2" ]]; then
  echo "FAIL: idempotent re-run changed schema_version (got $VERSION_AFTER)" >&2
  exit 1
fi
echo "PASS migration is idempotent (re-running on v0.2 keeps it at v0.2)"

# Reject unknown schema_version
echo 'schema_version: "9.9"' > "$TMP_DIR/bad.yaml"
echo 'goals: []' >> "$TMP_DIR/bad.yaml"
if "$MIGRATE" "$TMP_DIR/bad.yaml" 2>/dev/null; then
  echo "FAIL: migration on unknown version did not error" >&2
  exit 1
fi
echo "PASS migration rejects unknown schema_version"

echo "migration_test: OK"
