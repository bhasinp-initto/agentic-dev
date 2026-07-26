#!/usr/bin/env bash
# Codex bridge: the only agentic-dev code that reaches the codex plugin.
# Subcommands: discover | preflight | review
# All failures are SOFT — callers fall back to Claude-only. Never exits non-zero
# for a Codex-unavailable condition; prints a JSON object describing it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECS="${AGENTIC_CODEX_TIMEOUT:-300}"

discover() { python3 "$SCRIPT_DIR/codex_discovery.py"; }

# Map the companion's setup --json to a reason_code. Args: <setup-json>
_setup_reason() {
  python3 - "$1" <<'PY'
import json, sys
try:
    s = json.loads(sys.argv[1])
except ValueError:
    print("setup_failed"); sys.exit()
if s.get("ready") is True:
    print("ok")
elif s.get("auth", {}).get("available") is False:
    print("not_authenticated")
elif s.get("codex", {}).get("available") is False:
    print("cli_missing")
else:
    print("setup_failed")
PY
}

preflight() {
  local disc; disc="$(discover)"
  local ready; ready="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')"
  if [ "$ready" != "True" ]; then echo "$disc"; return 0; fi

  local companion; companion="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["companion_path"])')"
  local setup_json reason
  setup_json="$(node "$companion" setup --json 2>/dev/null)" || setup_json='{}'
  reason="$(_setup_reason "$setup_json")"

  echo "$disc" | python3 -c '
import json, sys
disc = json.load(sys.stdin)
reason = sys.argv[1]
disc["ready"] = (reason == "ok")
disc["reason_code"] = reason
print(json.dumps(disc))
' "$reason"
}

case "${1:-}" in
  discover) discover ;;
  preflight) preflight ;;
  review) shift; review "$@" ;;   # defined in Task 6
  *) echo '{"ready":false,"reason_code":"bad_usage","detail":"discover|preflight|review"}'; exit 0 ;;
esac
