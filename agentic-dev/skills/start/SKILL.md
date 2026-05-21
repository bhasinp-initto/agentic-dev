---
description: Public entry point. Begin a queue run. Optionally accepts --until <HH:MM | <N>m | <N>h> to set a target wall-clock cutoff.
---

# `/agentic-dev:start` — Begin a Queue Run

## Overview

This is the public entry point for starting an autonomous queue run.
It validates the circuit breaker, optionally records a run cutoff time, sets
the circuit breaker to `running`, and delegates to `_run-orchestrator` to drive
the approved-goal queue.

---

## $ARGUMENTS

```
$ARGUMENTS = [--until <value>]
```

Optional argument: `--until <value>` where `<value>` is one of:

- `HH:MM` — wall-clock cutoff time (e.g. `--until 23:30`)
- `<N>m` — duration in minutes (e.g. `--until 45m`)
- `<N>h` — duration in hours (e.g. `--until 2h`)

If `--until` is not provided, the run continues until the queue is exhausted,
halted, or manually interrupted.

### Parsing $ARGUMENTS

1. If `$ARGUMENTS` is empty or not provided → no cutoff; proceed normally.
2. If `$ARGUMENTS` starts with `--until` → extract the value token that follows.
3. Validate the value matches one of the accepted formats above.
   - Invalid format → print a warning and proceed without a cutoff (do not abort).
4. Any other tokens are ignored.

---

## Step 1a: Pre-check — Orphan Approved Specs

Before checking the circuit breaker, scan for "orphan approved specs" — specs in `.claude/agentic/specs/*.md` with `approved: true` in frontmatter, but whose `id` is NOT present in `.claude/agentic/queue.yaml`'s goals list (at any status).

For each orphan found, print:
```
NOTICE: approved spec not in queue: <spec-path>
  goal id: <id>
  run /agentic-dev:_check-approval <spec-path> to validate and auto-enqueue.
```

This catches the case where a user manually set `approved: true` and ran `/agentic-dev:start` without going through the AI validator. The fix is to run `_check-approval` (which validates AND enqueues on the clean path).

Do NOT auto-enqueue from /start — that would skip the AI validator. Just warn and proceed. The user will still see "Queue empty" or similar from the orchestrator and know what to do.

---

## Step 1: Pre-check — Circuit Breaker State

Read `.claude/agentic/state.json` and inspect `circuit_breaker.state`.

- **`halted`** — refuse with:
  ```
  ERROR: Queue is currently halted.
  Halted goal: <circuit_breaker.halted_goal_id>
  Reason:      <circuit_breaker.halted_reason>
  Run /agentic-dev:resume <decision> to address the halt before starting again.
  ```
  Exit 1.

- **`idle`** or **`running`** — proceed to Step 2.

- **`completed`** — the previous run finished cleanly. Treat as `idle` and
  proceed (a new run is valid after completion).

---

## Step 2: Record --until Cutoff (if provided)

For v0.6 simplification: log the cutoff intent to `.claude/agentic/decisions.log`
rather than enforcing it via state.schema. Do not block on schema enforcement.

If `--until` was parsed successfully:

```
Append to .claude/agentic/decisions.log:
<ISO timestamp> | start --until <value> | target_cutoff_at=<resolved-cutoff-ISO> | notes=run-start
```

Note: `target_cutoff_at` is a new optional field for v0.6. Future schema bumps
may formalize it in `state.schema.json`. For now, the cutoff is recorded in
decisions.log only and is advisory — the orchestrator does not yet enforce it
hard-stop; it serves as a log of the operator's intent.

---

## Step 3: Transition Circuit Breaker to Running

```bash
bin/circuit-breaker.sh running
```

This marks the queue as actively being driven.

---

## Step 4: Invoke the Orchestrator

```
/agentic-dev:_run-orchestrator
```

Delegate all queue-loop logic to the internal orchestrator. This skill waits for
the orchestrator to return (after the queue is exhausted, halted, or the first
wake-up cycle completes).

---

## Step 5: Print Final Summary

On return from `_run-orchestrator`, print a structured final summary:

```
agentic-dev:start — run summary

  circuit breaker:    <state.circuit_breaker.state>
  goals completed:    <count of completed goals (from queue.yaml)>
  goals halted:       <count of halted goals>
  goals remaining:    <count of approved goals still pending>

  <If halted:>
  HALTED — run /agentic-dev:resume <decision> to continue.

  <If idle/queue empty:>
  Queue exhausted — all approved goals processed.
```

Exit with the same code as `_run-orchestrator`:
- **exit 0** if queue completed cleanly or became idle.
- **exit 1** if a goal halted the circuit breaker.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `exit 0` | Queue ran cleanly (exhausted or idle). |
| `exit 1` | A goal halted the circuit breaker. Run `/agentic-dev:resume` to proceed. |

---

## Do NOT

- **Do NOT** invoke `_advance-goal` directly. Delegate to `_run-orchestrator`.
- **Do NOT** clear or skip a halted circuit breaker. Only `/agentic-dev:resume`
  may do this.
- **Do NOT** enforce the `--until` cutoff by killing the orchestrator mid-run in v0.6.
  The cutoff is logged as intent only; enforcement is deferred to v0.7.
- **Do NOT** start a run if the circuit breaker is `halted`. Always surface the halt
  and suggest `/agentic-dev:resume`.
