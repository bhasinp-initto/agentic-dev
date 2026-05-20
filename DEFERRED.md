# Deferred Items

Items deferred during implementation that the next phase (or future phase) should address. Each entry includes the source review, the deferral reason, and a target phase.

This file is the single source of truth for tech debt across phases. Add to it whenever a code review surfaces something that's deferred rather than fixed-in-place.

---

## From Phase 1 → P2 attention required

### P1-DEF-001 — Queue goal schema extension strategy

**Source:** Phase 1 final code review (commit `64cdea4` review).
**What:** `agentic-dev/schemas/queue.schema.json` uses `additionalProperties: false` on goal items. Allowed fields today: `id`, `status`, `spec_path`, `intent_path`, `added_at`. P2's `/agentic-dev:intent` skill will likely need to add fields (`started_at`, `budget_overrides`, `worktree_path`, etc.) to goal items.
**Decision required:** Either bump `schema_version` to `"0.2"` and add fields explicitly, OR relax `additionalProperties` to `false` only at the top-level queue, not on goal items.
**Target:** P2-T1 (first task of Phase 2) — decide before writing any code that writes goals.

---

## From Phase 1 → P2/P5 testing extensions

### P1-DEF-002 — Halted-state SKILL.md display block lacks integration test

**Source:** T4 code review (commit `1cc05ee`).
**What:** `agentic-dev/skills/status/SKILL.md` specifies that when `circuit_breaker.state == "halted"`, the status output appends a halt block (reason, at, goal). No test exercises this — the schema's positive halted-state fixture validates the SHAPE but no `status_test` invocation drives a halted state through `/agentic-dev:status`.
**Target:** P5 (when escalation/halt logic ships) — add a `status_test_halted.sh` or extend `status_test.sh` with a second pre-populated state.

### P1-DEF-003 — No worktree-based integration tests yet

**Source:** Phase 1 spec §18.
**What:** Worktree-per-session isolation (Nimbalyst pattern borrowed) is part of the design but no Phase 1 test creates or exercises worktrees. P3 (implementer subagent) will introduce them.
**Target:** P3.

---

## From Phase 1 → P2 deferred polish

### P1-DEF-004 — Smoke assertions are fail-fast, not fail-accumulate

**Source:** T5 code review (commit `0ea7210`).
**What:** `tests/phase-1/smoke_test.sh` uses `exit 1` on first failed grep assertion, vs. `status_test.sh` which accumulates with `ok=0` and reports all failures before exiting. Fail-accumulate gives better signal during iteration.
**Target:** Phase 2 test polish (low priority).

### P1-DEF-005 — Cost claim in tests/README.md is approximate

**Source:** T5 code review.
**What:** README says "well under a dollar" for a full `run_all.sh`. Dispatch brief said budget $1–$2. Empirical usage so far is $0.50–$1 per full run. Refine the claim with observed data once more runs accumulate.
**Target:** Phase 2 or whenever observations stabilize.

### P1-DEF-006 — `run_all.sh` doesn't emit machine-readable failure attribution

**Source:** T5 code review.
**What:** `run_all.sh` halts on first child test failure via `set -euo pipefail`. The last section header printed tells you which test failed (human-readable), but no machine-readable "FAILED: init_test" line is emitted for CI parsers.
**Target:** When CI is added (Phase 8).

### P1-DEF-007 — Refactor Python heredocs into a shared schema-validation helper

**Source:** T2 code review (commit `61c563a`).
**What:** `tests/phase-1/init_test.sh` has three nearly-identical Python heredocs that load a schema, parse a YAML/JSON file, and validate. Factoring into `tests/lib/validate-schema.py` would reduce duplication.
**Target:** P2 or whenever a fourth state file is added to the test surface.

### P1-DEF-008 — SKILL.md "Do NOT" sections use English not tool-level constraints

**Source:** T4 code review.
**What:** `agentic-dev/skills/status/SKILL.md` says "Do not modify any files" — would be more robust as "Do not use the Write, Edit, or Bash tools." Same for the implementer subagent's status-like read-only roles in later phases.
**Target:** When the hardened-reviewer subagent ships (P5) — apply the tool-level constraint pattern consistently.

---

## How to use this file

- New items: add a section under the appropriate "From Phase N" heading. Include source review, what, and target phase.
- Closing an item: when a deferred item is addressed in a later phase, mark it `[CLOSED in Phase N — commit SHA]` rather than deleting, so the audit trail is preserved.
- The DEFERRED.md is read by the spec drafter at the start of each phase (per spec §13's cross-session memory pattern) so deferrals don't slip.
