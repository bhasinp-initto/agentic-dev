# Deferred Items

Items deferred during implementation that the next phase (or future phase) should address. Each entry includes the source review, the deferral reason, and a target phase.

This file is the single source of truth for tech debt across phases. Add to it whenever a code review surfaces something that's deferred rather than fixed-in-place.

---

## From Phase 1 → P2 attention required

### P1-DEF-001 — Queue goal schema extension strategy

**Source:** Phase 1 final holistic code review.
**What:** `agentic-dev/schemas/queue.schema.json` uses `additionalProperties: false` on goal items. Allowed fields today: `id`, `status`, `spec_path`, `intent_path`, `added_at`. P2's `/agentic-dev:intent` skill will likely need to add fields (`started_at`, `budget_overrides`, `worktree_path`, etc.) to goal items.
**Decision required:** Either bump `schema_version` to `"0.2"` and add fields explicitly, OR relax `additionalProperties` to `false` only at the top-level queue, not on goal items.
**Target:** P3-T1 (deferred from P2 — P2 didn't touch queue.yaml so the decision didn't surface). Must decide before writing any code that adds new fields to goal items.

---

## From Phase 1 → P2/P5 testing extensions

### P1-DEF-002 — Halted-state SKILL.md display block lacks integration test

**Source:** T4 code review.
**What:** `agentic-dev/skills/status/SKILL.md` specifies that when `circuit_breaker.state == "halted"`, the status output appends a halt block (reason, at, goal). No test exercises this — the schema's positive halted-state fixture validates the SHAPE but no `status_test` invocation drives a halted state through `/agentic-dev:status`.
**Target:** P5 (when escalation/halt logic ships) — add a `status_test_halted.sh` or extend `status_test.sh` with a second pre-populated state.

### P1-DEF-003 — No worktree-based integration tests yet

**Source:** Phase 1 spec §18.
**What:** Worktree-per-session isolation (Nimbalyst pattern borrowed) is part of the design but no Phase 1 test creates or exercises worktrees. P3 (implementer subagent) will introduce them.
**Target:** P3.

---

## From Phase 1 → P2 deferred polish

### P1-DEF-004 — Smoke assertions are fail-fast, not fail-accumulate

**Source:** T5 code review.
**What:** `tests/phase-1/smoke_test.sh` uses `exit 1` on first failed grep assertion, vs. `status_test.sh` which accumulates with `ok=0` and reports all failures before exiting. Fail-accumulate gives better signal during iteration.
**Target:** P3 test polish (deferred from P2; low priority).

### P1-DEF-005 — Cost claim in tests/README.md is approximate

**Source:** T5 code review.
**What:** README says "well under a dollar" for a full `run_all.sh`. Dispatch brief said budget $1–$2. Empirical usage so far is $0.50–$1 per full run. Refine the claim with observed data once more runs accumulate.
**Target:** P3 or whenever observations stabilize (deferred from P2).

### P1-DEF-006 — `run_all.sh` doesn't emit machine-readable failure attribution

**Source:** T5 code review.
**What:** `run_all.sh` halts on first child test failure via `set -euo pipefail`. The last section header printed tells you which test failed (human-readable), but no machine-readable "FAILED: init_test" line is emitted for CI parsers.
**Target:** When CI is added (Phase 8).

### P1-DEF-007 — Refactor Python heredocs into a shared schema-validation helper

**Source:** T2 code review.
**What:** `tests/phase-1/init_test.sh` has three nearly-identical Python heredocs that load a schema, parse a YAML/JSON file, and validate. Factoring into `tests/lib/validate-schema.py` would reduce duplication.
**Target:** P3 or whenever a fourth state file is added to the test surface (deferred from P2).

### P1-DEF-008 — SKILL.md "Do NOT" sections use English not tool-level constraints

**Source:** T4 code review.
**What:** `agentic-dev/skills/status/SKILL.md` says "Do not modify any files" — would be more robust as "Do not use the Write, Edit, or Bash tools." Same for the implementer subagent's status-like read-only roles in later phases.
**Target:** When the hardened-reviewer subagent ships (P5) — apply the tool-level constraint pattern consistently.

---

## From Phase 2 → future polish

### P2-DEF-001 — Drafter response parsing should tolerate leading whitespace

**Source:** T2 code review.
**What:** `skills/intent/SKILL.md` checks if drafter output begins with `---` literally. A leading newline or whitespace causes a false rejection even though the drafter's output contract forbids such output. Low probability but worth `.lstrip()` in the parsing logic.
**Target:** v0.2.x polish.

### P2-DEF-002 — Drafter dispatch prompt format inconsistency

**Source:** T2 code review.
**What:** `agents/spec-drafter.md` says `config_defaults` is "JSON"; `skills/intent/SKILL.md` sends it as YAML-style bullet list. Both parse via LLM, but the documentation mismatch makes the contract unclear. Pick one format and align.
**Target:** v0.2.x polish.

### P2-DEF-003 — `must_exist()` is dead code in intent_fresh_test.sh

**Source:** T2 code review.
**What:** Defined at lines 43–50, never invoked. Use it for the file-existence checks or delete it.
**Target:** v0.2.x polish.

### P2-DEF-004 — Validator's intent_path fallback uses `dirname × 4` hardcode

**Source:** T3 code review.
**What:** `agentic-dev/bin/validate-spec.sh`'s project-root derivation for the intent_path fallback hardcodes 4 levels of `os.path.dirname` based on the canonical spec path `.claude/agentic/specs/<file>.md`. If a future phase introduces nested spec directories (e.g., `specs/p3/<file>.md`), the fallback will yield the wrong project root. A robust replacement would walk upward looking for the `.claude/agentic` directory.
**Target:** v0.2.x or whenever spec directory structure changes.

### P2-DEF-005 — Refine test does not verify preservation of multiple answered questions

**Source:** T4 code review.
**What:** `tests/phase-2/intent_refine_test.sh` answers only QUESTION-1 and verifies only QUESTION-1's preservation. A drafter regression that renumbers or paraphrases QUESTION-2+ would go undetected. Worth extending to answer two questions and verify both survive.
**Target:** v0.2.x polish.

### P2-DEF-006 — Refine test regex against bold-markup drift

**Source:** T4 code review.
**What:** The Python heredoc in `intent_refine_test.sh` uses `re.sub` to patch QUESTION-1's "Your answer" line, with a regex that matches exact `**Your answer:**`. If the drafter ever emits surrounding whitespace or a slightly different markup, the regex silently no-ops and the test produces a misleading FAIL on the preservation check. Add `assert new_text != text` after the substitution, or use a looser pattern.
**Target:** v0.2.x polish.

### P2-DEF-007 — Refine idempotency: stable output on re-run with no answer changes

**Source:** T4 code review.
**What:** Running `--refine` twice without changing answers should produce stable output (no question-count churn, no renumbering). The "never delete, never modify" rules imply this, but it is not stated explicitly or tested. mtime changes on every run regardless of content identity.
**Target:** v0.2.x polish.

### P2-DEF-008 — Conditional question deletion in refine

**Source:** T4 code review.
**What:** `spec-drafter.md`'s refine rule `Never deletes a QUESTION-N block` is absolute. If Q3 picks branch A and Q4 only makes sense in branch B, Q4 survives forever. This is intentionally conservative. Worth a comment in the spec-drafter prompt acknowledging this is a known UX limitation.
**Target:** v0.3 or later if conditional question trees become a real need.

### P2-DEF-009 — approval_gate_test.sh: CWD leak after run_one cleanup

**Source:** T5 code review.
**What:** After `run_one` returns, the RETURN trap deletes `$TMP_PROJECT`, but the script's CWD is now a deleted directory. Bash on macOS holds the inode so it doesn't fail immediately, but `pwd` would error. The next `run_one` does `cd "$TMP_PROJECT"` to a fresh absolute path, so the script recovers. Worth a `cd "$REPO_ROOT"` between calls, or running `run_one` in a subshell.
**Target:** v0.2.x polish.

### P2-DEF-010 — approval_gate_test.sh: QUESTION-N assertion not isolated to new blocks

**Source:** T5 code review.
**What:** `grep -qE '<!-- QUESTION-[0-9]+ '` matches ANY QUESTION block, including ones pre-existing in the fixture. Current fixtures have no pre-existing QUESTIONs so the assertion correctly validates that a new one was added. If a future fixture ships with QUESTIONs already present, this assertion would pass even if the skill added no new blocks.
**Target:** v0.2.x polish.

---

## How to use this file

- New items: add a section under the appropriate "From Phase N" heading. Include source review, what, and target phase.
- Closing an item: when a deferred item is addressed in a later phase, mark it `[CLOSED in Phase N — commit SHA]` rather than deleting, so the audit trail is preserved.
- The DEFERRED.md is read by the spec drafter at the start of each phase (per spec §13's cross-session memory pattern) so deferrals don't slip.
