# Changelog

All notable changes to `agentic-dev` are documented here.
This project follows [Semantic Versioning](https://semver.org/).

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
