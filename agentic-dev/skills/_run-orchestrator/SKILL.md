---
description: Internal queue loop. Picks the first approved goal; advances it via /agentic-dev:_advance-goal; on success, schedules the next wake-up via ScheduleWakeup. On halt, exits with circuit breaker locked.
---

# `_run-orchestrator` — Queue Loop Orchestrator

## Overview

This is an internal skill that drives the approved-goal queue end-to-end.
It is invoked by `/agentic-dev:start` and re-invoked by ScheduleWakeup after each
goal completes. It picks the first `approved` goal, delegates to `_advance-goal`,
and either schedules the next wake-up (clean) or locks the circuit breaker (halted).

**Do NOT invoke this skill directly for routine use.** Use `/agentic-dev:start` to
begin a queue run.

---

## $ARGUMENTS

This skill takes no arguments. Any tokens in `$ARGUMENTS` are ignored — the skill
always operates on the first `approved` goal found in `queue.yaml`.

---

## Step 1: Pre-check — Circuit Breaker State

Read `.claude/agentic/state.json` and inspect `circuit_breaker.state`.

- **Allowed states:** `idle`, `running` — proceed to Step 2.
- **`halted`** — refuse with:
  ```
  ERROR: Queue is halted (circuit_breaker.state = halted).
  Halted goal: <circuit_breaker.halted_goal_id>
  Reason:      <circuit_breaker.halted_reason>
  Run /agentic-dev:resume <decision> to proceed.
  ```
  Exit 1.
- **`completed`** — refuse with:
  ```
  INFO: Queue run has already completed (circuit_breaker.state = completed).
  Run /agentic-dev:start to begin a new run.
  ```
  Exit 0.

---

## Step 2: Find First Approved Goal

Read `.claude/agentic/queue.yaml`. Iterate goals in insertion order.
Find the first goal whose `status` field equals `approved`.

- **If an approved goal is found:** proceed to Step 3.
- **If no approved goal found:** proceed to Step 4 (queue idle / empty handling).

---

## Step 3: Transition Circuit Breaker to Running (if idle)

If `circuit_breaker.state == idle`, transition it to `running`:

```bash
bin/circuit-breaker.sh running
```

This marks the orchestrator as actively driving the queue.
If `circuit_breaker.state` is already `running`, skip this step.

---

## Step 4: Queue Idle / Empty Handling

If no `approved` goal exists in `queue.yaml`:

1. Count goals by status:
   - `drafted_count` = number of goals with `status=drafted`
   - `intent_only_count` = number of goals with `status=intent_only`
   - `pending_count` = `drafted_count` + `intent_only_count`

2. If `pending_count > 0`:
   ```
   Queue idle (N drafts awaiting approval).
   Goals needing human approval: <list goal IDs with drafted/intent_only status>
   ```
   Exit 0.

3. If `pending_count == 0` and queue is entirely empty:
   ```
   Queue empty. No goals to run.
   ```
   Exit 0.

If the circuit breaker was `running` at the time the queue became empty, transition
it back to `idle` (queue exhausted cleanly, ready for more work):

```bash
bin/circuit-breaker.sh idle
```

---

## Step 5: Advance the Goal

Invoke the single-goal pipeline:

```
/agentic-dev:_advance-goal <goal-id>
```

Where `<goal-id>` is the ID of the first `approved` goal found in Step 2.

---

## Step 6: Route on Exit Code

### Exit 0 (goal completed cleanly)

The goal advanced to `completed`. Schedule the next wake-up using the
ScheduleWakeup tool with a 30-second delay so the next approved goal picks up:

```
ScheduleWakeup(
  delaySeconds=30,
  prompt="/agentic-dev:_run-orchestrator"
)
```

Print:
```
Goal <goal-id> completed cleanly. Next wake-up scheduled in 30s.
```

Exit 0.

### Exit 1 (goal halted)

`_advance-goal` has already called `circuit-breaker.sh halted` and set the
`halted_goal_id` and `halted_reason` fields in `state.json`. Print a summary:

```
HALTED: Goal <goal-id> failed — circuit breaker is locked.
Reason: <circuit_breaker.halted_reason>
Run /agentic-dev:resume <decision> to proceed.
```

Do NOT schedule another wake-up — the circuit breaker is locked and will refuse
any subsequent `_run-orchestrator` invocations until a human resets it via
`/agentic-dev:resume`.

Exit 1.

---

## Do NOT

- **Do NOT** modify any spec file, manifest, gate verdict, reviewer verdict, or
  escalation packet. This skill is orchestration-only; it only reads `queue.yaml`
  and `state.json`, and dispatches `_advance-goal`.
- **Do NOT** attempt to advance a `running`, `completed`, `halted`, or `drafted`
  goal. Only `approved` goals are eligible for advancement.
- **Do NOT** clear or reset the circuit breaker from `halted`. Only
  `/agentic-dev:resume` (human-invoked) may do this.
- **Do NOT** schedule a wake-up if `_advance-goal` exits 1. A locked circuit
  breaker will refuse the next orchestrator invocation anyway.
- **Do NOT** run more than one goal per invocation. Each invocation processes
  exactly one goal, then either schedules the next wake-up (exit 0) or halts.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `exit 0` | Goal completed (wake-up scheduled) OR queue idle/empty (no work to do). |
| `exit 1` | Goal halted; circuit breaker is locked. Human action required. |

---

## Wake-Up Cadence

The default delay between goals is **30 seconds** (30s). This is controlled by the
`delaySeconds=30` parameter passed to ScheduleWakeup. Per design §22, this cadence
is intentionally short (overnight multi-goal runs benefit from minimal dead-time
between goals).

---

## State Summary

| Event | circuit_breaker.state |
|-------|----------------------|
| Start (was idle) | `idle` → `running` |
| Goal clean | stays `running` |
| Queue exhausted | `running` → `idle` |
| Goal halted | `running` → `halted` (set by `_advance-goal`) |
| Pre-check: already halted | refuse, exit 1 |
| Pre-check: already completed | refuse, exit 0 |
