#!/usr/bin/env bash
# gate-budget-check.sh <manifest-path> <kickoff-path>
# Exits 0 on pass / 1 on fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
KICKOFF="${2:-}"
if [[ -z "$MANIFEST" || -z "$KICKOFF" ]]; then
  echo '{"gate":"budget-check","result":"inconclusive","severity":"warning","details":"missing args"}'
  exit 1
fi

python3 - "$MANIFEST" "$KICKOFF" <<'PY'
import sys, json
from datetime import datetime, timezone

mpath, kpath = sys.argv[1:3]
mf = json.load(open(mpath))
kf = json.load(open(kpath))

budget = kf.get("budget", {})
budget_lines = budget.get("diff_lines_per_goal")
budget_files = budget.get("files_touched_per_goal")
budget_wall  = budget.get("wall_clock_minutes_per_goal")

diff_stats = mf.get("diff_stats", {})
files_touched  = diff_stats.get("files_touched", 0)
lines_added    = diff_stats.get("lines_added", 0)
lines_removed  = diff_stats.get("lines_removed", 0)
total_lines    = lines_added + lines_removed

# Compute wall-clock minutes if both timestamps present
wall_minutes = None
started_at   = mf.get("started_at")
completed_at = mf.get("completed_at")
if started_at and completed_at:
    try:
        fmt = "%Y-%m-%dT%H:%M:%SZ"
        t0 = datetime.strptime(started_at, fmt).replace(tzinfo=timezone.utc)
        t1 = datetime.strptime(completed_at, fmt).replace(tzinfo=timezone.utc)
        wall_minutes = (t1 - t0).total_seconds() / 60.0
    except Exception:
        pass

failures = []
if budget_lines is not None and total_lines > budget_lines:
    failures.append(f"lines: {total_lines} > budget {budget_lines}")
if budget_files is not None and files_touched > budget_files:
    failures.append(f"files_touched: {files_touched} > budget {budget_files}")
if budget_wall is not None and wall_minutes is not None and wall_minutes > budget_wall:
    failures.append(f"wall_clock_minutes: {wall_minutes:.1f} > budget {budget_wall}")

raw = {
    "total_lines": total_lines,
    "lines_added": lines_added,
    "lines_removed": lines_removed,
    "files_touched": files_touched,
    "wall_minutes": wall_minutes,
    "budget_lines": budget_lines,
    "budget_files": budget_files,
    "budget_wall": budget_wall,
}

if failures:
    print(json.dumps({
        "gate": "budget-check",
        "result": "fail",
        "severity": "blocking",
        "details": "budget exceeded: " + "; ".join(failures),
        "raw": raw,
    }))
    sys.exit(1)

wall_note = f"{wall_minutes:.1f}min" if wall_minutes is not None else "n/a (completed_at null)"
print(json.dumps({
    "gate": "budget-check",
    "result": "pass",
    "severity": "blocking",
    "details": (f"all within budget: {total_lines} lines, "
                f"{files_touched} files, wall={wall_note}"),
    "raw": raw,
}))
sys.exit(0)
PY
