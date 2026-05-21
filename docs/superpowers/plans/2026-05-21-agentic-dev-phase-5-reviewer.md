# Phase 5 — Hardened Reviewer + Escalation + Telegram Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Ship v0.5: AI judgment layer (hardened reviewer + adversary), escalation packet generation, Telegram notifications with placeholder config. Concern routing (mechanical → auto-fix-candidate, judgment → escalation). Zero `claude -p` in tests; one controller-driven agent-dispatch smoke.

**Architecture:** P4's gates produce a verdict; if P4 passed, P5's `_run-reviewer` dispatches the hardened-reviewer subagent (read-only, adversarial, doesn't see implementer prose). On clean verdict, second-pass adversary runs. Concerns routed by category; judgment concerns generate an escalation packet + Telegram notification. Telegram has a placeholder mode (file log only if not configured).

**Reference design:** `docs/superpowers/specs/2026-05-21-agentic-dev-phase-5-reviewer-design.md` (READ FIRST for full content).

**Cost policy:** `docs/superpowers/test-cost-policy.md` — zero `claude -p` in P5; one agent-dispatched smoke at T6.

---

## File Structure

**New plugin source:**
- `agentic-dev/agents/hardened-reviewer.md`
- `agentic-dev/agents/reviewer-adversary.md`
- `agentic-dev/schemas/reviewer-verdict.schema.json`
- `agentic-dev/schemas/escalation-packet.schema.json`
- `agentic-dev/bin/telegram-notify.sh`
- `agentic-dev/bin/generate-escalation.sh`
- `agentic-dev/skills/_run-reviewer/SKILL.md`

**Tests** (`tests/phase-5/`):
- `reviewer_verdict_schema_test.py`
- `escalation_packet_schema_test.py`
- `hardened_reviewer_structure_test.py`
- `reviewer_adversary_structure_test.py`
- `telegram_notify_test.sh`
- `generate_escalation_test.sh`
- `run_reviewer_skill_structure_test.py`
- `run_all.sh`
- `fixtures/` — manifest, verdict, diff-envelope, config, escalation samples

**Plugin meta:**
- `agentic-dev/.claude-plugin/plugin.json` (0.5.0)
- `agentic-dev/README.md` (v0.5 section)
- `agentic-dev/CHANGELOG.md` (v0.5.0 entry)

---

## Task 1: Schemas (reviewer-verdict + escalation-packet)

**Files:** 2 schemas + 2 tests + 2 fixtures.

**`reviewer-verdict.schema.json`** required: schema_version (const "0.1"), goal_id (pattern), reviewer_role (enum: primary|adversary), reviewed_at (date-time), verdict (enum: clean|concern|blocking), concerns (array), checks_run (array). 

Concerns items: file, line (integer ≥0), severity (enum: blocking|concern), category (enum: mechanical|judgment|uncategorized), description. All required, additionalProperties:false.

checks_run items: name, outcome (enum: pass|fail), evidence. Required.

**`escalation-packet.schema.json`** required: schema_version, goal_id, generated_at, trigger (enum: reviewer_blocking|judgment_concerns|gate_failure|auto_fix_exhausted|budget_hard_halt|spec_drift), concerns (array; same shape as reviewer concerns), manifest_path, summary, suggested_next_actions (array of strings).

Optional: verdict_path, diff_envelope_path, spec_path, worktree_path.

**Tests:** positive + 3 negative cases each (bad enum, missing field, bad date-time).

**Steps:**
1. Fixtures: hand-author sample-reviewer-verdict-clean.json, sample-reviewer-verdict-concerns.json, sample-escalation.json
2. Write 2 schema tests (mirror P4 pattern); run, expect fail
3. Create both schemas
4. Re-run; expect 8 PASS total (4 each)
5. Commit `feat(phase-5): reviewer-verdict + escalation-packet schemas`

---

## Task 2: Subagents (hardened-reviewer + reviewer-adversary)

**Files:** 2 agent definitions + 2 structural tests.

**`agents/hardened-reviewer.md`** frontmatter:
```yaml
---
name: hardened-reviewer
description: Read-only AI reviewer for a goal's manifest + diff. Adversarial framing: assume the diff is broken; find where it is. Produces structured JSON verdict. NEVER edits files.
tools: Read, Glob, Grep, Bash
---
```

Body must include:
- The adversarial system prompt (per design §4 — "Assume this diff is broken. The implementer's job was to make it look correct. Your job is to find where it isn't. List every concern with file:line and severity.")
- What you receive: spec, manifest (filtered — no commit message bodies, no implementer prose), diff envelope, P4 verdict
- Two judgment dimensions: (1) does the diff actually implement what the spec says? (2) does it introduce risks (hard-coded secrets, dependency drift, security smells, out-of-spec creep)?
- Categorize each concern: mechanical (coverage low, lint nit, missing test edge) vs judgment (architectural choice, security risk, scope drift)
- Required output structure: JSON matching reviewer-verdict.schema.json; `reviewer_role: "primary"`; NO preamble, NO code fences
- "Do NOT" list: no Write/Edit; never edit the spec; never edit the manifest; never invent concerns (clean is a valid verdict)

**`agents/reviewer-adversary.md`** frontmatter same shape but `name: reviewer-adversary`, description mentions second-pass.

Body: "The first reviewer marked this clean. Your job is to find what they missed." Same JSON output but `reviewer_role: "adversary"`. Emphasis: only return concerns if you find SOMETHING; don't invent if first reviewer was right.

**Structural tests** mirror P2's drafter structure test pattern: assert frontmatter, tools (read-only — no Write/Edit/NotebookEdit), required phrases (adversarial, "blocking", "concern", "category", "JSON", "no preamble"), required sections.

**Steps:**
1. Write 2 structural tests; run; expect fail
2. Create hardened-reviewer.md (full content per design + key phrases)
3. Create reviewer-adversary.md (second-pass framing)
4. Re-run tests; expect 2 PASS
5. Commit `feat(phase-5): hardened-reviewer + reviewer-adversary subagents`

---

## Task 3: telegram-notify.sh + generate-escalation.sh

**Files:** 2 bash scripts + 2 tests.

**`bin/telegram-notify.sh`** `<severity> <message> [packet-path]`:
1. Read `.claude/agentic/config.yaml`'s `telegram` field
2. If `telegram == null` OR `telegram.bot_token` missing OR `telegram.chat_id` missing → append to `.claude/agentic/notifications-log.txt` (format: `<ISO timestamp> | <severity> | <message>`); print "logged (Telegram not configured)"; exit 0
3. Otherwise: POST to `https://api.telegram.org/bot<token>/sendMessage` with chat_id + formatted message (severity prefix, optional packet excerpt)
4. On HTTP failure: log + print warning; exit 0 (notifications are advisory)

Always exit 0 — notifications don't fail the pipeline.

**`bin/generate-escalation.sh`** `<goal-id> <trigger> [manifest-path] [verdict-path]`:
1. Look up manifest at `.claude/agentic/manifests/<goal-id>.json` (or use override)
2. Look up reviewer-verdict at `.claude/agentic/reviewer-verdicts/<goal-id>.json` if exists
3. Look up gate verdict at `.claude/agentic/verdicts/<goal-id>.json` if exists
4. Read concerns from reviewer-verdict (if applicable) or blocking_failures from gate verdict
5. Build escalation packet JSON matching escalation-packet.schema.json
6. Write to `.claude/agentic/escalations/<ISO-timestamp>-<goal-id>.md` as markdown with structured sections (Summary, Trigger, Goal Info, Concerns, Suggested Actions) + JSON appendix
7. Print packet path; exit 0

**Tests:**
- `telegram_notify_test.sh`: 3 fixtures — placeholder mode (no config → log file populated, no network attempt verifiable via stdout); configured but unreachable server (graceful fail); missing args (refused with exit 1)
- `generate_escalation_test.sh`: 2 fixtures — given a manifest+verdict, generates a valid escalation packet (validates against escalation-packet.schema.json); given missing manifest, errors

**Steps:**
1. Write both tests; run; expect fail
2. Create telegram-notify.sh; chmod +x; run telegram test; expect pass
3. Create generate-escalation.sh; chmod +x; run escalation test; expect pass
4. Commit `feat(phase-5): telegram-notify + generate-escalation helpers`

---

## Task 4: _run-reviewer skill

**Files:** 1 SKILL.md + 1 structural test.

**`skills/_run-reviewer/SKILL.md`** behavior:
1. $ARGUMENTS = goal-id; refuse if empty
2. Pre-checks: manifest + gate verdict + diff envelope all exist
3. If gate verdict's `overall == "fail"` with any blocking_failures:
   - Skip reviewer dispatch
   - Call `bin/generate-escalation.sh <goal-id> gate_failure`
   - Call `bin/telegram-notify.sh blocking "Goal <id> blocked by gates"` 
   - Print packet path; exit 1
4. Otherwise: dispatch hardened-reviewer subagent via Agent tool with:
   - Spec text (Read the spec file)
   - Filtered manifest (strip commits[].subject if implementer-prose-rich; keep core fields)
   - Diff envelope path (subagent reads it)
   - Gate verdict (passing)
5. Capture JSON response; validate against reviewer-verdict.schema.json; write to `.claude/agentic/reviewer-verdicts/<id>.json`
6. Route on verdict:
   - `clean` → dispatch reviewer-adversary; merge any new concerns
   - `concern` → categorize concerns; if all mechanical → mark "auto-fix-candidate"; else trigger escalation
   - `blocking` → trigger escalation
7. If escalation triggered: generate-escalation.sh + telegram-notify.sh (severity=blocking for blocking verdict; severity=warning for judgment concerns)
8. Print structured summary; exit 0 if clean, 1 if escalation

**Structural test** mirrors prior pattern: assert frontmatter, key phrases ("$ARGUMENTS", "hardened-reviewer", "reviewer-adversary", "Agent tool", "generate-escalation", "telegram-notify", "clean", "concern", "blocking", "mechanical", "judgment", "uncategorized").

**Steps:**
1. Write structural test; run; expect fail
2. Create SKILL.md
3. Re-run; expect 1 PASS
4. Commit `feat(phase-5): /agentic-dev:_run-reviewer skill`

---

## Task 5: Phase 5 run_all + completion checks

1. Create `tests/phase-5/run_all.sh` aggregating all P5 deterministic tests
2. Run full P5 suite; expect all PASS
3. Run P3 + P4 to confirm no regression
4. Commit `test(phase-5): run_all aggregator`

---

## Task 6: Closer (docs + version bump + agent-dispatch smoke)

1. `agentic-dev/.claude-plugin/plugin.json`: version → "0.5.0"
2. `agentic-dev/README.md`: intro updated to v0.5; new v0.5 subsection
3. `agentic-dev/CHANGELOG.md`: v0.5.0 entry above v0.4.0 with all P5 additions
4. **Controller-driven agent-dispatch smoke** (executed by the controller during T6 verification, not part of `run_all.sh`):
   - Set up a tmp project with init + a hand-authored approved spec + a manifest+diff envelope for a trivial passing change
   - Dispatch hardened-reviewer via Agent tool with those inputs
   - Verify JSON output validates against reviewer-verdict.schema.json
   - Verdict for clean inputs: expect "clean"
   - Try once more with a "concerning" manifest (e.g., diff that adds a hardcoded API key); verify reviewer flags it
   - This smoke is informational only — not blocking for v0.5 ship
5. Update DEFERRED.md if any new items emerge
6. Commit `docs(phase-5): v0.5.0 — README + CHANGELOG + plugin version`

---

## Phase 5 Completion Checklist

- [ ] `bash tests/phase-5/run_all.sh` exits 0
- [ ] P1-P4 still pass (no regression)
- [ ] plugin.json version is "0.5.0"
- [ ] CHANGELOG records v0.5.0
- [ ] All 6 task commits on the branch
- [ ] Zero `claude -p` invocations in P5 dev (agent-dispatched smoke in T6 is Max-billed)
