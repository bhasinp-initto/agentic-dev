---
description: Internal orchestrator step. Runs one approved goal end-to-end (implementer → gates → reviewer → routing). Handles the auto-fix loop (cap 3 rounds) for any reviewer concerns (mechanical OR judgment) — escalates only when verdict is blocking or auto-fix is exhausted. Updates queue + circuit-breaker state. Cleans up worktree on clean completion; halts circuit breaker on any blocking failure.
---

# `_advance-goal` — Single-Goal Pipeline Orchestrator

## Overview

This is an internal skill invoked by `_run-orchestrator`. It drives a single approved goal
through the full pipeline: implementer → gates → reviewer, with auto-fix loop for mechanical
concerns, state-machine transitions, and either a clean path or halt path outcome.

**Do NOT invoke this skill directly from user-facing commands.** Use `/agentic-dev:start`
or `/agentic-dev:_run-orchestrator` instead.

---

## $ARGUMENTS

```
$ARGUMENTS = <goal-id>
```

The first (and only) argument is the goal ID to advance. If $ARGUMENTS is empty or
unrecognised, **refuse** immediately:

```
ERROR: _advance-goal requires a goal ID as its first argument.
Usage: /agentic-dev:_advance-goal <goal-id>
```

Exit 1 on empty or missing argument — do not proceed.

---

## Pre-checks

Before beginning any state transition, verify:

1. `.claude/agentic/queue.yaml` exists and contains the given `<goal-id>`.
2. The goal's `status=approved`. If the status is anything other than `approved`
   (e.g., `running`, `completed`, `halted`, `drafted`), refuse:
   ```
   ERROR: Goal <id> has status=<actual> — only approved goals can be advanced.
   ```
   Exit 1 without modifying any file.

3. The spec file referenced in the goal entry exists on disk.

---

## State Transition: Mark Running

Capture the current HEAD commit as `baseline_ref` using:

```bash
git rev-parse HEAD
```

Then transition the goal to `running`:

```bash
bin/queue-set-status.sh <id> running \
  started_at=<current-UTC-timestamp> \
  baseline_ref=<sha-from-git-rev-parse>
```

If `queue-set-status.sh` exits non-zero (e.g., schema validation failure),
enter the **halt path** immediately — the queue is in an inconsistent state.

---

## Step 1: Implementer Dispatch

Invoke the implementer sub-skill with the goal's spec path:

```
/agentic-dev:_run-implementer <spec-path>
```

The spec path is read from the queue entry (field: `spec_path`).

**Failure handling:** If `_run-implementer` exits non-zero, enter the **halt path**.
The implementer may have produced partial artifacts; do not attempt to continue.

---

## Step 2: Gates Dispatch

Invoke the gates sub-skill:

```
/agentic-dev:_run-gates <id>
```

`_run-gates` writes a gate verdict to `.claude/agentic/verdicts/<id>.json`.

**Failure handling:** If `_run-gates` reports overall=fail or exits non-zero,
enter the **halt path**. `_run-gates` already generates the escalation packet and
Telegram notification — do not re-generate them here.

---

## Step 3: Reviewer Dispatch

Invoke the reviewer sub-skill:

```
/agentic-dev:_run-reviewer <id>
```

`_run-reviewer` writes a reviewer verdict to `.claude/agentic/reviewer-verdicts/<id>.json`.

After `_run-reviewer` returns, **route on outcome** (§ Routing below).

---

## Routing on Reviewer Outcome

Inspect the following after `_run-reviewer` returns:

### A. No auto-fix-queue file (`.claude/agentic/auto-fix-queue/<id>.json` absent)

Reviewer returned clean. Enter the **clean path**.

### B. auto-fix-queue file exists (any concerns — verdict was concern, not blocking)

Enter the **auto-fix loop** (see below). The queue may contain mechanical, judgment, or uncategorized concerns — the implementer will receive them all as guidance and attempt to address them.

### C. `_run-reviewer` exits 1

Reviewer escalated a blocking or judgment concern. `_run-reviewer` already generated
the escalation packet and notified via Telegram. Enter the **halt path**.

---

## Auto-Fix Loop (cap 3 rounds)

When `.claude/agentic/auto-fix-queue/<id>.json` exists after a reviewer pass, the file
contains a list of reviewer concerns of any category (mechanical, judgment, or uncategorized).
The implementer is dispatched again with the concerns as explicit fix guidance — categories
are passed as informational metadata so the implementer applies the right kind of fix
(judgment concerns get more careful treatment, mechanical concerns get straightforward
remediation).

**Hard cap:** max 3 rounds (bumped from 2 in 1.1.0 — judgment concerns often need an extra
pass for the implementer to converge). Track rounds in a local counter starting at 0;
increment before each auto-fix dispatch.

### Loop body (for each round):

1. Read `.claude/agentic/auto-fix-queue/<id>.json` — parse the `concerns` array.
2. Re-dispatch implementer with an addendum that includes the concerns AND their categories:

   ```
   /agentic-dev:_run-implementer <spec-path>
   ```

   The skill must construct the dispatch prompt to include an addendum of the form:

   > Address these concerns from review (round <N> of 3). Categories indicate the
   > nature of each issue — apply the appropriate kind of fix:
   >
   > 1. [<category>] <file>:<line> — <concern description>
   > 2. [<category>] <file>:<line> — <concern description>
   > ...
   >
   > Notes:
   > - `mechanical`: lint nits, missing tests, dead code, formatting → direct fix.
   > - `judgment`: security flaw, scope deviation, design choice with a clear remediation
   >   → apply the obvious fix when possible; if the fix requires changing the spec or
   >   making a value trade-off you don't have authority for, record a
   >   `spec_change_request` in your manifest rather than guessing.
   > - `uncategorized`: read the description carefully and judge whether it's mechanical
   >   or needs spec input.

3. Re-run gates:
   ```
   /agentic-dev:_run-gates <id>
   ```
   If gates fail → **halt path** (do not continue the loop).

4. Re-run reviewer:
   ```
   /agentic-dev:_run-reviewer <id>
   ```

5. After reviewer returns:
   - If auto-fix-queue file is absent (or empty) → **clean path** (exit loop).
   - If reviewer exits 1 (verdict was blocking, OR `_run-reviewer` short-circuited because of new gate failures) → **halt path** (exit loop).
   - If auto-fix-queue still present and `rounds < 3` → increment `rounds`, next iteration.
   - If `rounds == 3` and auto-fix-queue still present → escalate as `auto_fix_exhausted`.

### Exhaustion (rounds == 3 and still concerns):

Set `halted_reason = auto_fix_exhausted` and enter the **halt path**:

```bash
bin/queue-set-status.sh <id> halted halted_at=<now>
bin/circuit-breaker.sh halted \
  halted_reason="auto_fix_exhausted" \
  halted_goal_id=<id>
```

The escalation packet should note that 3 rounds of auto-fix were attempted and the reviewer
still found unresolved concerns. Exit 1.

---

## Clean Path (success)

When the reviewer returns clean with no auto-fix-queue file (either on the primary pass or
after a successful auto-fix round):

1. Capture final HEAD:
   ```bash
   git rev-parse HEAD
   ```

2. Transition goal to completed:
   ```bash
   bin/queue-set-status.sh <id> completed \
     completed_at=<current-UTC-timestamp> \
     head_ref=<final-sha> \
     manifest_path=.claude/agentic/manifests/<id>.json
   ```

3. Clean up the worktree:
   ```bash
   bin/cleanup-completed-goal.sh <id>
   ```

4. Send a success digest notification:
   ```bash
   bin/telegram-notify.sh digest "Goal <id> completed cleanly"
   ```

5. Exit 0.

---

## Halt Path (any failure)

Entered on any of:
- Empty or invalid $ARGUMENTS
- Pre-check failure (goal not found or status != approved)
- queue-set-status.sh failure on transition to running
- `_run-implementer` exits non-zero
- `_run-gates` reports failure / exits non-zero
- `_run-reviewer` exits 1
- auto_fix_exhausted (rounds == 2 and concerns remain)

## Auto-append memory entry (per umbrella §13)

On the halt path, before exiting, call:

`bin/log-incident.sh memory observation="Goal <goal-id> halted: <halt reason>" consequence="Escalation packet generated; review and human-resume needed"`

This builds the cross-session memory that future spec-drafter dispatches will read. Failure to append is logged but does not block (P7-L4).

### Halt procedure:

1. Transition goal to halted (include head_ref + manifest_path if already populated):
   ```bash
   bin/queue-set-status.sh <id> halted \
     halted_at=<current-UTC-timestamp> \
     [head_ref=<sha>] \
     [manifest_path=<path>]
   ```

2. Trip the circuit breaker:
   ```bash
   bin/circuit-breaker.sh halted \
     halted_reason="<descriptive reason for the halt>" \
     halted_goal_id=<id>
   ```
   Use descriptive `halted_reason` values such as:
   - `implementer_failed`
   - `gate_failure`
   - `reviewer_escalated`
   - `auto_fix_exhausted`
   - `queue_transition_error`

3. **Do NOT** re-generate escalation packets or Telegram notifications — these are produced
   by the upstream sub-skill (`_run-gates`, `_run-reviewer`) that triggered the failure.

4. Exit 1.

---

## Do NOT

- **Do NOT** modify the goal's spec file, manifest file, gate verdict, reviewer verdict,
  or any escalation packet. This skill is orchestration-only.
- **Do NOT** run `bin/cleanup-completed-goal.sh` on halted goals. The worktree is preserved
  for forensic investigation.
- **Do NOT** continue past a halt. Once a failure is detected and the halt procedure is
  invoked, exit 1 immediately — do not attempt to advance to the next goal or retry
  outside the defined auto-fix loop.
- **Do NOT** increment the auto-fix rounds counter beyond the cap of 2 rounds.
- **Do NOT** de-escalate the circuit breaker. Only `/agentic-dev:resume` (human-invoked)
  may reset circuit-breaker state from halted.
- **Do NOT** invoke `/agentic-dev:_run-orchestrator` recursively from within this skill.
  Return cleanly (exit 0 or exit 1) and let the orchestrator decide the next step.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `exit 0` | Goal advanced cleanly to `completed`; worktree cleaned up; digest sent. |
| `exit 1` | Goal halted; circuit breaker tripped; caller must not continue the queue. |

---

## State Summary

| Event | queue.yaml status | circuit_breaker |
|-------|-------------------|----------------|
| Start | `approved` → `running` (+ `started_at`, `baseline_ref`) | unchanged |
| Clean | `running` → `completed` (+ `completed_at`, `head_ref`, `manifest_path`) | unchanged (stays running) |
| Halt  | `running` → `halted` (+ `halted_at`) | `running` → `halted` |
