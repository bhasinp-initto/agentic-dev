# Phase 2 — Spec Drafter Design

**Status:** Draft for review
**Date:** 2026-05-20
**Phase:** P2 of P1–P8
**Umbrella spec:** `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` (§4 Role 2c, §6.1, §15)

---

## 1. Intent

Phase 2 adds the spec-drafting layer of the agentic-dev system. When a human runs `/agentic-dev:intent <free-form text>`, the system records the intent, drafts a structured spec with explicit `QUESTION-N` blocks at every architectural decision, and gates approval behind a two-stage validator (deterministic + AI). After P2 ships, a human can move from "I want X" to a measurable, scope-bounded, approved spec without writing code by hand — but cannot bypass the explicit-decision discipline that makes the rest of the system possible.

## 2. Goals

- **G1** — Implement `/agentic-dev:intent` as the user's single entry point for new work.
- **G2** — Implement the `spec-drafter` subagent that produces structured drafts, refusing to guess on architectural decisions (anti-eagerness).
- **G3** — Implement the spec validator in two halves: deterministic checks via shell on every spec save, AI-judgment checks via subagent on approval attempts.
- **G4** — Preserve the load-bearing property that drafting state lives on disk continuously (spec §20 L8); no conversation-local state is required to resume a draft.
- **G5** — Pivotable seam — the drafter's structured-output contract (`{frontmatter, sections, questions[]}`) is reviewer-agnostic so P5's reviewer subagent can consume the same schema later.

## 3. Non-goals (out of scope for P2)

- Touching `.claude/agentic/queue.yaml`. The queue is populated later (P6).
- Implementing `/agentic-dev:approve` or any explicit approval CLI. Approval is "edit frontmatter to `approved: true`" — the spec file IS the gesture.
- Implementing the implementer subagent or any work that consumes approved specs (P3).
- Telegram notifications on approval (P5).
- Refining the AI validator into a fully adversarial reviewer (P5).
- Resolving **P1-DEF-001** (queue goal schema extension strategy). Deferred again to whichever phase first writes new fields to goal items, expected P3 or P6.

## 4. Architecture

```
agentic-dev/
├── skills/
│   ├── init/SKILL.md                    (existing, P1)
│   ├── status/SKILL.md                  (existing, P1)
│   ├── intent/SKILL.md                  NEW — user entry point
│   └── _check-approval/SKILL.md         NEW — internal, hook-triggered;
│                                              dispatches spec-validator-ai
│                                              on approval flip
├── agents/
│   ├── spec-drafter.md                  NEW — drafter subagent
│   └── spec-validator-ai.md             NEW — AI validator subagent
├── bin/
│   └── validate-spec.sh                 NEW — deterministic validator
├── hooks/
│   └── hooks.json                       NEW — wires validate-spec.sh
│                                              and triggers _check-approval
├── schemas/
│   ├── state.schema.json                (existing, P1)
│   ├── queue.schema.json                (existing, P1, untouched in P2)
│   ├── config.schema.json               (existing, P1)
│   └── spec.schema.json                 NEW — spec frontmatter schema
└── prompts/                             NEW — editable default prompts
    ├── spec-drafter.md
    └── spec-validator-ai.md
```

### Component roles

- **`/agentic-dev:intent <text>` (skill in main session).** Records raw intent to `.claude/agentic/intents/<id>.md`. Dispatches `spec-drafter` subagent. Writes the returned structured draft to `.claude/agentic/specs/<id>.md`. Reports the path and unresolved-QUESTION count. Exits. Supports `--refine <spec-path>` to re-run the drafter on a partially-answered spec.
- **`spec-drafter` (subagent).** Read-only on the host project (can `Read`/`Glob` to propose realistic file paths, cannot `Edit`/`Write`). Produces a structured draft: `{ frontmatter, sections[], questions[] }`. Returns it; never writes files itself.
- **`bin/validate-spec.sh` (deterministic).** Hook-invoked on every save to `.claude/agentic/specs/*.md`. Mechanical checks only. Exit-coded output.
- **`spec-validator-ai` (subagent).** Dispatched only when the deterministic validator detects an `approved: false → true` flip and all mechanical checks pass. Read-only on the spec. Judges measurability of completion criteria and scope coherence. Returns structured `{verdict, concerns[]}`. The invoking skill translates concerns into new `QUESTION-N` blocks in the spec.

### Read/Write boundaries (load-bearing)

| Component | Reads | Writes |
|---|---|---|
| `/agentic-dev:intent` skill | host repo, intent file, spec file (for refine) | intent file, spec file |
| `spec-drafter` subagent | host repo (Read/Glob), intent text, config defaults | nothing |
| `validate-spec.sh` | spec file | nothing (exit code only) |
| `spec-validator-ai` subagent | spec file | nothing (structured output) |
| `_check-approval` skill (triggered by hook) | validator AI output | spec file (writes new QUESTIONs + reverts `approved`) |

Only the skill that owns the lifecycle ever writes the spec. Subagents are output-only. This mirrors P5's planned reviewer pattern.

## 5. Drafter calibration (anti-eagerness)

The drafter's system prompt encodes a fixed table mapping spec sections to behavior. The drafter is forbidden from improvising outside the table — if a section isn't in the table, default-to-flag.

| Spec section / field | Behavior |
|---|---|
| Frontmatter `id`, `date` | Confident from environment (current date, derived from slug) |
| Frontmatter `approved` | Confident default `false` |
| Frontmatter `slug` | Derive kebab-case from intent text (first 5–8 meaningful words, sanitized); emit `QUESTION-N` if intent is too vague |
| `Intent` (section body) | Echo human's words verbatim. No paraphrase. |
| `Scope — In` | Flag as `QUESTION-N` with 2–4 concrete suggestions from intent. Never confidently set. |
| `Scope — Out (deferrals)` | Flag as `QUESTION-N`. Forces explicit boundary thinking. |
| `Files in scope` | Flag as `QUESTION-N` with suggestions based on repo inspection. |
| `Architectural decisions` | Flag every non-trivial one. Load-bearing anti-eagerness lever. |
| `ADR candidates` | Flag with proposed list; empty list is a valid answer. |
| `Test strategy` | Confident default for small changes: "Add tests for new behaviors; existing tests must continue to pass." Flag for substantive features. |
| `Completion criteria` | Flag with the explicit measurable-predicate constraint and examples. |
| `Diff budget` | Confident from `config.yaml` defaults. Flag if intent suggests larger work. |
| `Sensitive paths` | Confident from `config.yaml` defaults. Flag if intent touches a path the human might want added. |

### `QUESTION-N` block format (canonical)

```markdown
<!-- QUESTION-3 (architectural-decision) -->
**Q:** Should rate limits be enforced per-tenant or per-API-key?

**Why this matters:** Per-tenant scopes affect a tenant's whole organization;
per-API-key allows finer-grained throttling but requires UI changes for users
to provision distinct keys.

**Options:**
- A. Per-tenant (simpler; matches existing auth scoping)
- B. Per-API-key (finer-grained; needs API-key provisioning UI)
- C. Both, with per-tenant as the outer ceiling and per-key as the inner cap

**Your answer:** [REPLACE THIS LINE with A, B, C, or your own text]
```

The `<!-- QUESTION-N` HTML comment is the machine-parseable delimiter. The deterministic validator looks for this marker. Categories used: `scope-in`, `scope-out`, `files-in-scope`, `architectural-decision`, `adr-candidates`, `test-strategy`, `completion-criteria`, `diff-budget`, `sensitive-paths`, `slug`.

## 6. Lifecycle

### Path A — fresh intent

1. User: `/agentic-dev:intent "Add rate limiting per-tenant to the API"`
2. Skill generates id (`YYYY-MM-DD-slug`), writes intent file, dispatches `spec-drafter` with `{intent_id, intent_text, repo_summary, config_defaults}`.
3. Drafter inspects repo (Read/Glob) to propose realistic paths, produces structured draft.
4. Skill writes `specs/<id>.md` with QUESTION-N blocks per the drafter's questions[] output.
5. Skill prints spec file path and count of unresolved QUESTIONs. Exits.

### Path B — user edits in place

6. User opens spec, answers QUESTION-N blocks by replacing "Your answer:" lines.
7. Each save fires the hook → `validate-spec.sh` runs → reports remaining count or mechanical failures.

### Path C — refinement on a partial spec

8. User: `/agentic-dev:intent --refine specs/<id>.md`
9. Skill reads partial spec, dispatches `spec-drafter` with current state. Drafter never overwrites human's answers; may add new QUESTION-N blocks if answers exposed new ambiguities.

### Path D — approval gate

10. User edits frontmatter `approved: true`.
11. Hook fires `validate-spec.sh` → detects `approved: true` → checks no remaining QUESTION-Ns → if clean, signals the _check-approval skill to dispatch `spec-validator-ai`.
12. AI validator returns verdict. Concerns → skill writes new QUESTION-N blocks AND reverts `approved` to `false`. Clean → spec stays approved. Hook logs.

**Key property:** every state is on disk. Step-away resumability is intrinsic.

## 7. Spec file template

````markdown
---
id: 2026-05-20-add-rate-limiting-per-tenant
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-add-rate-limiting-per-tenant.md
approved: false
created_at: 2026-05-20T15:30:00Z
---

# Intent

<!-- echoed verbatim from intent file -->

# Scope — In
<!-- QUESTION-N blocks if flagged -->

# Scope — Out (deferrals)
<!-- QUESTION-N if flagged -->

# Files in scope
<!-- QUESTION-N typically -->

# Architectural decisions
<!-- QUESTION-N per decision -->

# ADR candidates
<!-- QUESTION-N -->

# Test strategy
<!-- confident default OR QUESTION-N -->

# Completion criteria
<!-- QUESTION-N -->

# Diff budget
- Wall clock: 90 minutes
- Diff lines: 800
- Files touched: 25

# Sensitive paths
(inherits from config.yaml unless overridden)
````

### Intent file template

```markdown
---
id: 2026-05-20-add-rate-limiting-per-tenant
created_at: 2026-05-20T15:30:00Z
---

Add rate limiting per-tenant to the API
```

Body is the human's words verbatim. Plain, minimal.

## 8. Validator design

### 8.1 Deterministic half — `bin/validate-spec.sh`

Runs on every spec save via `PostToolUse` hook (matcher: `Write|Edit`, file pattern: `.claude/agentic/specs/*.md`).

Checks:
1. Frontmatter parses as YAML; required fields present (`id`, `schema_version`, `intent_path`, `approved`, `created_at`).
2. `schema_version` matches `"0.1"` (const).
3. `intent_path` resolves on disk.
4. `approved` is boolean.
5. If `approved == true`:
   - No `<!-- QUESTION-N` markers remain in the body.
   - No literal `[REPLACE THIS LINE` strings remain.
6. `created_at` validates as RFC 3339 date-time.
7. "Diff budget" section parses out wall_clock_minutes / diff_lines / files_touched as integers ≥ 1.
8. "Files in scope" globs are syntactically valid; warn (not fail) on zero current matches (forward-looking globs are legal).

Output on failure (precise; actionable):
```
agentic-dev: spec validation failed
  file: .claude/agentic/specs/<id>.md
  ERROR: approved=true but 2 unresolved QUESTION blocks remain:
    - QUESTION-3 (files-in-scope) at line 42
    - QUESTION-6 (completion-criteria) at line 71
  Either answer those questions or set approved=false.
```

### 8.2 AI half — `spec-validator-ai` subagent

Dispatched ONLY on `approved: false → true` flip AND deterministic side passes. Read-only on the spec. Returns structured JSON:

```json
{
  "verdict": "clean | concerns",
  "concerns": [
    {
      "category": "completion-criterion | scope-coherence",
      "criterion_index": 2,
      "explanation": "...",
      "suggested_question": "Concrete QUESTION-N text the skill should embed"
    }
  ]
}
```

Two judgment checks:
1. **Measurability of each completion criterion.** A criterion is measurable if an automated check could verify it without human judgment.
2. **Scope coherence with intent.** Does the intent text fit within in-scope? Does out-of-scope contradict the intent?

### 8.3 Concerns handling

The _check-approval skill (triggered by the same hook) consumes the validator's JSON:
- `clean` → spec stays at `approved: true`. Hook logs the success to `.claude/agentic/validation-log.txt`.
- `concerns` → for each concern, the skill writes a new QUESTION-N block at the right location in the spec, sets `approved` back to `false`, and writes a one-line note above the new blocks:

```markdown
<!-- spec-validator-ai found new ambiguities; resolve before re-approval -->
```

User sees the new questions on next read. Loop continues, no bounce.

## 9. Error handling

| Failure | Handling |
|---|---|
| User breaks YAML frontmatter | Deterministic validator reports parse error with line number. No data lost. |
| User puts incoherent answer ("garbage") | Deterministic side can't catch. AI validator catches via scope-coherence; writes follow-up QUESTION. No silent acceptance. |
| Drafter subagent fails/times out/returns malformed output | Skill catches; writes nothing to disk; surfaces error; intent file preserved so re-run is cheap. |
| AI validator fails | Logged to `validation-log.txt`. `approved` stays `true`. Status skill flags unprocessed validation. Full escalation comes in P5. |
| Hook misfires | Hook output visible in Claude Code tool output. Spec untouched (fail-open in the data-loss sense). |
| Spec file deleted mid-flow | Status skill notices orphaned intent. User can re-run `--refine` to regenerate, or delete intent. No automatic resurrection. |
| Multiple intents in one invocation | Drafter detects and refuses with clear error: "Multiple intents detected. Run /agentic-dev:intent once per goal." Anti-eagerness. |
| Re-running `/agentic-dev:intent` with same text | Idempotent by intent ID. If `intents/<id>.md` exists, skill prints existing spec path and exits. Use `--refine` to force re-draft. |

## 10. Testing strategy

Three layers, building on P1's infrastructure.

### 10.1 Pure deterministic unit tests (no Claude calls)

- `tests/phase-2/validate_spec_test.py` — feeds the deterministic validator a battery of good/bad spec fixtures. Asserts exit codes and error messages.
- `tests/phase-2/spec_schema_test.py` — validates spec frontmatter fixtures against `spec.schema.json`.

### 10.2 End-to-end skill tests (`claude -p`-driven, billed)

- `tests/phase-2/intent_fresh_test.sh` — runs `/agentic-dev:intent "..."` in a throwaway init'd project; asserts intent file written, spec file written with the expected sections and QUESTION-N count, frontmatter `approved: false`.
- `tests/phase-2/intent_refine_test.sh` — pre-populates a partial spec, runs `--refine`; asserts existing answers preserved, no overwrites.
- `tests/phase-2/approval_gate_test.sh` — drives a spec from drafted → all-answered → `approved: true`; asserts deterministic block on remaining QUESTIONs, AI dispatch on clean approval, new QUESTIONs appear if AI finds concerns.

### 10.3 Adversarial fixture tests (AI validator only)

- `tests/phase-2/fixtures/spec-unmeasurable-criteria.md` — completion criterion "system is fast"; assert AI returns `concerns` with `completion-criterion`.
- `tests/phase-2/fixtures/spec-scope-incoherent.md` — intent contradicts out-of-scope; assert AI returns `concerns` with `scope-coherence`.
- `tests/phase-2/fixtures/spec-clean.md` — fully clean spec; assert AI returns `clean`.

### 10.4 Infrastructure carryover from P1

- `KEEP_TMP=1` escape hatch on all shell tests.
- `--add-dir` + `--dangerously-skip-permissions` for headless `claude -p`.
- `~/.claude/agentic-dev-test.env` env-file convention for API auth.
- `tests/phase-2/run_all.sh` aggregator. (P1's stays as-is.)
- `tests/requirements.txt` covers Python deps already.

Budget: ~10 `claude -p` invocations per full `run_all.sh`; ~$2–3 per run.

## 11. Load-bearing properties for P2

Extending spec §20's L1–L10 with phase-specific properties:

- **P2-L1** — Drafting state lives on disk continuously. Step-away resumability is intrinsic. No conversation context is load-bearing.
- **P2-L2** — Drafter never writes files. Only the lifecycle skill writes. Boundary enforced by subagent tool list (no `Write`/`Edit`).
- **P2-L3** — `approved: true` cannot be set while QUESTION-N blocks remain. Deterministic check; hook-enforced.
- **P2-L4** — AI validator concerns become new QUESTION-N blocks, never silent rejections. The edit loop continues in-place.
- **P2-L5** — Drafter is forbidden from improvising. Calibration table is the closed set of behaviors; default-to-flag for anything outside.
- **P2-L6** — Multi-intent inputs are refused, never split silently. Anti-eagerness.
- **P2-L7** — `--refine` never overwrites a human's answer. Idempotent re-runs preserve state.

## 12. Scope of P2 v1 build

1. **Schemas** — `agentic-dev/schemas/spec.schema.json` (frontmatter) + validation tests.
2. **Skills** — `/agentic-dev:intent` (main + `--refine` mode), `/agentic-dev:_check-approval` (internal, prefixed with `_` to signal hook-triggered; orchestrates AI validator dispatch and concern-writing).
3. **Subagents** — `spec-drafter` (calibration table prompt + structured-output contract), `spec-validator-ai` (read-only judgment prompt + structured-output contract).
4. **Hook wiring** — `hooks/hooks.json` registering `PostToolUse` on `Write|Edit` matching `.claude/agentic/specs/*.md` → `bin/validate-spec.sh`. On detected approval flip, also invokes the check-approval skill.
5. **Deterministic validator script** — `bin/validate-spec.sh` (per §8.1 checks).
6. **Spec + intent file templates** baked into the drafter prompt.
7. **Tests** — three layers per §10.
8. **README + CHANGELOG updates** — plugin README adds `/agentic-dev:intent` and `--refine` to usage; CHANGELOG records v0.2.0.

### Descopable for a v0.2-alpha (if compression needed)

- AI validator (§8.2 + §8.3). Ship deterministic-only; AI half becomes v0.2.1.
- `--refine` mode. Ship single-shot; refine becomes v0.2.1.
- Adversarial fixture tests (§10.3). Defer until AI validator ships.

## 13. Open questions / out-of-scope for v1

- **P1-DEF-001 deferred again** — queue.yaml stays untouched. Will resurface when P3 implementer subagent or P6 queue runner needs new fields on goal items.
- **AI validator failure handling is minimal.** Logs and warns; doesn't escalate. P5's escalation infrastructure addresses this rigorously.
- **No mechanism yet for human to reject a spec entirely.** Setting `approved: false` and adding a top-level `<!-- ABANDONED -->` comment is the working convention; a proper `/agentic-dev:abandon` skill is P-later territory.
- **Validator AI same-model bias.** P5 will introduce cross-model review options; P2's validator is acceptable since it's bounded to a narrow check (measurability + scope-coherence) and writes back into the user's edit loop rather than auto-rejecting.

## 14. References

- Umbrella spec: `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md`
- P1 design and plan: `docs/superpowers/plans/2026-05-20-agentic-dev-phase-1-plugin-skeleton.md`
- DEFERRED items: `DEFERRED.md` at repo root
- Anthropic plugin docs: https://code.claude.com/docs/en/plugins
