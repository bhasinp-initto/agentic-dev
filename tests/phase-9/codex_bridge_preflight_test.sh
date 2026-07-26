#!/usr/bin/env bash
# Bridge discover/preflight against a fake companion .mjs (no real plugin needed).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$REPO_ROOT/agentic-dev/bin/codex-bridge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got: $2)"; fails=$((fails+1)); fi; }

# Build a fake plugin version dir with a companion that reports healthy setup.
V="$TMP/cache/1.0.0"
mkdir -p "$V/scripts" "$V/schemas" "$V/.claude-plugin"
printf '{}' > "$V/.claude-plugin/plugin.json"
printf '{}' > "$V/schemas/review-output.schema.json"
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready: true, auth: {available: true}, codex: {available: true}})); }
JS
printf '{"enabledPlugins":{"codex@openai-codex":true}}' > "$TMP/settings.json"

export AGENTIC_CODEX_CACHE_ROOT="$TMP/cache"
export AGENTIC_CODEX_SETTINGS="$TMP/settings.json"

# discover
D="$(bash "$BRIDGE" discover)"
check "discover-ready" "$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')" "True"

# preflight healthy
P="$(bash "$BRIDGE" preflight)"
check "preflight-ready" "$(echo "$P" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')" "True"

# preflight when auth missing => not_authenticated
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready: false, auth: {available: false}, codex: {available: true}})); }
JS
P2="$(bash "$BRIDGE" preflight)"
check "preflight-not-authed" "$(echo "$P2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason_code"])')" "not_authenticated"

# preflight when plugin disabled => short-circuits, no node needed
printf '{"enabledPlugins":{"codex@openai-codex":false}}' > "$TMP/settings.json"
P3="$(bash "$BRIDGE" preflight)"
check "preflight-disabled" "$(echo "$P3" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason_code"])')" "plugin_disabled"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
