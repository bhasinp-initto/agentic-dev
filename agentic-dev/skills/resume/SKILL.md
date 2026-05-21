---
description: Public skill. After a halt, decide how to proceed: resume | skip | address | replan | abort. Logs the decision to decisions.log and resets circuit breaker accordingly.
---

# `/agentic-dev:resume` — Post-Halt Decision Handler

## Overview

This is the public skill for handling a halted queue run. It accepts a human
decision, logs it to `.claude/agentic/decisions.log`, applies the appropriate
state transition, and either re-enables the queue (via circuit-breaker.sh idle)
or stops it (via circuit-breaker.sh completed).

Only a human can clear a halted circuit breaker. This skill is that gateway.

---

## $ARGUMENTS

```
$ARGUMENTS = <decision> [context...]
```

- First token: the decision (required). One of: `resume`, `skip`, `address`, `replan`, `abort`.
- Remaining tokens: freeform context / notes (optional, used for `address` decision).

### Parsing $ARGUMENTS

1. If `$ARGUMENTS` is empty → refuse:
   ```
   ERROR: /agentic-dev:resume requires a decision argument.
   Usage: /agentic-dev:resume <resume|skip|address|replan|abort> [context]
   ```
   Exit 1.

2. Extract first token as `<decision>`.
3. If `<decision>` is not one of the five valid values → refuse with the same usage error.
4. Remaining tokens (if any) = `<notes>`.

---

## Step 1: Pre-check — Circuit Breaker Must Be Halted

Read `.claude/agentic/state.json`.

- If `circuit_breaker.state != halted` → refuse:
  ```
  ERROR: Circuit breaker is not halted (current state: <state>).
  /agentic-dev:resume is only valid when the queue is halted.
  ```
  Exit 1.

- If `circuit_breaker.state == halted` → proceed.

---

## Step 2: Identify the Halted Goal

Read `circuit_breaker.halted_goal_id` from `state.json`.

Verify the goal exists in `.claude/agentic/queue.yaml`. If not found → print a
warning but continue (state.json may be out of sync; the decision is still logged).

Let `GOAL_ID = circuit_breaker.halted_goal_id`.

---

## Step 3: Log the Decision

Append a single line to `.claude/agentic/decisions.log`:

```
<ISO timestamp> | <decision> | <GOAL_ID> | <notes>
```

Format:
- `<ISO timestamp>` — current UTC time in ISO 8601 format (e.g. `2026-05-21T14:32:00Z`)
- `<decision>` — the decision token (resume / skip / address / replan / abort)
- `<GOAL_ID>` — the halted goal ID from state.json
- `<notes>` — freeform text from $ARGUMENTS remainder, or empty string

Create the file if it does not yet exist. Append only — never truncate decisions.log.

---

## Step 4: Apply Decision

### `resume`

Re-approve the halted goal and unlock the circuit breaker:

```bash
bin/queue-set-status.sh <GOAL_ID> approved
bin/circuit-breaker.sh idle
```

Print:
```
Goal <GOAL_ID> re-approved. Circuit breaker reset to idle.
Run /agentic-dev:start to continue the queue.
```

Exit 0.

---

### `skip`

Mark the halted goal as abandoned and unlock the circuit breaker:

```bash
bin/queue-set-status.sh <GOAL_ID> abandoned
bin/circuit-breaker.sh idle
```

Print:
```
Goal <GOAL_ID> abandoned. Circuit breaker reset to idle.
Run /agentic-dev:start to continue the queue with the next approved goal.
```

Exit 0.

---

### `address <text>`

The `<text>` is the freeform concern-resolution context from $ARGUMENTS remainder.

Log it (already done in Step 3 via `<notes>`). Then re-approve and unlock:

```bash
bin/queue-set-status.sh <GOAL_ID> approved
bin/circuit-breaker.sh idle
```

Print:
```
Goal <GOAL_ID> re-approved with address note: "<text>"
Circuit breaker reset to idle.
Run /agentic-dev:start to continue the queue.
```

Exit 0.

---

### `replan`

Mark the halted goal's spec as needing rework and set it back to drafted:

1. Read the `spec_path` field from the goal entry in `queue.yaml`.
2. Use the Edit tool to update the spec at `<spec_path>`: set `approved: false`
   (or equivalent field per spec schema). This signals that the spec needs review
   before the goal can be re-queued.
3. Transition goal status to drafted:
   ```bash
   bin/queue-set-status.sh <GOAL_ID> drafted
   ```
4. Reset the circuit breaker to idle:
   ```bash
   bin/circuit-breaker.sh idle
   ```

Print:
```
Goal <GOAL_ID> set to drafted. Spec at <spec_path> requires revision.
Circuit breaker reset to idle.
Re-run /agentic-dev:intent --refine <spec_path> to address and re-approve.
```

Exit 0.

---

### `abort`

Stop the entire queue run. No further goals are processed.

```bash
bin/circuit-breaker.sh completed
```

Do NOT change the halted goal's queue status — it remains `halted` as a forensic
record. The circuit breaker state `completed` signals that the operator has chosen
to end this queue run entirely.

Print:
```
Queue run aborted. Circuit breaker set to completed.
Goal <GOAL_ID> remains halted for forensic review.
Run /agentic-dev:start to begin a fresh queue run when ready.
```

Exit 0.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `exit 0` | Decision applied; state updated; decisions.log appended. |
| `exit 1` | Pre-check failed (not halted, bad decision, missing goal ID). |

---

## Do NOT

- **Do NOT** run if the circuit breaker is not halted. This skill is only valid
  in the `halted` state.
- **Do NOT** apply any decision other than the five defined ones. Unknown decisions
  are refused.
- **Do NOT** truncate or overwrite decisions.log — only append.
- **Do NOT** delete escalation packets, manifests, or gate verdicts for the halted
  goal. These are preserved for forensic review regardless of decision.
- **Do NOT** invoke `_run-orchestrator` or `_advance-goal` from this skill.
  After resetting the circuit breaker, instruct the user to run `/agentic-dev:start`.
- **Do NOT** auto-start the queue after applying the decision. Human confirmation
  via `/agentic-dev:start` is required.

---

## State Summary

| Decision | Goal Status After | circuit_breaker After |
|----------|------------------|-----------------------|
| `resume` | `approved` | `idle` |
| `skip` | `abandoned` | `idle` |
| `address` | `approved` | `idle` |
| `replan` | `drafted` | `idle` |
| `abort` | `halted` (unchanged) | `completed` |
