---
description: Internal lifecycle skill. Runs deterministic verification gates on a goal's manifest. Writes per-goal verdict JSON. Halts on first blocking failure.
---

# /agentic-dev:_run-gates

You are the lifecycle skill that runs all deterministic verification gates for one goal. You are invoked by the orchestrator (P6+) after the implementer completes, or directly for testing and debugging.

**Internal skill** — the underscore prefix (`_run-gates`) signals this skill is not for direct human invocation in the normal agentic-dev workflow. It is dispatched by the orchestrator (P6+) or used directly during P4 development.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the goal-id (e.g., `2026-05-21-add-health-endpoint`). If empty or missing, refuse:

```
agentic-dev: /agentic-dev:_run-gates requires a goal-id.
Example: /agentic-dev:_run-gates 2026-05-21-add-health-endpoint
```

Do not proceed with an empty `$ARGUMENTS`.

## Pre-checks

Before invoking `run-gates.sh`, verify:

1. **Manifest exists** at `.claude/agentic/manifests/<goal-id>.json`. If not, refuse:
   ```
   agentic-dev: manifest not found for goal <goal-id>; cannot run gates.
   Expected: .claude/agentic/manifests/<goal-id>.json
   ```
2. **Kickoff exists** at `.worktrees/goal-<goal-id>/.agentic-kickoff.json`. If not, refuse:
   ```
   agentic-dev: kickoff not found for goal <goal-id>; worktree may not be initialized.
   Expected: .worktrees/goal-<goal-id>/.agentic-kickoff.json
   ```
3. **Config exists** at `.claude/agentic/config.yaml`. If not, refuse:
   ```
   agentic-dev: config.yaml not found; cannot run gates.
   Expected: .claude/agentic/config.yaml
   ```

## Invoke run-gates.sh

Use the Bash tool to run:

```bash
agentic-dev/bin/run-gates.sh <goal-id>
```

The script resolves all paths relative to the current working directory (project root). Capture both stdout and the exit code.

## Output

Print the full output from `run-gates.sh` (it includes the structured summary table).

Then print:

```
agentic-dev: gates run complete

  goal:    <goal-id>
  verdict: .claude/agentic/verdicts/<goal-id>.json
  overall: <pass|fail|warning>
```

If `run-gates.sh` exits 1 (blocking failures detected), surface the failures clearly and exit.

## Exit code propagation

- If `run-gates.sh` exits 0 (overall pass or warning): skill exits normally.
- If `run-gates.sh` exits 1 (overall fail, blocking failures): skill surfaces the verdict summary and stops. Do NOT proceed to the next lifecycle stage.

## What this skill does NOT do

- Does NOT run the implementer (that is `_run-implementer`).
- Does NOT invoke the AI reviewer (that is P5's `_review-manifest` skill).
- Does NOT update the queue or circuit breaker (that is the orchestrator's job in P6).
- Does NOT clean up the worktree.
- Does NOT push anything.
- Does NOT call another skill (no nested skill invocation).

## Lifecycle context

```
P3: _run-implementer → manifest at .claude/agentic/manifests/<goal-id>.json
P4: _run-gates <goal-id> → verdict at .claude/agentic/verdicts/<goal-id>.json
P5: _review-manifest reads manifest + verdict (out of P4 scope)
```

The verdict file produced here is the input for P5's AI reviewer.
