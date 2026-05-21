---
description: Internal lifecycle skill. Dispatches the hardened-reviewer subagent on a goal that passed gates, runs reviewer-adversary on clean verdicts, routes concerns by category, generates escalation packets + Telegram notifications when warranted. Does NOT drive the auto-fix loop (P6 does).
---

# /agentic-dev:_run-reviewer

You are the lifecycle skill that dispatches AI review for one goal after P4's deterministic gates have completed. You dispatch the hardened-reviewer subagent, validate its output, run the reviewer-adversary on clean verdicts, route concerns by category, and generate escalation packets + Telegram notifications when warranted.

**Internal skill** — the underscore prefix (`_run-reviewer`) signals that this skill is not for direct human invocation in the normal agentic-dev workflow. It is dispatched by the orchestrator (P6+) or used directly during P5 development.

---

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the goal-id (e.g., `2026-05-21-add-health-endpoint`). If empty or missing, refuse:

```
agentic-dev: /agentic-dev:_run-reviewer requires a goal-id.
Example: /agentic-dev:_run-reviewer 2026-05-21-add-health-endpoint
```

Do not proceed with an empty `$ARGUMENTS`.

---

## Pre-checks

Before dispatching the reviewer, verify all required artifacts exist:

1. **Manifest exists** at `.claude/agentic/manifests/<goal-id>.json`. If not, refuse:
   ```
   agentic-dev: manifest not found for goal <goal-id>; cannot run reviewer.
   Expected: .claude/agentic/manifests/<goal-id>.json
   ```

2. **Gate verdict exists** at `.claude/agentic/verdicts/<goal-id>.json` — required; P4 must have run first. If not, refuse:
   ```
   agentic-dev: gate verdict not found for goal <goal-id>; run _run-gates first.
   Expected: .claude/agentic/verdicts/<goal-id>.json
   ```

3. **Diff envelope exists** at `.claude/agentic/diffs/<goal-id>.json` — required when manifest's `head_ref` is not null. Read the manifest first; if `head_ref` is non-null and the diff envelope is missing, refuse:
   ```
   agentic-dev: diff envelope not found for goal <goal-id>; expected at .claude/agentic/diffs/<goal-id>.json
   ```

4. **Spec exists** at the path given by `manifest.spec_path`. If not, refuse:
   ```
   agentic-dev: spec not found at <spec_path> (from manifest); cannot run reviewer.
   ```

---

## Gate-failure short-circuit

Read the gate verdict from `.claude/agentic/verdicts/<goal-id>.json`.

If `overall == "fail"` and `blocking_failures` is a non-empty array, **skip the reviewer entirely**:

1. Call `bin/generate-escalation.sh <goal-id> gate_failure`
2. Call `bin/telegram-notify.sh blocking "Goal <goal-id> blocked by deterministic gates"`
3. Print the escalation packet path and a summary of blocking failures
4. Exit 1

There is no point dispatching AI judgment when deterministic gates already failed. The AI reviewer cannot override a gate failure.

---

## Dispatch the hardened-reviewer subagent

If the gate verdict's `overall` is not `"fail"` (i.e., it is `"pass"` or `"warning"`), dispatch the hardened-reviewer subagent via the **Agent tool** with `subagent_type: hardened-reviewer`.

Construct the prompt:

```
You are dispatched as hardened-reviewer for goal <goal_id>.

Read these files:
  Spec:          <absolute spec_path>
  Manifest:      <absolute .claude/agentic/manifests/<goal-id>.json>
  Diff envelope: <absolute .claude/agentic/diffs/<goal-id>.json>
  Gate verdict:  <absolute .claude/agentic/verdicts/<goal-id>.json>

The manifest contains structured fields only — no implementer prose by design.
Apply both judgment dimensions from your calibration:
  1. Spec compliance: does the diff actually implement what the spec requires?
  2. Risk detection: does it introduce security smells, hard-coded secrets, dependency drift, or out-of-spec creep?

Categorize each concern:
  - mechanical: coverage gap, lint nit, missing test edge case
  - judgment: architectural choice, security risk, scope drift
  - uncategorized: when in doubt — uncategorized is valid

Output a single JSON object matching reviewer-verdict.schema.json with reviewer_role: "primary".
No preamble. No code fences. Just JSON.
```

---

## Capture and validate the JSON response

After the Agent tool completes, capture the subagent's response text.

Use Python + jsonschema to validate the response against `agentic-dev/schemas/reviewer-verdict.schema.json`.

**On malformed or invalid JSON output:**
1. Write the raw response to `.claude/agentic/reviewer-verdicts/<goal-id>.raw.txt`
2. Write a stub verdict to `.claude/agentic/reviewer-verdicts/<goal-id>.json`:
   ```json
   {
     "schema_version": "0.1",
     "goal_id": "<goal-id>",
     "reviewer_role": "primary",
     "reviewed_at": "<ISO timestamp>",
     "verdict": "blocking",
     "concerns": [
       {
         "file": "_meta",
         "line": 0,
         "severity": "blocking",
         "category": "uncategorized",
         "description": "Reviewer returned malformed output"
       }
     ],
     "checks_run": []
   }
   ```
3. Log the error to `.claude/agentic/validation-log.txt` with ISO timestamp

**On valid output:**
Write the validated JSON to `.claude/agentic/reviewer-verdicts/<goal-id>.json`.

---

## Route on verdict

### `verdict: "clean"` → dispatch reviewer-adversary

Dispatch a second-pass review via the Agent tool with `subagent_type: reviewer-adversary`.

Prompt:

```
You are dispatched as reviewer-adversary for goal <goal_id>.

The primary reviewer marked this clean. Your job is to find what they missed.

Read these files:
  Spec:             <absolute spec_path>
  Manifest:         <absolute .claude/agentic/manifests/<goal-id>.json>
  Diff envelope:    <absolute .claude/agentic/diffs/<goal-id>.json>
  Primary verdict:  <absolute .claude/agentic/reviewer-verdicts/<goal-id>.json>

Apply adversarial second-pass scrutiny.
Output a single JSON object matching reviewer-verdict.schema.json with reviewer_role: "adversary".
No preamble. No code fences. Just JSON.
```

Capture and validate the adversary's JSON output (same malformed-output handling pattern). Write to `.claude/agentic/reviewer-verdicts/<goal-id>.adversary.json`.

**If the adversary verdict is also `clean`:**
- Print: `Goal <goal-id> clean (primary + adversary)`
- Call `bin/telegram-notify.sh digest "Goal <goal-id> passed primary + adversary review"` (queue-completion bookkeeping)
- Exit 0

**If the adversary finds concerns:**
- Treat those concerns as if they came from the primary reviewer
- Route per the concern routing rules below (see `verdict: "concern"`)

---

## Auto-append checklist entries (per umbrella §13)

Before generating the escalation packet, for EACH judgment or uncategorized concern that's triggering this escalation, call:

`bin/log-incident.sh checklist rule="<concern.description>" caught_by="reviewer" incident_ref="<escalation packet path>"`

This builds the cross-session checklist that future hardened-reviewer dispatches will read. If `log-incident.sh` fails (e.g., schema validation, file lock), log to validation-log.txt and continue — auto-append must never block the pipeline (P7-L4).

For blocking verdicts: same pattern, `caught_by="reviewer"`.
For adversary concerns (second-pass): `caught_by="adversary"`.

### `verdict: "concern"` → route by category

Iterate over all concerns in the verdict. For each concern, check its `category` field.

**Collect concerns by category:**
- `mechanical` concerns → candidates for the auto-fix loop (P6 will drive this)
- `judgment` and `uncategorized` concerns → must escalate to human

**Decision logic:**

If there are any `judgment` or `uncategorized` concerns (or if there are no `mechanical` concerns and all concerns escalate):
1. Call `bin/generate-escalation.sh <goal-id> judgment_concerns`
2. Call `bin/telegram-notify.sh warning "Goal <goal-id> has judgment concerns requiring human review"`
   - Note: `warning` severity, not `blocking` — judgment concerns are routine, not a 2am wake-up call.
3. Exit 1

If there are ONLY `mechanical` concerns (zero judgment / uncategorized):
1. Write the auto_fix_candidates to `.claude/agentic/auto-fix-queue/<goal-id>.json` as a JSON array of the mechanical concern objects
2. Print: `Goal <goal-id>: <N> mechanical concerns; P6 will drive auto-fix loop`
3. Exit 0

Note: v0.5 does not yet integrate with P3's implementer for the actual auto-fix iteration — that is P6 territory.

---

### `verdict: "blocking"` → immediate escalation

1. Call `bin/generate-escalation.sh <goal-id> reviewer_blocking`
2. Call `bin/telegram-notify.sh blocking "Goal <goal-id> has blocking reviewer concerns"`
3. Exit 1

---

## Output

Print a structured summary after routing:

```
agentic-dev: reviewer run complete

  goal:              <goal-id>
  manifest:          .claude/agentic/manifests/<goal-id>.json
  gate verdict:      .claude/agentic/verdicts/<goal-id>.json
  reviewer verdict:  .claude/agentic/reviewer-verdicts/<goal-id>.json
  adversary verdict: .claude/agentic/reviewer-verdicts/<goal-id>.adversary.json (if applicable)

  verdict:           <clean|concern|blocking>
  routing decision:  <clean (both passes) | N mechanical concerns queued | escalated (judgment) | escalated (blocking)>
  escalation packet: <path or "n/a">
```

---

## Do NOT

- Do NOT modify the spec, manifest, gate verdict, or any goal file.
- Do NOT clean up the worktree — that is the orchestrator's job (P6+).
- Do NOT update queue.yaml — that is the orchestrator's job.
- Do NOT invoke another skill (no nested skill calls).
- Do NOT drive the auto-fix loop — P6 owns iteration over mechanical concerns.
- Do NOT push anything to the remote.

---

## Lifecycle context

```
P3: _run-implementer → manifest at .claude/agentic/manifests/<goal-id>.json
P4: _run-gates       → gate verdict at .claude/agentic/verdicts/<goal-id>.json
P5: _run-reviewer    → reviewer verdict at .claude/agentic/reviewer-verdicts/<goal-id>.json
                     → adversary verdict at .claude/agentic/reviewer-verdicts/<goal-id>.adversary.json
                     → escalation packet at .claude/agentic/escalations/<timestamp>-<goal-id>.md (if warranted)
                     → auto-fix queue at .claude/agentic/auto-fix-queue/<goal-id>.json (if only mechanical)
P6: orchestrator reads routing decision; drives auto-fix loop or advances
```
