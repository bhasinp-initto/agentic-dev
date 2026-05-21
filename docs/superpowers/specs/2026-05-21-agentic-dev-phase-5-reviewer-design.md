# Phase 5 — Hardened Reviewer + Escalation + Telegram Design

**Status:** Draft (autonomous decision-mode)
**Date:** 2026-05-21
**Phase:** P5 of P1–P8
**Umbrella spec:** §4 Role 2b (reviewer), §7 Reviewer hardening, §8 Escalation policy, §9 Concern handling, §12 Escalation mechanics

---

## 1. Intent

Phase 5 ships the AI judgment layer that runs AFTER P4's deterministic gates: the hardened reviewer subagent reads the manifest + structured diff + spec and returns a structured verdict; the reviewer-adversary runs a second pass on otherwise-clean reviews; concerns categorized as "mechanical" get auto-fix-looped through the implementer; concerns categorized as "judgment" escalate to human via an escalation packet + Telegram notification. Telegram ships with a placeholder configuration mechanism — if not configured, notifications log to file only.

## 2. Goals

- **G1** — `hardened-reviewer` subagent: read-only, adversarial prompt per umbrella §7, doesn't see implementer reasoning (stripped at hand-off), produces structured JSON verdict.
- **G2** — `reviewer-adversary` subagent: second-pass on clean reviews; "find what the first reviewer missed."
- **G3** — Concern routing: `mechanical` → auto-fix loop (cap 2 rounds); `judgment` → escalate.
- **G4** — Escalation packet generation: structured markdown at `.claude/agentic/escalations/<timestamp>-<goal-id>.md`.
- **G5** — Telegram notification helper: severity-tiered routing per umbrella §12. Placeholder config in `.claude/agentic/config.yaml`'s `telegram` field; if absent → log to `.claude/agentic/notifications-log.txt`.
- **G6** — `_run-reviewer` lifecycle skill that wires it all together: dispatches reviewer, parses verdict, runs adversary on clean, handles concerns, generates escalation, fires notification.
- **G7** — Per cost policy: deterministic tests for schemas + structural tests for skills/agents; ONE controller-driven agent-dispatch smoke for actual reviewer behavior. Zero `claude -p` in P5.

## 3. Non-goals

- The implementer's auto-fix loop full integration (P6 — orchestrator drives the iteration).
- Cross-model review (the design's Path B/D — deferred to v1.x).
- Walkthrough/Playwright (deferred).
- User-facing Telegram config UI (config.yaml editing is the v0.5 surface).

## 4. Architecture

```
agentic-dev/
├── agents/
│   ├── hardened-reviewer.md          NEW
│   └── reviewer-adversary.md         NEW
├── schemas/
│   ├── reviewer-verdict.schema.json  NEW
│   └── escalation-packet.schema.json NEW
├── bin/
│   ├── telegram-notify.sh            NEW
│   └── generate-escalation.sh        NEW
└── skills/
    └── _run-reviewer/SKILL.md        NEW
```

### Reviewer hardening (per umbrella §7)

The `hardened-reviewer` subagent:

- **Tools:** Read, Glob, Grep, Bash (for `git show`, test re-runs if needed). NO Write, NO Edit, NO Agent dispatch.
- **System prompt:** Adversarial framing — *"Assume this diff is broken. The implementer's job was to make it look correct. Your job is to find where it isn't."*
- **Input contract** (orchestrator strips before hand-off):
  - Receives: spec, manifest (with `clarifying_questions_asked` + `deferrals` + `spec_change_requests` only — NOT `commits[].subject` prose, NOT free-form reasoning), diff envelope, P4 verdict, artifacts.
  - Does NOT receive: implementer's commit message bodies (only commit SHAs in the manifest's `commits[]` array — even `subject` is debatable; for v0.5 we include `subject` but the verbose reasoning is never present anyway).
- **Output:** Structured JSON matching `reviewer-verdict.schema.json`.

### `reviewer-verdict.schema.json` shape

```json
{
  "schema_version": "0.1",
  "goal_id": "...",
  "reviewer_role": "primary | adversary",
  "reviewed_at": "...",
  "verdict": "clean | concern | blocking",
  "concerns": [
    {
      "file": "src/foo.ts",
      "line": 42,
      "severity": "blocking | concern",
      "category": "mechanical | judgment | uncategorized",
      "description": "..."
    }
  ],
  "checks_run": [
    { "name": "...", "outcome": "pass | fail", "evidence": "..." }
  ]
}
```

Per umbrella §8: uncategorized concerns default to `judgment` → escalate (anti-eagerness applied to categorization itself).

### Concern handling (per umbrella §9)

After primary reviewer verdict:

- **`clean`** → dispatch `reviewer-adversary` for second pass (cheap; catches first-pass misses).
  - Adversary clean → goal complete; emit Telegram digest entry; cleanup worktree (eventually — P6 owns this).
  - Adversary finds concerns → treat as new concerns from primary reviewer; route per category.
- **`concern`** verdict:
  - For each concern: if `category == "mechanical"` → enqueue for auto-fix loop. If `category == "judgment"` or `uncategorized` → mark for escalation.
  - If any judgment-category concerns OR auto-fix-loop exceeded cap → generate escalation packet, send Telegram, halt.
  - If only mechanical concerns AND under cap → re-dispatch implementer with concerns as a structured task; on completion, re-run reviewer (round 2).
- **`blocking`** verdict → immediate escalation; no auto-fix attempt; halt.

**Auto-fix cap:** 2 rounds. After 2 rounds without convergence → escalate as if judgment.

In v0.5, the auto-fix loop is a single round (no integration with P3's implementer dispatch yet; that's P6). P5's `_run-reviewer` skill captures the verdict and the routing decision, writes it to disk; the orchestrator (P6) actually drives the loop.

### `escalation-packet.schema.json` shape

```json
{
  "schema_version": "0.1",
  "goal_id": "...",
  "generated_at": "...",
  "trigger": "reviewer_blocking | judgment_concerns | gate_failure | auto_fix_exhausted | budget_hard_halt | spec_drift",
  "concerns": [...],
  "manifest_path": "...",
  "verdict_path": "...",
  "diff_envelope_path": "...",
  "spec_path": "...",
  "worktree_path": "...",
  "summary": "...",
  "suggested_next_actions": ["resume", "skip", "address", "replan", "abort"]
}
```

The orchestrator (P6) reads this when the human resumes; v0.5 just writes it.

### Telegram notification helper

`bin/telegram-notify.sh`:

```
Usage: telegram-notify.sh <severity> <message-summary> [packet-path]
Severities: blocking | digest | warning | info
```

Behavior:
1. Read `.claude/agentic/config.yaml` `telegram` field.
2. If `telegram == null` or `bot_token` missing → log to `.claude/agentic/notifications-log.txt` and exit 0. (Placeholder mode.)
3. If configured: POST to Telegram Bot API with severity-tiered formatting. On failure → log + exit 0 (notifications never fail-loud; they're a side channel).

Severity routing per umbrella §12:
- `blocking` → push (real-time, even at 2am)
- `digest` → batched (appended to morning digest file; not sent immediately in v0.5)
- `warning` → batched
- `info` → log only (not pushed)

v0.5 ships push for blocking; digest-batching defers to P6 (which controls the queue runs).

## 5. Lifecycle (v0.5)

```
1. P4's _run-gates completes; verdict at .claude/agentic/verdicts/<id>.json
2. Caller invokes: /agentic-dev:_run-reviewer <goal-id>
3. Skill pre-checks: manifest + verdict + diff envelope all exist
4. If P4 verdict.overall == "fail" with any blocking_failures: skip reviewer; generate escalation directly with trigger=gate_failure. Notify. Halt.
5. Otherwise: dispatch hardened-reviewer (Agent tool, subagent_type)
   - Input: spec, manifest (filtered), diff envelope, verdict, artifacts
   - Output: JSON matching reviewer-verdict.schema.json
6. Parse + validate. Write to .claude/agentic/reviewer-verdicts/<id>.json
7. Route:
   - verdict=clean → dispatch reviewer-adversary (second pass); merge concerns
   - verdict=concern AND all concerns are mechanical AND auto-fix-rounds <2 → mark "needs auto-fix", write routing decision, exit 0 (P6 picks up)
   - verdict=concern AND any judgment concern → generate-escalation; notify; exit 1
   - verdict=blocking → generate-escalation; notify; exit 1
8. Print summary
```

## 6. Testing strategy (per cost policy)

### 6.1 Deterministic tests (run on every run_all.sh)

- `reviewer_verdict_schema_test.py` — positive + 3 negative cases (bad verdict enum, bad category enum, missing required field).
- `escalation_packet_schema_test.py` — positive + 2 negative cases.
- `hardened_reviewer_structure_test.py` — parses agents/hardened-reviewer.md; asserts frontmatter, tools list (no mutation tools), required phrases (adversarial framing, "blocking", "concern", "category", "checks_run").
- `reviewer_adversary_structure_test.py` — parses agents/reviewer-adversary.md; asserts second-pass framing.
- `telegram_notify_test.sh` — invokes bin/telegram-notify.sh with config.yaml in placeholder mode; asserts log file populated; no network call attempted.
- `generate_escalation_test.sh` — invokes bin/generate-escalation.sh with hand-authored manifest+verdict; asserts escalation file written + validates against schema.
- `run_reviewer_skill_structure_test.py` — parses skills/_run-reviewer/SKILL.md.

### 6.2 Agent-dispatch smoke (controller-driven; Max-billed, no API cost)

ONE smoke test that I (controller) run during T6 final verification:
- Hand-author a "clean" manifest+diff (trivial 5-line addition)
- Dispatch hardened-reviewer via Agent tool with the proper inputs
- Verify verdict parses + verdict is "clean"
- Hand-author a "concerning" manifest+diff (adds a hard-coded secret, or modifies a file outside scope — adversarial example)
- Dispatch reviewer → verify concerns flagged

This smoke is invoked by me at task T6; it doesn't ship as part of `run_all.sh`.

### 6.3 Zero `claude -p` in P5

All structural tests are deterministic. Smoke is agent-dispatched. Estimated P5 dev cost: **<$2**.

## 7. Load-bearing properties

- **P5-L1** — Reviewer NEVER sees implementer prose/reasoning. Strip-at-handoff is enforced in the lifecycle skill.
- **P5-L2** — Reviewer is read-only at the tool level (frontmatter: Read, Glob, Grep, Bash for read-only inspection). No Write/Edit.
- **P5-L3** — Uncategorized concerns default to judgment → escalate.
- **P5-L4** — Auto-fix loop has a hard cap (2 rounds in design; v0.5 ships single-round capture without full loop integration; P6 wires the loop).
- **P5-L5** — Telegram notifications never block the pipeline. Failures log to file.
- **P5-L6** — Escalation packets are written even if Telegram fails (filesystem-first; Telegram is a side channel).
- **P5-L7** — P4's gate verdict's `overall: fail` short-circuits the reviewer. No point asking AI judgment when deterministic checks already failed.

## 8. Scope of P5 v1 build

1. Schemas: reviewer-verdict + escalation-packet + tests.
2. Subagents: hardened-reviewer + reviewer-adversary + structural tests.
3. Helpers: bin/telegram-notify.sh + bin/generate-escalation.sh + tests.
4. Lifecycle skill: skills/_run-reviewer/SKILL.md + structural test.
5. Aggregator: tests/phase-5/run_all.sh.
6. Closer: plugin.json 0.5.0 + README + CHANGELOG + DEFERRED updates.

6 tasks. Pattern matches P3/P4.

## 9. Out of scope (deferred to later)

- Full auto-fix-loop integration with P3 implementer dispatch — P6.
- Digest batching for non-blocking notifications — P6.
- Cross-model reviewer (Codex etc.) — v1.x.
- Walkthrough integration — v1.x or later.
- Reviewer-adversary as a third-pass — v1.x if empirically warranted.
- Memory.yaml updates from reviewer findings — P7.

## 10. References

- Umbrella spec §4 (Roles 2a/2b), §6.5 (verification flow), §7 (reviewer hardening), §8 (escalation policy), §9 (concern handling), §12 (escalation mechanics)
- P4 design: gates produce the verdict P5 consumes
- Test cost policy: `docs/superpowers/test-cost-policy.md`
