# Changelog

All notable changes to `agentic-dev` are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.3] — 2026-05-21

Two more bugs caught by the same real-project install, plus a new `accept` resume decision for "I reviewed the work, I'm happy with it as-is."

### Fixed
- **`log-incident.sh` failed schema validation on every fresh project.** The init skill (v1.0.0–v1.0.2) wrote `checklist.yaml` and `memory.yaml` without a `schema_version` field, so the first call to `log-incident.sh` always failed validation. The reviewer skill swallowed the failure per P7-L4 ("auto-append must never block the pipeline") but the cross-session learning feature was effectively dead.
  - **Fix (going forward):** `init/SKILL.md` now writes `schema_version: "0.1"` into both files.
  - **Fix (existing projects):** `log-incident.sh` self-heals — if the loaded yaml is missing `schema_version`, backfills `"0.1"` in-place before validation. Verified on both checklist + memory side.

### Added
- **`/agentic-dev:resume accept`** — new decision for "I looked at the halted goal's worktree, I'm satisfied with the work despite the reviewer's concerns, mark it complete." Marks `status: completed` + populates `completed_at`/`head_ref`/`manifest_path` from the manifest + resets circuit breaker to idle. **Does NOT auto-clean the worktree** — the human merges from it and runs `bin/worktree-cleanup.sh <goal-id>` explicitly when done.
  - The reviewer's verdict + escalation packet remain on disk for forensic reference.
  - Use this when you want the operator-override path: reviewer caught real concerns, you considered them, you accept the trade-off.

### Notes
- All six `/agentic-dev:resume` decisions now: `resume | skip | address <text> | replan | accept | abort`.
- Resume structural test updated to assert all six.
- Phase 7 log-incident test still passes (existing happy-path fixtures already had `schema_version`); the new self-heal path is verified by inline regression covered in the 1.0.3 commit body.

## [1.0.2] — 2026-05-21

Caught by first real-project install on a real spec.

### Fixed
- **`validate-spec.sh` rejected approved specs even when all questions were answered.** The validator grepped for any `<!-- QUESTION-N -->` marker and rejected on marker presence alone, but the drafter emits QUESTION markers as **persistent audit-trail annotations** — the user fills in the `**Your answer:**` line beneath each marker, the marker stays. The validator was conflating "marker present" with "unresolved." Now: validator counts `[REPLACE THIS LINE` placeholders (the actual "unanswered" sentinel) instead of markers. An approved spec with markers + filled answers passes; an approved spec with any unfilled placeholder is rejected with an error that names the QUESTION-N each unfilled placeholder belongs to.
- "questions remaining" count in draft-state output now reports unfilled placeholders out of total questions (e.g., `state: draft (3 of 13 questions unanswered)`) instead of just total marker count.

### Test changes
- Added `APPROVED_WITH_ANSWERED_QUESTION` fixture (asserts approval passes when markers are preserved + answers filled).
- Added assertion that the `approved-with-question` failure message mentions the placeholder hint.

### Notes
- Existing v1.0.x installs that worked around this by stripping markers should NOT need to undo that workaround — both stripped-markers and preserved-markers states are now valid as long as answers are filled. Preserved markers are recommended for traceability.

## [1.0.1] — 2026-05-21

Post-ship bug fixes caught by first real-project install.

### Fixed
- **The intent → approval → queue → start chain was broken.** `_check-approval`'s clean verdict didn't enqueue the goal, and `/agentic-dev:start` only reads `queue.yaml`. Users would approve a spec, run `/agentic-dev:start`, and see "Queue empty". Now: clean verdict calls a new `bin/enqueue-goal.sh` helper that appends the goal to `queue.yaml` with `status: approved` (idempotent; promotes drafted/intent_only to approved; refuses to clobber running/completed/halted). 10 new deterministic assertions in `tests/phase-2/enqueue_goal_test.sh`.
- **`/agentic-dev:start` now warns about orphan approved specs.** New Step 1a scans `.claude/agentic/specs/*.md` for `approved: true` entries not present in `queue.yaml`, prints a NOTICE suggesting `_check-approval` to validate-and-auto-enqueue. Defensive: never auto-enqueues from `/start` (that would skip the AI validator).
- **`/agentic-dev:init`'s closing message referenced a non-existent `/agentic-dev:configure-telegram` skill** (forward reference to a feature that never shipped — P5 went the placeholder-config route instead). Updated init's output to explain editing `.claude/agentic/config.yaml` directly.

### Added
- `agentic-dev/bin/enqueue-goal.sh` — manually-invocable enqueue helper for goals approved before this version shipped, or for advanced workflows that bypass `_check-approval`. Idempotent; schema-validates before writing.

### Notes
- Existing v1.0.0 installs hit the queue-gap bug on every approved spec. Upgrade to v1.0.1 (`/plugin update agentic-dev`) and re-run `/agentic-dev:_check-approval <spec>` — the clean verdict will auto-enqueue.

## [1.0.0] — 2026-05-21

**v1.0** — the full three-role agentic development pattern is complete and shippable.

### The complete arc (P1 through P8)

`agentic-dev` is a Claude Code plugin that automates the three-role development pattern: a human (Role 1) provides direction, two distinct AI subagent roles (drafter, hardened-reviewer) cooperate with an implementer subagent (Role 3) under deterministic gates, escalating to the human only when quality demands it. Designed for overnight autonomous progress on architecturally substantive work where quality is the prime concern.

### Phase summary

- **v0.1 (P1)** — Plugin scaffold + `/agentic-dev:init` + `/agentic-dev:status`
- **v0.2 (P2)** — Spec drafter + `/agentic-dev:intent` + AI validator (`_check-approval`)
- **v0.3 (P3)** — Implementer subagent (`implementer-strict`) + worktree-per-goal isolation + `_run-implementer`
- **v0.4 (P4)** — Six deterministic gates (scope, budget, sensitive-path, test-count, rerun-tests, bisect-on-claim) + `_run-gates`
- **v0.5 (P5)** — Hardened reviewer + reviewer-adversary + escalation packets + Telegram (placeholder config) + `_run-reviewer`
- **v0.6 (P6)** — Autonomous orchestrator (`_run-orchestrator`, `_advance-goal`) + public `/agentic-dev:start` and `/agentic-dev:resume` + auto-fix loop (cap 2 rounds) + ScheduleWakeup-driven overnight progression
- **v0.7 (P7)** — Cross-session memory: checklist + memory YAMLs, auto-append on incidents, subagent prompts read both at dispatch
- **v1.0 (P8)** — Marketplace polish + CLAUDE.md template + final regression

### Added in v1.0 (P8)
- `agentic-dev/templates/CLAUDE.md` — starter file for host projects, surfaces workflow context to future Claude Code sessions.
- `tests/phase-8/marketplace_smoke_test.sh` — structural validation of the marketplace catalog + optional plugin-load smoke (gated behind AGENTIC_E2E=1).
- `tests/phase-8/run_all.sh` — phase 8 aggregator.

### Public skills (cumulative — all available in v1.0)

| Skill | Purpose |
|---|---|
| `/agentic-dev:init` | Bootstrap `.claude/agentic/` in a host project. |
| `/agentic-dev:status` | Show current queue, circuit-breaker state, config summary. |
| `/agentic-dev:intent <text>` | Draft a structured spec for a new goal. |
| `/agentic-dev:intent --refine <spec-path>` | Re-run the drafter on a partial spec. |
| `/agentic-dev:_check-approval <spec-path>` | Run AI validator on an approved spec. |
| `/agentic-dev:start [--until ...]` | Begin the autonomous queue run. |
| `/agentic-dev:resume <decision>` | After halt: resume / skip / address / replan / abort. |

Internal lifecycle skills (`_run-implementer`, `_run-gates`, `_run-reviewer`, `_run-orchestrator`, `_advance-goal`) are invoked by the orchestrator; users can invoke them directly for testing or debugging.

### Cost / quality discipline established
- `docs/superpowers/test-cost-policy.md` codifies three test classes (deterministic, agent-dispatched, claude -p) with default-deterministic discipline.
- Total project dev cost: ~$110 across all 8 phases (~$100 spent in P1+P2 before the cost policy; ~$10 across P3-P8 combined under the policy).
- Subagent-driven-development pattern with two-stage review (spec + code quality) per task held throughout — caught numerous real bugs.

### Notes
- Repository: `bhasinp-initto/agentic-dev` (private). Install via `/plugin marketplace add bhasinp-initto/agentic-dev`.
- DEFERRED.md tracks items not addressed in P1-P8 (drafter-running-ahead, cross-model reviewer, walkthrough integration, multi-developer support). Post-v1 work.

## [0.7.0] — 2026-05-21

Cross-session memory + auto-learning. The system now adapts to past incidents in this project without manual curation.

### Added
- `schemas/checklist.schema.json` — `.claude/agentic/checklist.yaml` shape (reviewer-pattern rules with date, incident_ref, rule, caught_by).
- `schemas/memory.schema.json` — `.claude/agentic/memory.yaml` shape (observations with date, observation, consequence).
- `bin/log-incident.sh` — append-only helper. Validates type (checklist|memory), required keys per type, auto-populates date, schema-validates before write, atomic.
- Subagent prompt modifications: `hardened-reviewer`, `reviewer-adversary` read checklist.yaml at dispatch; `spec-drafter` reads memory.yaml. All gracefully handle empty/missing files.
- Skill modifications: `_run-reviewer` auto-appends checklist entries for judgment/uncategorized/blocking concerns before escalation; `_advance-goal` auto-appends memory entry on the halt path.
- `tests/phase-7/` — 3 deterministic test files (schemas + log-incident). Zero claude -p.

### Notes
- Auto-append failures (schema validation, file lock, etc.) log to validation-log.txt and continue — never block the pipeline (P7-L4).
- Humans can prune/edit checklist.yaml and memory.yaml at any time using a text editor. The system reads whatever's there.
- P7 dev cost: <$1 API credits.

## [0.6.0] — 2026-05-21

The autonomous orchestrator ships. After approving specs, run `/agentic-dev:start` and the system processes the queue end-to-end: implementer writes code in worktree → gates verify → reviewer checks → auto-fix loop for mechanical concerns → escalation on judgment concerns → next goal. Halts are circuit-breaker-locked until human resumes.

### Added
- `bin/queue-set-status.sh` — atomic goal-status transitions with schema validation. Accepts `key=value` field updates (started_at, completed_at, baseline_ref, head_ref, etc.).
- `bin/circuit-breaker.sh` — atomic state.json transitions. `halted` state requires halted_reason + halted_goal_id; auto-populates halted_at.
- `bin/cleanup-completed-goal.sh` — post-success worktree removal (delegates to bin/worktree-cleanup.sh). Refuses if goal status isn't `completed`.
- `skills/_advance-goal/SKILL.md` — internal single-goal pipeline. Wires implementer + gates + reviewer + routing decisions. Handles auto-fix loop with hard cap of 2 rounds; on cap-exhaustion, escalates as `auto_fix_exhausted`. Updates queue + circuit-breaker on clean/halt.
- `skills/_run-orchestrator/SKILL.md` — internal queue loop. Picks first approved goal; runs `_advance-goal`; on success, schedules next wake-up via `ScheduleWakeup` (30s delay). On halt, exits with circuit breaker locked.
- `skills/start/SKILL.md` — **public entry**. Optional `--until <HH:MM | Nm | Nh>` cutoff.
- `skills/resume/SKILL.md` — **public after-halt entry**. Five decisions (resume | skip | address | replan | abort) with per-decision state transitions, all logged to `decisions.log`.
- `tests/phase-6/` — 7 deterministic tests (3 state-helper, 4 skill-structure). Zero claude -p.

### Notes
- The auto-fix loop is now end-to-end functional. Mechanical reviewer concerns trigger a re-dispatched implementer with the concerns as kickoff input; up to 2 rounds. If the third reviewer pass still flags mechanical concerns, the loop escalates rather than spinning forever.
- ScheduleWakeup-driven overnight runs: the orchestrator self-resumes between goals, processing the queue while you sleep. A blocking event halts; you wake up to escalation packets + a Telegram digest (if configured) plus a queue snapshot.
- The orchestrator is "drafter-running-ahead" capable (umbrella §10) but v0.6 ships linear processing only. P7+ may add parallelism.
- P6 dev cost: <$1 API credits (all plumbing; no LLM-driven tests).

## [0.5.0] — 2026-05-21

AI judgment layer ships. After gates pass, the hardened reviewer reads spec + manifest + diff envelope and returns a structured verdict; clean verdicts get a second-pass adversary check; concerns routed by category. Escalation packets and Telegram notifications (placeholder-friendly) complete the human-in-the-loop signal path.

### Added
- `agents/hardened-reviewer.md` — read-only AI reviewer subagent with adversarial framing. Two judgment dimensions: spec compliance + risk detection. Concerns categorized as mechanical | judgment | uncategorized (uncategorized defaults to judgment per umbrella §8).
- `agents/reviewer-adversary.md` — second-pass adversary subagent on otherwise-clean reviews.
- `schemas/reviewer-verdict.schema.json` — structured AI verdict (verdict enum, concerns[], checks_run[]).
- `schemas/escalation-packet.schema.json` — structured escalation file (trigger enum, concerns, paths to manifest/verdict/diff/spec, suggested_next_actions).
- `bin/telegram-notify.sh` — severity-tiered Telegram helper. Placeholder mode (no config) logs to `notifications-log.txt`; configured mode POSTs to Telegram Bot API with graceful failure. Always exits 0 (notifications are advisory).
- `bin/generate-escalation.sh` — escalation packet generator. Builds packet from manifest + reviewer-verdict + gate-verdict (any available); validates against schema; writes timestamped markdown with YAML frontmatter to `.claude/agentic/escalations/`.
- `skills/_run-reviewer/SKILL.md` — internal lifecycle skill. Short-circuits to escalation on gate_failure. Otherwise dispatches hardened-reviewer; runs adversary on clean; routes concerns; writes auto_fix_candidates to `.claude/agentic/auto-fix-queue/` (mechanical) or generates escalation + notification (judgment/blocking).
- `tests/phase-5/` — 7 deterministic test files covering schemas, subagent structures, helper scripts, and skill structure. Zero claude -p.

### Configuration

To enable real Telegram notifications, edit `.claude/agentic/config.yaml`:

```yaml
telegram:
  bot_token: "<your-bot-token>"
  chat_id: <your-chat-id>
```

Without this, all notifications log to `.claude/agentic/notifications-log.txt`. The pipeline never blocks on notification failures.

### Notes
- v0.5 doesn't yet drive the auto-fix loop end-to-end — `_run-reviewer` captures mechanical concerns into an auto-fix-queue file; P6's orchestrator reads this and re-dispatches the implementer.
- P5 dev cost: <$1 in API credits (deterministic-first per cost policy; one optional controller-driven agent-dispatch smoke at T6).

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
