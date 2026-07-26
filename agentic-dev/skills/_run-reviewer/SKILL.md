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

## Pre-dispatch: query the checklist for relevant past incidents (1.5.0+)

Before dispatching the reviewer, query `.claude/agentic/checklist.yaml` for past-incident rules most relevant to THIS goal. Use the Bash tool:

```bash
# Build a query string from the spec body excerpt + diff envelope's raw_patch excerpt.
# Truncate each to ~2000 chars to keep the bash arg manageable.
QUERY="$(head -c 2000 <spec_path>)$(python3 -c '
import json
diff = json.load(open(".claude/agentic/diffs/<goal-id>.json"))
print(diff.get("raw_patch", "")[:2000])
')"

# Query for top-5 relevant entries
${CLAUDE_PLUGIN_ROOT}/bin/query-checklist.sh "$QUERY" -k 5
```

If the helper returns one or more JSONL lines, format them as a `Relevant past incidents` section in the dispatch prompt (see template below). If it returns nothing (empty checklist, or no token overlap with the query), skip the section — the reviewer's prompt simply won't have it.

If `bin/query-checklist.sh` exits non-zero or fails to run (e.g., checklist.yaml missing in a fresh project): log to `validation-log.txt` and proceed without the section. **Query failure must NEVER block the dispatch** — the reviewer can still review without the pre-filtered hints.

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

Relevant past incidents (top 5 from checklist.yaml, ranked by similarity to the spec + diff):
  [Only include this section if query-checklist.sh returned >=1 entry]
  1. [<caught_by>] <rule>  (ESC ref: <incident_ref>, score: <score>)
  2. ...
  ...

The manifest contains structured fields only — no implementer prose by design.
Apply both judgment dimensions from your calibration:
  1. Spec compliance: does the diff actually implement what the spec requires?
  2. Risk detection: does it introduce security smells, hard-coded secrets, dependency drift, or out-of-spec creep?

Categorize each concern:
  - mechanical: code-fixable, including security with clear remediation
  - judgment: requires spec change or value trade-off
  - uncategorized: when in doubt — but try to classify first

Output a single JSON object matching reviewer-verdict.schema.json with reviewer_role: "primary".
No preamble. No code fences. Just JSON.
```

Same `Relevant past incidents` section is also injected into the reviewer-adversary dispatch prompt below.

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

#### Augment with Codex (2.0.0+)

After the Claude adversary verdict is captured, optionally augment it with a
second, independent-model adversary (Codex). This is **pure upside** — any
failure falls back to the Claude adversary result and **never blocks**.

1. **Read the toggle.** From `.claude/agentic/config.yaml`, read
   `review.codex_adversary`. If the `review` block is **absent** or the value is
   `off`, skip this entire subsection and proceed with the Claude adversary
   verdict unchanged (today's behavior).

2. **Preflight.** Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex-bridge.sh preflight
   ```
   Parse the JSON. If `ready` is not `true`, log
   `codex adversary: skipped (<reason_code>)` to
   `.claude/agentic/validation-log.txt`, note it in the final summary, and
   proceed with the Claude adversary verdict unchanged.

3. **Gather preconditions** from the manifest (`.claude/agentic/manifests/<goal-id>.json`)
   and diff envelope (`.claude/agentic/diffs/<goal-id>.json`):
   - `worktree_path` — the manifest's `worktree_path` (authoritative worktree).
   - `expected_head` — the manifest's `head_ref`.
   - `base_sha` — the diff envelope's base ref.

4. **Run the Codex adversary:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex-bridge.sh review \
     "<goal-id>" "<base_sha>" "<worktree_path>" "<expected_head>"
   ```
   The bridge always exits 0 and prints EITHER an adapted reviewer-verdict OR a
   `{"skipped":true,"reason_code":...}` object. If `skipped` is present: log
   `codex adversary: skipped (<reason_code>)` to `validation-log.txt`, note it in
   the summary, and proceed with the Claude adversary verdict unchanged.
   Otherwise write the adapted verdict to
   `.claude/agentic/reviewer-verdicts/<goal-id>.codex.json` and the raw companion
   `.result` (if you captured it) to `<goal-id>.codex.raw.json`.

5. **Merge into one aggregate verdict** (route ONCE on the aggregate — do not
   route each source separately):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex_adapter.py merge \
     ".claude/agentic/reviewer-verdicts/<goal-id>.adversary.json" \
     ".claude/agentic/reviewer-verdicts/<goal-id>.codex.json"
   ```
   This prints `{"verdict": <aggregate>, "concerns": [...]}`. The `merge` helper
   prefixes Claude concerns with `[claude-adversary]` and preserves the
   `[codex-adversary]` prefixes for provenance. Use the returned `verdict` as the
   effective adversary verdict and the returned `concerns` as the concern set:
   - aggregate `clean` → treat as the both-clean case (primary + Claude + Codex).
   - aggregate `concern` → route the concerns to the auto-fix queue (existing rules).
   - aggregate `blocking` → immediate escalation (existing rules).

Codex failure **never blocks** the pipeline: if `codex_adapter.py merge` itself
fails (non-zero exit) — or any earlier step in this subsection skipped or
errored — the Claude adversary verdict stands alone and routing proceeds
exactly as it does without Codex; log the failure to `validation-log.txt` and
continue.

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

### `verdict: "concern"` → queue for auto-fix (regardless of category)

**Routing rule (changed in 1.1.0 — was over-strict, escalated too eagerly):**

If `verdict == "concern"`, write ALL concerns to the auto-fix queue regardless of `category`. The orchestrator's auto-fix loop (P6 `_advance-goal`) will re-dispatch the implementer with the concerns as explicit fix guidance, up to a cap of 3 rounds. The `category` field is **informational metadata** for the implementer — it tells them the NATURE of the concern (mechanical/judgment/uncategorized) but does NOT gate routing.

The previous design double-gated: any `judgment` category → escalate. But the reviewer's `verdict` field already encodes severity. If the work needs more iteration but is code-fixable, that's `verdict: concern`. If the work is fundamentally broken and can't be code-fixed, that's `verdict: blocking`. Use `verdict` for routing; treat `category` as guidance for the implementer.

**What to do:**

1. Write the full concerns array to `.claude/agentic/auto-fix-queue/<goal-id>.json` — JSON array of all concern objects (with their category, severity, file, line, description preserved). The implementer will read this on the next round.

2. Optionally call `bin/log-incident.sh checklist ...` once per judgment-category concern for cross-session learning (`caught_by: reviewer`). Failure is non-blocking (P7-L4); log and continue.

3. Print:
   ```
   Goal <goal-id>: <N> concerns queued for auto-fix loop
     <count> mechanical, <count> judgment, <count> uncategorized
   ```

4. Exit 0.

The orchestrator's `_advance-goal` skill reads the auto-fix-queue file and either dispatches another implementer round (if under cap) or escalates as `auto_fix_exhausted` (if cap reached).

**Why this is safe:**

- `verdict: blocking` is the reviewer's explicit "halt now" signal — it short-circuits to escalation (see below).
- The implementer will see the categorized concerns and apply judgment-aware fixes; if a concern truly requires a spec change, the implementer should record a `spec_change_request` in its new manifest, which itself surfaces as a different kind of escalation.
- The cap (3 rounds) prevents infinite loops if the implementer can't converge.
- For genuinely architectural decisions, the reviewer should mark `verdict: blocking` — that escalates immediately.

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
  codex adversary:   <ran (verdict) | skipped (reason_code) | disabled>

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
