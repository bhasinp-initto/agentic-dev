---
description: Internal lifecycle skill (orchestrator-invoked). Dispatches the walkthrough-runner subagent against a goal that passed gates + reviewer; captures the walkthrough verdict (clean | concern | blocking | skipped) and writes it to .claude/agentic/walkthrough-verdicts/<goal-id>.json. Does NOT make routing decisions — that's _advance-goal's job.
---

# `/agentic-dev:_run-walkthrough` — Walkthrough Lifecycle

## Overview

You are the lifecycle skill that runs the Playwright-driven walkthrough for a single goal. You are invoked by `_advance-goal` after the AI reviewer (primary + optional adversary) returns clean, BEFORE the goal is marked completed and its worktree cleaned. Your job: dispatch the `walkthrough-runner` subagent, validate its JSON response against `walkthrough-verdict.schema.json`, write the verdict file. Routing decisions (clean → advance, concern → auto-fix queue, blocking → escalate, skipped → treat as clean) are made by the caller.

---

## How to interpret `$ARGUMENTS`

```
$ARGUMENTS = <goal-id>
```

`<goal-id>` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$`. If empty or malformed, refuse:

```
agentic-dev: /agentic-dev:_run-walkthrough requires a goal-id.
Example: /agentic-dev:_run-walkthrough 2026-05-22-add-checkout-flow
```

---

## Pre-checks

1. **Manifest exists** at `.claude/agentic/manifests/<goal-id>.json`. If not → refuse with `agentic-dev: manifest not found for <goal-id>; cannot run walkthrough`.

2. **Reviewer-verdict clean** — read `.claude/agentic/reviewer-verdicts/<goal-id>.json`; require `verdict == "clean"`. If `concern` or `blocking`, refuse — walkthrough only runs AFTER reviewer-clean.

3. **Worktree exists** at the path in the manifest. If not → refuse.

4. **Kickoff exists** at `<worktree_path>/.agentic-kickoff.json` — required to read the walkthrough specification.

---

## Read the walkthrough spec from kickoff

The kickoff JSON has an optional `walkthrough` field (added in 1.4.0). Shape:

```json
{
  "walkthrough": {
    "acceptance_url": "http://localhost:5173/",
    "acceptance_criteria": [
      "Open / and verify the header shows 'TradingView Dashboard'",
      "Click 'Watchlist' in the sidebar; verify the URL is /watchlist",
      "..."
    ],
    "dev_server_command": "npm run dev",
    "dev_server_ready_pattern": "Local:.*5173",
    "dev_server_port": 5173
  }
}
```

If `kickoff.walkthrough` is null, missing, or `acceptance_criteria` is empty → the goal has no UI to walk. Build a stub verdict immediately:

```json
{
  "schema_version": "0.1",
  "goal_id": "<id>",
  "walked_at": "<now>",
  "verdict": "skipped",
  "skip_reason": "no walkthrough section in spec",
  "dev_server": null,
  "criteria_results": [],
  "console_errors_count": 0,
  "artifacts": []
}
```

Write it to `.claude/agentic/walkthrough-verdicts/<goal-id>.json`. Exit 0.

---

## Set up the screenshot directory

```bash
mkdir -p .claude/agentic/walkthrough-screenshots/<goal-id>
```

---

## Dispatch walkthrough-runner

Use the Agent tool with `subagent_type: walkthrough-runner`. Construct the prompt:

```
You are dispatched as walkthrough-runner for goal <goal-id>.

Worktree path (absolute): <worktree_path>
Acceptance URL: <kickoff.walkthrough.acceptance_url>
Acceptance criteria (in order):
1. <criterion 1>
2. <criterion 2>
...
Dev server command: <kickoff.walkthrough.dev_server_command or "null">
Dev server ready pattern: <kickoff.walkthrough.dev_server_ready_pattern or "null">
Screenshots directory: .claude/agentic/walkthrough-screenshots/<goal-id>/

Follow your calibration:
- Skip cleanly if walkthrough not configured / Playwright not available
- Bring up dev server only if needed; tear it down after
- Drive the browser through each criterion in order
- Capture screenshots per criterion
- Collect console errors
- Compute verdict per your rules
- Output a single JSON object matching walkthrough-verdict.schema.json. No preamble. No code fences.
```

---

## Capture + validate the walkthrough response

The subagent's response should be a single JSON object. Parse it with the Bash tool:

```bash
printf '%s' "<subagent response>" | python3 -c "
import json, sys, jsonschema
try:
    obj = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f'PARSE_ERROR: {e}')
    sys.exit(1)
schema = json.load(open('${CLAUDE_PLUGIN_ROOT}/schemas/walkthrough-verdict.schema.json'))
try:
    jsonschema.validate(obj, schema, format_checker=jsonschema.FormatChecker())
except jsonschema.ValidationError as e:
    print(f'SCHEMA_ERROR: {e.message}')
    sys.exit(1)
print(f'OK verdict={obj[\"verdict\"]}')
"
```

On `PARSE_ERROR` or `SCHEMA_ERROR`: save the raw response to `.claude/agentic/walkthrough-verdicts/<goal-id>.raw.txt`, write a stub verdict with `verdict: blocking` + a criterion result describing the parse failure, log to `validation-log.txt`. The orchestrator will then escalate.

On valid output: write the parsed JSON to `.claude/agentic/walkthrough-verdicts/<goal-id>.json` via the Write tool.

---

## Output summary

Print a structured summary to stdout so the operator transcript shows what happened:

```
agentic-dev: walkthrough complete
  goal:                <goal-id>
  verdict:             <clean | concern | blocking | skipped>
  criteria attempted:  <N>
  passed:              <N>
  failed:              <N>
  inconclusive:        <N>
  console errors:      <N>
  dev server:          <started by walkthrough | already running | n/a>
  screenshots:         <count> at .claude/agentic/walkthrough-screenshots/<goal-id>/
  verdict file:        .claude/agentic/walkthrough-verdicts/<goal-id>.json
```

Exit 0. Routing is the orchestrator's job, not yours.

---

## Do NOT

- Do NOT make routing decisions. Output the verdict; let `_advance-goal` route.
- Do NOT delete screenshots or any walkthrough artifacts.
- Do NOT clean up the worktree.
- Do NOT modify the manifest, reviewer verdict, gate verdict, or spec.
- Do NOT call `bin/telegram-notify.sh` directly — the orchestrator handles notifications based on the final routing decision.
- Do NOT install Playwright if it's missing. Skip cleanly with reason "Playwright MCP tools not available."
