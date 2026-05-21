# Changelog

All notable changes to `agentic-dev` are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.4.0] — 2026-05-21

Deterministic verification gates ship. The implementer's manifest claims (scope, budget, test counts) are now checked independently against actual worktree state. No AI in this layer — that's P5.

### Added
- `bin/gate-scope-check.sh` — verifies touched files against spec's "Files in scope" globs; cross-checks against manifest's own scope_check.
- `bin/gate-budget-check.sh` — diff_lines, files_touched, wall_clock budget enforcement.
- `bin/gate-sensitive-path-check.sh` — touched files matched against config.yaml's sensitive_paths globs; always-blocking on match.
- `bin/gate-test-count-check.sh` — manifest.tests.passed compared against kickoff's baseline test counts; fails on drops.
- `bin/gate-rerun-tests.sh` — independently re-runs the project test command in the worktree; cross-checks against manifest's reported counts.
- `bin/bisect-on-claim.sh` — verifies "pre-existing failure" deferrals by re-running the failing test on baseline_ref in a temp worktree.
- `bin/run-gates.sh` — orchestration wrapper that chains all gates, aggregates into a per-goal verdict, halts on first blocking failure.
- `schemas/gate-verdict.schema.json` — structured per-goal verdict (gates[], overall, blocking_failures[], warnings[]).
- `skills/_run-gates/SKILL.md` — internal lifecycle skill.
- `tests/phase-4/` — 10 deterministic tests covering each gate + the orchestrator. Zero claude -p.

### Modified
- `bin/worktree-init.sh` — captures baseline test counts in kickoff JSON via the cascading regex parser (jest/mocha → pytest → generic → PASS/FAIL line count). Null fallback on parse failure.
- `tests/phase-3/worktree_init_test.sh` — updated required-fields list to include `baseline` (collateral fix for the kickoff shape change).

### Notes
- P4 burned <$1 in API credits during development — full compliance with the test-cost policy.

## [0.3.0] — 2026-05-21

Implementer layer ships. An approved spec can now be turned into committed code in a dedicated worktree via the new internal lifecycle skill. Closing the loop (reviewer + orchestrator + queue) lands in P5–P6.

### Added
- `agents/implementer-strict.md` — implementer subagent with anti-eagerness calibration. Operates only in worktree; halts on ambiguity; honest test reporting; never commits to main; never pushes.
- `skills/_run-implementer/SKILL.md` — internal lifecycle skill (orchestrator-invoked). Creates worktree, dispatches implementer, captures manifest + diff envelope.
- `bin/worktree-init.sh` — creates `.worktrees/goal-<id>/` from current HEAD and writes the kickoff package.
- `bin/worktree-cleanup.sh` — removes a worktree (post-success only; halted worktrees preserved for forensics).
- `bin/migrate-v0.1-to-v0.2.sh` — one-shot idempotent migration for existing queue.yaml.
- `schemas/manifest.schema.json` — completion manifest schema.
- `schemas/diff-envelope.schema.json` — structured git-diff schema (consumed by P5 reviewer).
- `schemas/queue.schema.json` — bumped to v0.2 with eight new optional goal-item fields (started_at, completed_at, halted_at, baseline_ref, head_ref, worktree_path, manifest_path, budget_overrides).
- `tests/phase-3/` — 8 deterministic tests covering schemas, migration, worktree management, and structural verification of the implementer + lifecycle skill. **Zero `claude -p` invocations** per the new test-cost policy at `docs/superpowers/test-cost-policy.md`.

### Resolved
- P1-DEF-001 (queue goal schema extension strategy) — user chose explicit-fields-with-version-bump.

### Notes
- The implementer is a SUBAGENT, not user-invocable as a skill. The lifecycle skill `_run-implementer` is the only user-visible entry, prefixed with `_` to signal internal use.
- v0.3 does not yet check the implementer's output for scope violations or budget breaches (that's P4's deterministic gates). It does not check whether the work is correct (P5's reviewer). Goals "complete" per the manifest's `status: complete` are accepted at face value in v0.3.
- The new test-cost policy is in effect for all future phases. P3 burned <$2 in API credits during development vs ~$30+ for P2.

## [0.2.0] — 2026-05-20

Spec drafting layer ships. Implementation is still not automated — the implementer subagent lands in P3.

### Added
- `/agentic-dev:intent <text>` — drafts a structured spec for a new goal. Produces a verbatim intent file plus a spec markdown with explicit QUESTION-N blocks for every architectural decision.
- `/agentic-dev:intent --refine <spec-path>` — re-runs the drafter on a partial spec; preserves existing answers; may add new questions.
- `/agentic-dev:_check-approval <spec-path>` — runs the AI validator on approved specs. Concerns become new QUESTION-N blocks; `approved` reverts to false. Clean verdicts leave the spec untouched.
- `agents/spec-drafter.md` — drafter subagent with a fixed calibration table (anti-eagerness: forbidden from improvising; defaults to flag).
- `agents/spec-validator-ai.md` — read-only AI validator subagent. Judges measurability and scope coherence.
- `bin/validate-spec.sh` — deterministic validator. Fires via PostToolUse hook on every spec save. Mechanical checks only: frontmatter complete, schema_version matches, intent_path resolves, no unresolved QUESTION blocks when approved=true, budget values are positive integers.
- `hooks/hooks.json` — PostToolUse hook wiring for the deterministic validator.
- `schemas/spec.schema.json` — spec frontmatter schema with id pattern, date-time format, and required fields.
- `tests/phase-2/` — six tests covering schema validation, deterministic validator unit cases, fresh-intent end-to-end, hook firing, --refine preservation, and the full approval gate across three adversarial fixtures (clean, unmeasurable criteria, incoherent scope).

### Notes
- Approval flow is explicit in v0.2: the user must run `/agentic-dev:_check-approval` after the deterministic validator emits its next-step instruction. Auto-firing from the hook is deferred (one-line hooks.json change when chosen).
- P1-DEF-001 (queue goal schema extension strategy) remains deferred. P2 still does not touch queue.yaml.

## [0.1.0] — 2026-05-20

Initial scaffold. Plugin installable and bootstrappable; no agentic loop yet.

### Added
- Plugin manifest (`.claude-plugin/plugin.json`) and marketplace catalog at the canonical `.claude-plugin/marketplace.json` path (per Anthropic plugin marketplace docs).
- JSON Schemas for the three per-project state files: `state.schema.json`, `queue.schema.json`, `config.schema.json`. State schema includes a conditional `if/then` that requires `halted_*` fields when `circuit_breaker.state == "halted"`.
- `/agentic-dev:init` skill — bootstraps `.claude/agentic/` in a host project. Supports both interactive prompts and YAML-driven configuration for tests. Idempotent: re-running does not overwrite existing state.
- `/agentic-dev:status` skill — read-only state report. Shows circuit-breaker state, current goal, queue counts by status, and project configuration summary. Handles the not-initialized and partial-initialization cases.
- Phase 1 test suite (`tests/phase-1/`): schema validation tests, init end-to-end test (with idempotence check), status end-to-end test (with not-initialized case), smoke test (init→status integration), `run_all.sh` aggregator.
- Test requirements file (`tests/requirements.txt`) declaring `pyyaml` and `jsonschema[format-nongpl]` (the latter pulls in `rfc3339-validator` so `format_checker` actually enforces `date-time`).
- KEEP_TMP=1 debugging escape hatch on all shell tests — preserves the tmp project on exit for inspection.

### Not yet shipped (see roadmap in repo)
- `/agentic-dev:intent`, `:run`, `:start`, `:resume`, `:review`, `:restart` skills (P2 onward)
- spec-drafter, hardened-reviewer, reviewer-adversary, implementer-strict subagents (P2 onward)
- Deterministic gates, hook wiring, Telegram notifications (P4–P5)
- Overnight queue, circuit breaker engine, cross-session memory (P5–P7)
- Plugin distribution via published GitHub marketplace + community submission (P8)
