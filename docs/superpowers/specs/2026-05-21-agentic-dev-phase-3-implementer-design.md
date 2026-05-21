# Phase 3 — Implementer Subagent + Worktree Isolation Design

**Status:** Draft (autonomous decision-mode per user authorization)
**Date:** 2026-05-21
**Phase:** P3 of P1–P8
**Umbrella spec:** `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` (§4 Role 3, §6.2 Kickoff, §6.3 Implementation, §6.4 Manifest, §18 Worktree borrowing)

---

## 1. Intent

Phase 3 ships the implementer subagent — Role 3 of the three-role pattern — with worktree-per-goal isolation. Given an approved spec, the implementer writes code in a dedicated git worktree, follows test-driven discipline, asks the orchestrator (or human, in P3 alone) for clarifications when the spec is ambiguous rather than guessing, and produces a structured completion manifest. After P3 ships, an approved spec can be translated into committed code in a worktree by dispatching one subagent — but the implementer cannot push, cannot touch the main repo's working tree, and cannot decide whether its work is "done" (that's the reviewer's job in P5).

## 2. Goals

- **G1** — Implement the `implementer-strict` subagent with an anti-eagerness calibration prompt that mirrors the drafter's discipline but for code-writing.
- **G2** — Worktree-per-goal isolation: each goal runs in `.worktrees/goal-<id>/` (Nimbalyst pattern from umbrella §18) so cross-goal interference is impossible.
- **G3** — Resolve **P1-DEF-001** (queue goal schema extension strategy): bump `queue.schema.json` to v0.2 with explicit new goal-item fields (per user decision).
- **G4** — Add `manifest.schema.json` and `diff-envelope.schema.json` (umbrella §6.4 + §18 structured-diff pattern).
- **G5** — Worktree lifecycle management: `bin/worktree-init.sh`, `bin/worktree-cleanup.sh`, plus a `/agentic-dev:_run-implementer` skill (internal, orchestrator-only invocation) that wires the lifecycle: kickoff package → dispatch implementer → capture manifest.
- **G6** — Preserve test-cost discipline per `docs/superpowers/test-cost-policy.md`: deterministic-first; one agent-dispatched smoke per phase.

## 3. Non-goals

- Build the orchestrator that drives `_run-implementer` autonomously — that's P6.
- Deterministic gates that check the implementer's output (scope/budget/sensitive-path) — that's P4.
- Reviewer of implementer output — P5.
- Telegram notifications on implementer events — P5.
- Persistent queue state updates from implementer (writing `running` status, etc.) — orchestrator's responsibility, P6.
- Cross-goal parallel execution — design supports it (worktree per goal), but P3 runs goals sequentially.

## 4. Architecture

```
agentic-dev/
├── skills/
│   ├── init/SKILL.md             (existing, P1)
│   ├── status/SKILL.md           (existing, P1)
│   ├── intent/SKILL.md           (existing, P2)
│   ├── _check-approval/SKILL.md  (existing, P2)
│   └── _run-implementer/SKILL.md NEW — internal lifecycle for one goal
├── agents/
│   ├── spec-drafter.md           (existing, P2)
│   ├── spec-validator-ai.md      (existing, P2)
│   └── implementer-strict.md     NEW — implementer subagent
├── bin/
│   ├── validate-spec.sh          (existing, P2)
│   ├── worktree-init.sh          NEW — create worktree from main branch + write kickoff
│   ├── worktree-cleanup.sh       NEW — remove worktree (clean-only; preserved on halt)
│   └── migrate-v0.1-to-v0.2.sh   NEW — queue.yaml schema migration helper
├── schemas/
│   ├── state.schema.json         (existing, P1)
│   ├── queue.schema.json         MODIFIED — v0.2 with new goal-item fields
│   ├── config.schema.json        (existing, P1)
│   ├── spec.schema.json          (existing, P2)
│   ├── manifest.schema.json      NEW — completion manifest schema
│   └── diff-envelope.schema.json NEW — structured diff schema
└── hooks/hooks.json              (existing, P2 — unchanged in P3)
```

### Component roles

- **`/agentic-dev:_run-implementer <spec-path>` (internal skill).** Reads the approved spec, computes the goal-id, runs `worktree-init.sh` to create `.worktrees/goal-<id>/`, dispatches `implementer-strict` with the kickoff package, captures the returned manifest, writes it to `.claude/agentic/manifests/<goal-id>.json`. Does NOT decide if the work is "done" — that's the reviewer in P5. Marked `_` prefix because it's intended for orchestrator use, not direct human invocation (though human can run it for testing).

- **`implementer-strict` (subagent).** Has Read, Edit, Write, Glob, Grep, Bash. Operates ONLY inside the worktree path passed in the kickoff. Follows TDD discipline (test first → run → fail → implement → run → pass → commit). Asks via `clarifying_questions` in the manifest when spec doesn't answer something. Never commits to main; never pushes. Writes manifest at the end (or partial manifest on halt). Calibration table in §6.

- **`bin/worktree-init.sh`.** Reads the spec's `id`, creates `.worktrees/goal-<id>/` via `git worktree add` from current HEAD. Writes the kickoff package JSON at `.worktrees/goal-<id>/.agentic-kickoff.json` for the implementer to read. Outputs the worktree path.

- **`bin/worktree-cleanup.sh`.** Removes a worktree by id. Only used on clean goal completion. Halts preserve the worktree (forensic-friendly per umbrella §11).

- **`bin/migrate-v0.1-to-v0.2.sh`.** One-shot script that migrates an existing `.claude/agentic/queue.yaml` from v0.1 to v0.2 (adds missing optional fields as null; bumps schema_version). Idempotent; safe to run multiple times.

### Read/write boundaries (load-bearing)

| Component | Reads | Writes |
|---|---|---|
| `_run-implementer` skill | spec file, config | manifest file, optional state update |
| `implementer-strict` subagent | spec, repo (inside worktree), kickoff package | files inside worktree, manifest |
| `worktree-init.sh` | spec, current HEAD | `.worktrees/goal-<id>/` (git worktree), kickoff package |
| `worktree-cleanup.sh` | nothing (just removes) | nothing (removes the worktree directory) |
| Migration script | queue.yaml | queue.yaml (rewritten with new schema_version) |

Only the lifecycle skill writes the manifest. The implementer's structured output IS the manifest content; the skill writes it to disk.

## 5. Schema work (P1-DEF-001 resolution)

Per user decision: bump `queue.schema.json` to `schema_version: "0.2"` with explicit new goal-item fields.

### v0.2 goal-item additions

```json
{
  "id": "...",                      // existing (v0.1)
  "spec_path": "...",               // existing
  "intent_path": "...",             // existing
  "status": "...",                  // existing
  "added_at": "...",                // existing
  "started_at": "...",              // NEW: when status transitioned to running
  "completed_at": "...",            // NEW: when status transitioned to completed
  "halted_at": "...",               // NEW: when status transitioned to halted
  "baseline_ref": "...",            // NEW: git SHA at start of work
  "head_ref": "...",                // NEW: git SHA at end of work (or halt)
  "worktree_path": "...",           // NEW: ".worktrees/goal-<id>"
  "manifest_path": "...",           // NEW: ".claude/agentic/manifests/<id>.json"
  "budget_overrides": {...}         // NEW: optional per-goal budget override
}
```

All new fields are optional in the schema (only present once a goal has progressed past `approved`). `additionalProperties: false` is preserved on goal items (still tight validation).

### Migration script behavior

- Reads existing `queue.yaml`.
- If `schema_version: "0.1"`: bumps to `"0.2"`. Existing goal items already valid since new fields are optional.
- If `schema_version: "0.2"`: no-op.
- Validates result against new schema before writing.

### `state.schema.json` — no changes in P3

The state file (orchestrator state + circuit breaker) stays at v0.1. The implementer doesn't modify it; that's the orchestrator's job in P6.

## 6. Implementer calibration

The `implementer-strict` subagent's system prompt encodes a fixed behavior table. Mirrors the drafter's anti-eagerness pattern but for code-writing.

| Situation | Behavior |
|---|---|
| Spec's "Files in scope" is missing or empty | Halt with `clarifying_question` — refuse to start. |
| File you want to touch is outside "Files in scope" | Halt with `clarifying_question` asking for scope amendment. Never silently expand scope. |
| Test you'd write to verify behavior X is unclear (e.g., spec doesn't say what the API should return) | Halt with `clarifying_question`. Never guess at expected outputs. |
| You need a tool/library/dependency the spec doesn't mention | Halt with `clarifying_question`. Do NOT add dependencies without explicit approval. |
| You hit a budget threshold (diff_lines or files_touched within 80% of cap) | Halt with `clarifying_question` asking whether to continue, descope, or escalate. |
| A test fails | Report it honestly in the manifest under `tests.failed`. If it's a test you just wrote, that's expected during TDD red phase. If it's an existing test that broke, INVESTIGATE before continuing. |
| An existing "pre-existing" failing test you didn't break | Note in manifest's `deferrals` with `reason: pre-existing failure unrelated to this goal`. Do NOT mask it. |
| Wall-clock approaches budget limit | Write partial manifest with `status: interrupted` and what's done so far; halt. |
| You complete a logical unit | Run the spec's test command. If pass, commit (in worktree, not main). Use commit message format: `[<goal-id>] <one-line summary>`. |
| You finish all in-scope work AND all tests pass AND lint/typecheck pass | Write final manifest with `status: complete`. Do NOT mark the goal "done" — that's the reviewer's call. |

The implementer is FORBIDDEN from:
- Touching files outside the worktree
- Committing to main branch (operates entirely in worktree)
- Pushing to remote (ever)
- Modifying `.claude/agentic/queue.yaml`, `state.json`, or any other orchestrator state
- Editing `.claude/agentic/specs/<id>.md` (the spec is read-only to the implementer; spec_change_requests go in the manifest, not by editing)
- Running the AI validator or any other subagent (single-layer dispatch only)
- Adding new dependencies without an explicit spec entry permitting them

## 7. Lifecycle

### Path A — Clean run (approved spec → committed work + manifest)

```
1. Caller (orchestrator in P6, test in P3) invokes:
   /agentic-dev:_run-implementer .claude/agentic/specs/<goal-id>.md

2. Skill reads spec; verifies approved: true; reads goal-id and budget.

3. Skill calls bin/worktree-init.sh <goal-id>:
   - Creates .worktrees/goal-<id>/ from current HEAD
   - Writes .worktrees/goal-<id>/.agentic-kickoff.json with:
     { goal_id, spec_path, baseline_ref, budget, sensitive_paths,
       project_commands (test, lint, typecheck from config.yaml) }

4. Skill dispatches implementer-strict subagent:
   - Working directory: .worktrees/goal-<id>/
   - Prompt includes: "Read .agentic-kickoff.json, then begin implementation
     per the spec. Follow your calibration table strictly. When done, output
     your manifest as a JSON object."

5. Implementer:
   a. Reads kickoff + spec
   b. Plans the test cases needed
   c. Writes failing tests (TDD red)
   d. Implements minimal code (TDD green)
   e. Runs tests; iterates if needed
   f. Runs lint/typecheck if configured
   g. Commits in worktree (not main) with [<goal-id>] prefix
   h. Repeats c-g for each logical unit
   i. When all in-scope work done + all tests pass + lint clean: writes final manifest

6. Skill captures manifest JSON, validates against manifest.schema.json, writes to:
   .claude/agentic/manifests/<goal-id>.json

7. Skill prints summary: goal-id, manifest path, diff stats, test counts,
   clarifying questions (if any), deferrals (if any). Exits.

8. (Out of P3 scope: reviewer runs on the manifest in P5.)
```

### Path B — Halt on ambiguity

```
1-4. Same as above.

5. Implementer encounters ambiguity (e.g., spec doesn't say what error code
   to return for a specific edge case):
   - Stops work
   - Writes partial manifest with status: blocked-on-clarification
   - clarifying_questions array contains the question(s)

6. Skill writes the partial manifest. Prints summary noting:
   - Goal status: blocked
   - N clarifying questions awaiting resolution
   - Resolution path: human edits the spec to answer; re-run /agentic-dev:_run-implementer
     (or, in P6, orchestrator escalates)
```

### Path C — Halt on budget

```
1-4. Same as Path A.

5. Implementer hits budget (e.g., 80% of diff_lines_max):
   - Stops at the next clean commit boundary
   - Writes partial manifest with status: blocked-on-budget
   - clarifying_questions might include "continue with more budget?" or
     "descope to subset?"

6. Skill writes partial manifest. Worktree is preserved for inspection.
```

## 8. Manifest schema

Required fields:

```json
{
  "schema_version": "0.1",
  "goal_id": "2026-05-21-add-rate-limiting",
  "spec_path": ".claude/agentic/specs/2026-05-21-add-rate-limiting.md",
  "worktree_path": ".worktrees/goal-2026-05-21-add-rate-limiting",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "status": "complete | blocked-on-clarification | blocked-on-budget | interrupted",
  "started_at": "2026-05-21T10:00:00Z",
  "completed_at": "2026-05-21T10:45:00Z",
  "diff_stats": {
    "files_touched": 7,
    "lines_added": 142,
    "lines_removed": 11
  },
  "tests": {
    "ran": 28,
    "passed": 28,
    "failed": 0,
    "skipped": 1,
    "logs_path": ".worktrees/goal-.../test-output.log"
  },
  "self_check": {
    "lint": "clean | failures | not-run",
    "typecheck": "clean | failures | not-run | n/a"
  },
  "scope_check": {
    "in_spec_files": ["..."],
    "out_of_spec_files": []
  },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [
    {
      "question": "Should rate limits include 429 Retry-After header?",
      "resolved_by": "spec_text | escalated | pending",
      "answer": "..."
    }
  ],
  "artifacts": [
    { "kind": "test_output", "path": "..." }
  ],
  "commits": [
    { "sha": "...", "subject": "[<goal-id>] add /health endpoint" }
  ]
}
```

`scope_check.out_of_spec_files` MUST be `[]` for a clean manifest. Any out-of-spec file appearing means the implementer broke its scope discipline — P4's deterministic gate catches this and escalates.

## 9. Diff envelope schema

The structured diff format borrowed from Nimbalyst. Stored alongside the manifest at `.claude/agentic/diffs/<goal-id>.json`:

```json
{
  "schema_version": "0.1",
  "goal_id": "...",
  "baseline_ref": "...",
  "head_ref": "...",
  "generated_at": "...",
  "files": [
    {
      "path": "src/routes/health.ts",
      "change_kind": "added | modified | deleted | renamed",
      "lines_added": 18,
      "lines_removed": 0,
      "hunks": [
        { "old_start": 0, "old_count": 0, "new_start": 1, "new_count": 18, "content": "..." }
      ]
    }
  ],
  "raw_patch": "<git diff output>"
}
```

P3 generates this as part of the skill's manifest-capture phase, NOT inside the implementer. The skill runs `git diff --stat` and `git diff` on the worktree against `baseline_ref` after the implementer returns.

The skill that writes diff envelopes for `_run-implementer` will be reusable in P5 (reviewer reads diffs) and P8 (release packaging).

## 10. Error handling

| Failure | Handling |
|---|---|
| Worktree already exists for the goal-id | Refuse to overwrite. Print clear error suggesting cleanup. |
| Spec not approved (approved: false) | Refuse with clear error. |
| Spec has unresolved QUESTION-N blocks (somehow approved=true slipped through) | Refuse; this is a deterministic-validator bypass — report and escalate. |
| Implementer subagent returns non-JSON output | Skill captures the response, writes a partial manifest with status: implementer-output-malformed; preserves worktree; logs to `.claude/agentic/validation-log.txt`. |
| Implementer's manifest fails JSON Schema validation | Skill writes the malformed manifest to a debug location; logs; flags for human inspection. |
| Implementer crashes mid-implementation (subagent error) | Worktree is preserved with whatever state it had. Skill writes partial manifest. |
| Worktree commit fails (git error) | Implementer notes in manifest's deferrals; halt at last clean commit. |
| Wall-clock budget exhausted | Implementer halts at next commit boundary (or immediately) with partial manifest. |

## 11. Testing strategy (per cost policy)

### 11.1 Deterministic tests (run on every `run_all.sh`)

- `tests/phase-3/queue_schema_v02_test.py` — validates queue.yaml v0.2 fixtures (good cases + negative cases for new fields).
- `tests/phase-3/manifest_schema_test.py` — validates manifest fixtures + 3-4 negative cases (wrong status enum, missing required fields, malformed dates).
- `tests/phase-3/diff_envelope_schema_test.py` — validates diff envelope fixtures.
- `tests/phase-3/migration_test.sh` — runs `bin/migrate-v0.1-to-v0.2.sh` on a v0.1 fixture; asserts v0.2 result validates against new schema; verifies idempotency.
- `tests/phase-3/worktree_init_test.sh` — runs `bin/worktree-init.sh` in a tmp git repo; verifies worktree created, kickoff file present, kickoff JSON validates against expected shape.
- `tests/phase-3/worktree_cleanup_test.sh` — runs cleanup; verifies worktree removed; verifies it refuses to clean a halted-state worktree (per policy).
- `tests/phase-3/implementer_structure_test.py` — parses `agents/implementer-strict.md`; asserts frontmatter has correct tools list, calibration table has required rows, anti-eagerness rules present.
- `tests/phase-3/run_implementer_skill_structure_test.py` — parses `skills/_run-implementer/SKILL.md`; asserts pre-checks, dispatch logic, manifest-capture, error-path handling.

### 11.2 Agent-dispatched smoke (controller-driven, no API cost)

ONE smoke test where I (the controller) dispatch the implementer-strict subagent against a tiny synthetic spec to verify end-to-end:
- Create a throwaway tmp project
- Init it with /agentic-dev:init (via subagent dispatch, not claude -p)
- Hand-author a tiny approved spec for a trivial goal (e.g., "add a hello.txt file with content 'hi'")
- Dispatch implementer with the kickoff
- Verify manifest produced + worktree state + tests pass

Run via the controller during P3-T6 final verification, not in `run_all.sh`.

### 11.3 No `claude -p` tests in P3

P3 has zero `claude -p` test invocations. All implementer behavior is tested either:
- Structurally (file parsing, schema validation, prompt-content checks)
- Via Agent dispatch in the controller (Max-billed, no API cost)

Estimated API spend for P3 dev: **<$2** (mostly small dispatches during iteration).

## 12. Load-bearing properties

- **P3-L1** — Implementer operates only inside the worktree path passed in kickoff. Out-of-worktree writes are forbidden by prompt; would be a critical bug.
- **P3-L2** — Implementer never commits to main, never pushes. Commits live in the worktree until merged by the orchestrator/human.
- **P3-L3** — Worktree per goal: cross-goal interference is structurally impossible (different git worktrees, different filesystem subtrees).
- **P3-L4** — Halt on ambiguity, never guess. The manifest's `clarifying_questions_asked` is the load-bearing escape valve.
- **P3-L5** — Honest test reporting: failed tests appear in `tests.failed`, not paper over. Pre-existing failures explicitly flagged in `deferrals`.
- **P3-L6** — Out-of-scope files appear in `scope_check.out_of_spec_files`. P4's gate uses this to escalate; the implementer's self-discipline is the first line of defense.
- **P3-L7** — Manifest schema is the structured contract; the implementer's output must validate against it. Malformed output halts the lifecycle skill.

## 13. Scope of P3 v1 build

1. **Schemas v0.2** — `queue.schema.json` bumped; `manifest.schema.json` + `diff-envelope.schema.json` created; deterministic tests.
2. **Migration script** — `bin/migrate-v0.1-to-v0.2.sh` + migration test.
3. **Worktree management** — `bin/worktree-init.sh`, `bin/worktree-cleanup.sh` + tests.
4. **Implementer subagent** — `agents/implementer-strict.md` with the calibration table.
5. **Lifecycle skill** — `skills/_run-implementer/SKILL.md`.
6. **Tests** — per §11. All deterministic; one controller-driven smoke at the end.
7. **README + CHANGELOG** updates for v0.3.0.
8. **DEFERRED.md** — close P1-DEF-001 (resolved by P3-T1); record any new deferrals.

## 14. Out of scope (P3) — deferred to later

- Deterministic gates that consume the manifest (scope, budget, sensitive-path enforcement) — P4.
- Reviewer subagent that reads the manifest + diff envelope — P5.
- Hardened-reviewer's adversarial second pass — P5.
- Telegram notifications on implementer events — P5.
- Auto-firing `_run-implementer` from the queue — P6.
- Self-improving checklist updates from implementer-flagged incidents — P7.

## 15. References

- Umbrella spec: `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md`
- P2 design: `docs/superpowers/specs/2026-05-20-agentic-dev-phase-2-spec-drafter-design.md`
- Test-cost policy: `docs/superpowers/test-cost-policy.md`
- DEFERRED items: `DEFERRED.md` (P1-DEF-001 must be closed by P3-T1)
