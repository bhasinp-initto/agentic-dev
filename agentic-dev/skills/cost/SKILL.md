---
description: Public skill. Report on agentic-dev usage (per-goal artifacts, durations, estimated subagent dispatches, diff stats). Helps correlate plugin activity with your Anthropic Console billing. Honest about what it can and cannot see.
---

# `/agentic-dev:cost` — Usage Observability

## Overview

This skill walks the artifacts under `.claude/agentic/` (manifests, verdicts, reviewer-verdicts, diffs) and prints a usage rollup: per-goal status, duration, estimated subagent dispatches, and diff size. It is **not** a real cost tracker — agentic-dev cannot read the Anthropic Console billing API from inside a Claude Code plugin. The report is for correlation: "this goal ran 3 implementer rounds, my Console shows a spend bump in that window."

For actual API token spend, the source of truth is https://console.anthropic.com/settings/billing.

## How to interpret `$ARGUMENTS`

```
$ARGUMENTS = [--since YYYY-MM-DD] [--goal <goal-id>]
```

Optional filters:
- `--since YYYY-MM-DD` — only goals with `started_at >= <date>`
- `--goal <goal-id>` — only the named goal (other filters ignored)

If both filters are absent, report on every goal that has a manifest on disk.

### Parsing

1. If empty `$ARGUMENTS` → no filter; full rollup.
2. Tokenize on whitespace. Recognize `--since <value>` and `--goal <value>`. Other tokens print a warning and are ignored.
3. Validate `--since`: must match `^\d{4}-\d{2}-\d{2}$`. If malformed: print warning, ignore.
4. Validate `--goal`: must match `^\d{4}-\d{2}-\d{2}-[a-z0-9-]+$`. If malformed: print warning, ignore.

## Step 1: Walk the artifacts

For each `.claude/agentic/manifests/<goal-id>.json`:

1. Read the manifest. Extract: `goal_id`, `status`, `started_at`, `completed_at` (or null), `diff_stats`, `tests`, `commits`.
2. Apply filters (skip if `--since` excludes it; skip if `--goal` is set and doesn't match).
3. Check for a corresponding gate verdict at `.claude/agentic/verdicts/<goal-id>.json` (exists or absent).
4. Check for a corresponding reviewer verdict at `.claude/agentic/reviewer-verdicts/<goal-id>.json` (exists or absent).
5. Check for an adversary verdict at `.claude/agentic/reviewer-verdicts/<goal-id>.adversary.json` (exists or absent).
6. Check for auto-fix queue files at `.claude/agentic/auto-fix-queue/<goal-id>*.json` (count rounds if present).

## Step 2: Compute per-goal stats

For each goal in the filtered set:

- **Duration**: if `completed_at` is non-null, `completed_at - started_at`. Else if status is halted/abandoned, use the queue.yaml's `halted_at`. Else "in progress."
- **Estimated subagent dispatches**: sum of:
  - 1 (implementer per round; count rounds: 1 initial + N auto-fix rounds)
  - 1 if gate verdict exists (gates are deterministic shell scripts, but the gate-runner counts as 1 dispatch)
  - 1 if reviewer verdict exists
  - 1 if adversary verdict exists
- **Diff size**: `diff_stats.lines_added + diff_stats.lines_removed`
- **Tests**: from manifest

## Step 3: Print the rollup

Format:

```
agentic-dev: usage report
  filter: <filter string or "all goals">
  generated: <ISO timestamp>

Summary
  completed:        <N>
  halted:           <N>
  abandoned:        <N>
  in progress:      <N>

  total subagent dispatches (estimate):  <N>
  total wall-clock across goals:         <duration aggregated>
  total diff lines (sum):                <N>

Per-goal breakdown:

  goal_id                                            status      duration    dispatches   diff lines
  ─────────────────────────────────────────────────────────────────────────────────────────────────
  2026-05-21-build-tradingview-style-application... halted      2h 14m      9            1,247
  ...

Note: dispatch counts are estimates from on-disk artifacts. Token-level costs are at
https://console.anthropic.com/settings/billing — cross-reference by timestamp range.
```

If no goals match the filter, print:
```
agentic-dev: usage report — no goals match filter
  filter: <filter string>
```

## Step 4: Honest disclaimer at the end

Always print:

```
What this report can see:
  - Artifacts on disk (manifests, verdicts, diffs)
  - Counted subagent dispatches per goal
  - Diff sizes and test counts as reported by the implementer

What this report CANNOT see:
  - Actual API token usage (live in Anthropic Console)
  - Subagent token cost (depends on prompt size, which we don't log)
  - Headless `claude -p` invocations from test scripts (those bill against API credits separately)
```

## Implementation hint

Use the Bash tool with a Python heredoc to do the walking. Pattern:

```bash
python3 <<'PY'
import os, json, sys
from datetime import datetime, timezone

MANIFEST_DIR = '.claude/agentic/manifests'
if not os.path.isdir(MANIFEST_DIR):
    print('agentic-dev: no .claude/agentic/manifests/ — is this an init\\'d project?')
    sys.exit(1)

goals = []
for fname in sorted(os.listdir(MANIFEST_DIR)):
    if not fname.endswith('.json'):
        continue
    path = os.path.join(MANIFEST_DIR, fname)
    try:
        m = json.load(open(path))
    except Exception:
        continue  # skip malformed
    goals.append(m)

# apply filters, compute, print ...
PY
```

## Do NOT

- Do NOT claim this is a real cost tracker. It's a usage-correlation tool.
- Do NOT attempt to query the Anthropic API or scrape Console pages. Out of scope.
- Do NOT modify any state files. Read-only.
- Do NOT count rounds from `validation-log.txt` — that file has informational entries, not authoritative artifacts.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Report printed successfully (even if zero matches) |
| 1 | Not in an agentic-dev-initialized project (no manifests dir) |

## Skill metadata

- **Public** (no underscore prefix; users invoke it directly).
- **Read-only**.
- **No subagent dispatch**.
- Implemented entirely via the Read + Bash tools.
