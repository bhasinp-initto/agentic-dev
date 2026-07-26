#!/usr/bin/env bash
# review: success path + soft-skips, using a fake companion + a real temp git worktree.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$REPO_ROOT/agentic-dev/bin/codex-bridge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got: $2)"; fails=$((fails+1)); fi; }
field() { echo "$1" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$2'))"; }

# Fake plugin whose adversarial-review prints a canned payload with .result.
V="$TMP/cache/1.0.0"; mkdir -p "$V/scripts" "$V/schemas" "$V/.claude-plugin"
printf '{}' > "$V/.claude-plugin/plugin.json"
# Real review-output schema so schema validation passes:
cp "/Users/pankajbhasin/.claude/plugins/cache/openai-codex/codex/1.0.6/schemas/review-output.schema.json" "$V/schemas/review-output.schema.json" 2>/dev/null || printf '{"type":"object"}' > "$V/schemas/review-output.schema.json"
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready:true,auth:{available:true},codex:{available:true}})); process.exit(0); }
if (arg === "adversarial-review") {
  console.log(JSON.stringify({ result: {
    verdict: "needs-attention", summary: "risky",
    findings: [{severity:"high",title:"Race",body:"TOCTOU",file:"a.py",line_start:5,line_end:6,confidence:0.9,recommendation:"lock"}],
    next_steps: ["add lock"]
  }}));
  process.exit(0);
}
JS
printf '{"enabledPlugins":{"codex@openai-codex":true}}' > "$TMP/settings.json"
export AGENTIC_CODEX_CACHE_ROOT="$TMP/cache"
export AGENTIC_CODEX_SETTINGS="$TMP/settings.json"

# A real git worktree with a base commit and a head commit.
WT="$TMP/wt"; mkdir -p "$WT"; git -C "$WT" init -q
git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
BASE="$(git -C "$WT" rev-parse HEAD)"
git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m head
HEAD_SHA="$(git -C "$WT" rev-parse HEAD)"

# Success path
R="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "success-verdict" "$(field "$R" verdict)" "blocking"
check "success-role" "$(field "$R" reviewer_role)" "adversary"
check "success-not-skipped" "$(field "$R" skipped)" "None"

# head_mismatch
R2="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "deadbeef")"
check "head-mismatch" "$(field "$R2" reason_code)" "head_mismatch"

# base_missing
R3="$(bash "$BRIDGE" review 2026-07-26-demo "0000000000000000000000000000000000000000" "$WT" "$HEAD_SHA")"
check "base-missing" "$(field "$R3" reason_code)" "base_missing"

# not_a_worktree
R4="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$TMP/not-git" "$HEAD_SHA")"
check "not-a-worktree" "$(field "$R4" reason_code)" "not_a_worktree"

# timeout: companion sleeps beyond a 2s bridge timeout
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "adversarial-review") { setTimeout(()=>{}, 60000); }
JS
R5="$(AGENTIC_CODEX_TIMEOUT=2 bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "timeout" "$(field "$R5" reason_code)" "timeout"

# parse_error: companion prints junk
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "adversarial-review") { console.log("not json at all"); }
JS
R6="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "parse-error" "$(field "$R6" reason_code)" "parse_error"

# discover not-ready (plugin disabled) => proper skip shape, not raw discover JSON
printf '{"enabledPlugins":{"codex@openai-codex":false}}' > "$TMP/settings.json"
R7="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "plugin-disabled-skipped" "$(field "$R7" skipped)" "True"
check "plugin-disabled-reason" "$(field "$R7" reason_code)" "plugin_disabled"
printf '{"enabledPlugins":{"codex@openai-codex":true}}' > "$TMP/settings.json"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
