#!/usr/bin/env bash
# Codex bridge: the only agentic-dev code that reaches the codex plugin.
# Subcommands: discover | preflight | review
# All failures are SOFT — callers fall back to Claude-only. Never exits non-zero
# for a Codex-unavailable condition; prints a JSON object describing it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECS="${AGENTIC_CODEX_TIMEOUT:-300}"

# _run_bounded <secs> <outfile> <cmd...> — run cmd with stdout to outfile, killing
# it after <secs>. Returns cmd's exit status, or 124 on timeout. Portable (no `timeout`).
_run_bounded() {
  local secs="$1" outfile="$2"; shift 2
  "$@" >"$outfile" 2>/dev/null &
  local pid=$! elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      return 124
    fi
    sleep 1; elapsed=$((elapsed+1))
  done
  wait "$pid" 2>/dev/null
}

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
  local setup_tmp; setup_tmp="$(mktemp)"
  if _run_bounded "$TIMEOUT_SECS" "$setup_tmp" node "$companion" setup --json; then
    setup_json="$(cat "$setup_tmp")"
  else
    setup_json='{}'
  fi
  rm -f "$setup_tmp"
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

_skip() { printf '{"skipped":true,"reason_code":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 0; }

review() {
  local goal_id="${1:-}" base_sha="${2:-}" worktree="${3:-}" expected_head="${4:-}"
  shift 4 2>/dev/null || true
  # remaining args ("$@") = focus text, passed through as argv — never shell-interpolated.

  # Discover the companion (structural check only: files exist, plugin enabled).
  # NOTE: deliberately uses discover(), not the live preflight() (which spawns
  # `node companion setup --json`). review() is invoked per-goal and must not
  # re-run that live health probe every time; preflight is a separate, earlier
  # gate. Discovery reason codes (plugin_disabled, no_valid_version, missing_files,
  # setup_failed if ever surfaced) still soft-skip via the same path.
  local disc ready companion schema
  disc="$(discover)"
  ready="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')"
  if [ "$ready" != "True" ]; then echo "$disc"; return 0; fi
  companion="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["companion_path"])')"
  schema="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["schema_path"])')"

  # Preconditions on the worktree.
  git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 || _skip not_a_worktree "$worktree"
  local head_now; head_now="$(git -C "$worktree" rev-parse HEAD 2>/dev/null)"
  [ "$head_now" = "$expected_head" ] || _skip head_mismatch "HEAD=$head_now expected=$expected_head"
  git -C "$worktree" cat-file -e "${base_sha}^{commit}" 2>/dev/null || _skip base_missing "$base_sha"

  # Run the companion with a bridge-enforced timeout, reusing _run_bounded.
  # `exec node ...` inside the wrapper replaces the bash -c process image so
  # _run_bounded's kill(TERM/KILL) lands directly on the node process — no orphan.
  # Focus args ("$@") are passed as argv positions (${@:3} below), never
  # interpolated into the command string.
  local out; out="$(mktemp)"
  local rc=0
  _run_bounded "$TIMEOUT_SECS" "$out" bash -c \
    'cd "$0" && exec node "$1" adversarial-review --json --wait --base "$2" --scope branch "${@:3}"' \
    "$worktree" "$companion" "$base_sha" "$@" || rc=$?
  if [ "$rc" -eq 124 ]; then
    rm -f "$out"; _skip timeout "${TIMEOUT_SECS}s"
  fi

  # Extract top-level .result.
  local result; result="$(mktemp)"
  if ! python3 -c '
import json, sys
raw = open(sys.argv[1]).read()
obj = json.loads(raw)               # raises on junk -> parse_error
res = obj.get("result")
if res is None: raise SystemExit(3)
open(sys.argv[2], "w").write(json.dumps(res))
' "$out" "$result" 2>/dev/null; then
    rm -f "$out" "$result"; _skip parse_error "no .result / bad json"
  fi

  # Validate .result against the selected companion's schema (best-effort; jsonschema
  # is a test dep, not guaranteed in prod — skip validation if unavailable or schema missing).
  if python3 -c 'import jsonschema' 2>/dev/null && [ -f "$schema" ]; then
    python3 -c '
import json, sys, jsonschema
jsonschema.validate(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))
' "$result" "$schema" 2>/dev/null || { rm -f "$out" "$result"; _skip schema_invalid ""; }
  fi

  # Adapt to reviewer-verdict.
  local reviewed_at; reviewed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 "$SCRIPT_DIR/codex_adapter.py" adapt "$result" \
    --goal-id "$goal_id" --reviewed-at "$reviewed_at"
  rm -f "$out" "$result"
}

case "${1:-}" in
  discover) discover ;;
  preflight) preflight ;;
  review) shift; review "$@" ;;   # defined in Task 6
  *) echo '{"ready":false,"reason_code":"bad_usage","detail":"discover|preflight|review"}'; exit 0 ;;
esac
