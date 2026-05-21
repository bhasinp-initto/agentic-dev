#!/usr/bin/env bash
# run-gates.sh <goal-id> [--project-root <path>]
#
# Orchestration wrapper: runs all deterministic gate scripts for a goal,
# aggregates results into a gate-verdict JSON, and writes it to
# .claude/agentic/verdicts/<goal-id>.json.
#
# Exit codes:
#   0 — overall verdict is "pass" or "warning"
#   1 — overall verdict is "fail" (blocking failures), or pre-check error
#
# JSON verdict conforms to agentic-dev/schemas/gate-verdict.schema.json.
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

GOAL_ID="${1:-}"
PROJECT_ROOT=""

if [[ -z "$GOAL_ID" ]]; then
  echo "run-gates: usage: run-gates.sh <goal-id> [--project-root <path>]" >&2
  exit 1
fi

shift 1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    *)
      echo "run-gates: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Path resolution ───────────────────────────────────────────────────────────

MANIFEST_PATH="$PROJECT_ROOT/.claude/agentic/manifests/${GOAL_ID}.json"
KICKOFF_PATH="$PROJECT_ROOT/.worktrees/goal-${GOAL_ID}/.agentic-kickoff.json"
VERDICT_DIR="$PROJECT_ROOT/.claude/agentic/verdicts"
VERDICT_PATH="$VERDICT_DIR/${GOAL_ID}.json"
CONFIG_PATH="$PROJECT_ROOT/.claude/agentic/config.yaml"
SCHEMA_PATH="$SCRIPT_DIR/../schemas/gate-verdict.schema.json"

# ── Pre-checks ────────────────────────────────────────────────────────────────

echo "run-gates: starting gate run for goal: $GOAL_ID"
echo "  manifest:  $MANIFEST_PATH"
echo "  kickoff:   $KICKOFF_PATH"
echo "  config:    $CONFIG_PATH"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "run-gates: ERROR: manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

if [[ ! -f "$KICKOFF_PATH" ]]; then
  echo "run-gates: ERROR: kickoff not found: $KICKOFF_PATH" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "run-gates: ERROR: config not found: $CONFIG_PATH" >&2
  exit 1
fi

# Validate manifest JSON is parseable and extract spec_path
SPEC_PATH_REL=""
if ! SPEC_PATH_REL="$(python3 - "$MANIFEST_PATH" <<'PY'
import sys, json
try:
    mf = json.load(open(sys.argv[1]))
except json.JSONDecodeError as e:
    print(f"run-gates: ERROR: manifest JSON parse failed: {e}", file=sys.stderr)
    sys.exit(1)
print(mf.get("spec_path", ""))
PY
)"; then
  echo "run-gates: ERROR: manifest JSON is invalid — aborting before any gate" >&2
  exit 1
fi

# Resolve spec path
SPEC_ABS=""
if [[ -n "$SPEC_PATH_REL" ]]; then
  SPEC_ABS="$PROJECT_ROOT/$SPEC_PATH_REL"
fi

# ── Temp directory for gate outputs ──────────────────────────────────────────

GATE_TMP="$(mktemp -d)"
trap "rm -rf '$GATE_TMP'" EXIT
GATE_SEQ=0  # counter for ordering

# ── Gate execution helper ─────────────────────────────────────────────────────

# run_gate <canonical-name> <script-filename> [args...]
# Runs the gate, captures its JSON output to a numbered temp file.
# Never exits early — collects all gate results regardless of individual exit codes.
run_gate() {
  local gate_name="$1"
  local gate_script="$SCRIPT_DIR/$2"
  shift 2
  local gate_args=("$@")

  GATE_SEQ=$((GATE_SEQ + 1))
  local out_file="$GATE_TMP/$(printf '%02d' "$GATE_SEQ")-${gate_name}.json"

  echo ""
  echo "run-gates: running gate: $gate_name"

  if [[ ! -x "$gate_script" ]]; then
    python3 -c "
import json
print(json.dumps({
    'name': '$gate_name',
    'result': 'inconclusive',
    'severity': 'warning',
    'details': 'gate script not found or not executable: $gate_script',
}))
" > "$out_file"
    echo "  [$gate_name] inconclusive (script missing)"
    return
  fi

  # Run gate; capture stdout (JSON); allow non-zero exit (failure is data, not abort)
  local raw_json=""
  local gate_exit=0
  raw_json="$("$gate_script" "${gate_args[@]}")" || gate_exit=$?

  # Normalize: replace "gate" key with "name" = canonical gate_name
  if ! python3 - "$gate_name" <<PYNORM > "$out_file"
import sys, json

gate_name = sys.argv[1]
raw = '''${raw_json}'''
try:
    d = json.loads(raw)
except json.JSONDecodeError as e:
    d = {
        'name': gate_name,
        'result': 'inconclusive',
        'severity': 'warning',
        'details': f'gate produced unparseable JSON: {str(e)[:200]}',
        'raw': {'raw_output': raw[:500]},
    }
    print(json.dumps(d))
    sys.exit(0)

# Replace "gate" key with "name" (canonical gate name)
d.pop('gate', None)
d['name'] = gate_name
print(json.dumps(d))
PYNORM
  then
    # Python normalization failed — write fallback
    python3 -c "
import json
print(json.dumps({
    'name': '$gate_name',
    'result': 'inconclusive',
    'severity': 'warning',
    'details': 'gate output normalization failed',
}))
" > "$out_file"
  fi

  local result
  result="$(python3 -c "import json; print(json.load(open('$out_file')).get('result','inconclusive'))")" || result="inconclusive"
  echo "  [$gate_name] $result"
}

# ── Run gates in order ────────────────────────────────────────────────────────

# 1. scope-check
if [[ -n "$SPEC_ABS" && -f "$SPEC_ABS" ]]; then
  run_gate "scope-check" "gate-scope-check.sh" "$MANIFEST_PATH" "$SPEC_ABS"
else
  GATE_SEQ=$((GATE_SEQ + 1))
  python3 -c "import json; print(json.dumps({'name':'scope-check','result':'inconclusive','severity':'warning','details':'spec not found; scope check skipped'}))" \
    > "$GATE_TMP/$(printf '%02d' "$GATE_SEQ")-scope-check.json"
  echo ""
  echo "run-gates: skipping scope-check (spec not found at: $SPEC_ABS)"
fi

# 2. budget-check
run_gate "budget-check" "gate-budget-check.sh" "$MANIFEST_PATH" "$KICKOFF_PATH"

# 3. sensitive-path-check
run_gate "sensitive-path-check" "gate-sensitive-path-check.sh" "$MANIFEST_PATH" "$CONFIG_PATH"

# 4. test-count-check
run_gate "test-count-check" "gate-test-count-check.sh" "$MANIFEST_PATH" "$KICKOFF_PATH"

# 5. rerun-tests
run_gate "rerun-tests" "gate-rerun-tests.sh" "$MANIFEST_PATH" "$KICKOFF_PATH"

# 6. bisect-on-claim (only if manifest has pre-existing deferrals)
NEEDS_BISECT="$(python3 - "$MANIFEST_PATH" <<'PY'
import sys, json
try:
    mf = json.load(open(sys.argv[1]))
    deferrals = mf.get("deferrals") or []
    has_preexisting = any(
        isinstance(d, dict) and "pre-existing" in str(d.get("reason", "")).lower()
        for d in deferrals
    )
    print("yes" if has_preexisting else "no")
except Exception:
    print("no")
PY
)"

if [[ "$NEEDS_BISECT" == "yes" ]]; then
  run_gate "bisect-on-claim" "bisect-on-claim.sh" "$MANIFEST_PATH"
fi

# ── Aggregate results via Python ──────────────────────────────────────────────

echo ""
echo "run-gates: aggregating results..."

mkdir -p "$VERDICT_DIR"

python3 - "$GATE_TMP" "$MANIFEST_PATH" "$GOAL_ID" "$VERDICT_PATH" <<'PY'
import sys, json, os, glob
from datetime import datetime, timezone

gate_tmp, mpath, goal_id, verdict_path = sys.argv[1:5]

# Read gate output files in numeric order
gate_files = sorted(glob.glob(os.path.join(gate_tmp, "*.json")))
gates = []
for f in gate_files:
    try:
        gates.append(json.load(open(f)))
    except Exception as e:
        name = os.path.basename(f).split("-", 1)[1].replace(".json", "")
        gates.append({
            "name": name,
            "result": "inconclusive",
            "severity": "warning",
            "details": f"failed to read gate output: {e}",
        })

# Compute overall
blocking_failures = []
warnings = []
for g in gates:
    result = g.get("result", "inconclusive")
    severity = g.get("severity", "warning")
    name = g.get("name", "unknown")
    if result == "fail" and severity == "blocking":
        blocking_failures.append(name)
    elif result in ("fail", "inconclusive") and severity == "warning":
        warnings.append(name)

if blocking_failures:
    overall = "fail"
elif warnings:
    overall = "warning"
else:
    overall = "pass"

# Manifest path for reference
manifest_path_val = f".claude/agentic/manifests/{goal_id}.json"

checked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

verdict = {
    "schema_version": "0.1",
    "goal_id": goal_id,
    "manifest_path": manifest_path_val,
    "checked_at": checked_at,
    "gates": gates,
    "overall": overall,
    "blocking_failures": blocking_failures,
    "warnings": warnings,
}

with open(verdict_path, "w") as f:
    json.dump(verdict, f, indent=2)
    f.write("\n")

print(f"run-gates: verdict written: {verdict_path}")
PY

# ── Validate verdict against schema ──────────────────────────────────────────

python3 - "$VERDICT_PATH" "$SCHEMA_PATH" <<'PY' 2>/dev/null || true
import sys, json
try:
    import jsonschema
except ImportError:
    sys.exit(0)
try:
    verdict = json.load(open(sys.argv[1]))
    schema = json.load(open(sys.argv[2]))
    jsonschema.validate(verdict, schema, format_checker=jsonschema.FormatChecker())
except jsonschema.ValidationError as e:
    print(f"run-gates: WARNING: verdict failed schema self-check: {e.message}", file=sys.stderr)
except Exception:
    pass
sys.exit(0)
PY

# ── Print summary ─────────────────────────────────────────────────────────────

python3 - "$VERDICT_PATH" <<'PY'
import sys, json

verdict = json.load(open(sys.argv[1]))
overall = verdict["overall"]
blocking = verdict["blocking_failures"]
warnings_list = verdict["warnings"]
gates = verdict["gates"]

print()
print("=" * 60)
print(f"  run-gates summary — goal: {verdict['goal_id']}")
print("=" * 60)
print(f"  overall:           {overall.upper()}")
print(f"  checked_at:        {verdict['checked_at']}")
print(f"  gates run:         {len(gates)}")
print(f"  blocking failures: {len(blocking)}")
print(f"  warnings:          {len(warnings_list)}")
print()

for g in gates:
    name = g.get("name", "?")
    result = g.get("result", "?")
    details = g.get("details", "")
    marker = "PASS" if result == "pass" else ("WARN" if result == "inconclusive" else "FAIL")
    print(f"  [{marker}] {name:28s} {details[:80]}")

if blocking:
    print()
    print(f"  BLOCKING FAILURES: {', '.join(blocking)}")
if warnings_list:
    print()
    print(f"  WARNINGS: {', '.join(warnings_list)}")

print()
if overall == "pass":
    print("  Result: PASS — all gates passed.")
elif overall == "warning":
    print("  Result: WARNING — no blocking failures; review warnings above.")
else:
    print("  Result: FAIL — blocking failures detected. Fix before proceeding.")
print("=" * 60)
PY

# ── Exit code ─────────────────────────────────────────────────────────────────

OVERALL="$(python3 -c "import json; print(json.load(open('$VERDICT_PATH'))['overall'])")"

if [[ "$OVERALL" == "fail" ]]; then
  exit 1
else
  exit 0
fi
