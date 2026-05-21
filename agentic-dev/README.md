# agentic-dev

A Claude Code plugin that automates the three-role development pattern: a hardened agentic loop that implements, reviews, and escalates to the human only when quality requires it.

This is **v0.6** — the autonomous orchestrator is alive. `/agentic-dev:start` runs the approved-goals queue end-to-end (implementer → gates → reviewer → routing). Auto-fix loop handles mechanical concerns (cap 2 rounds). Halt-on-blocking + circuit breaker. Overnight progression via ScheduleWakeup. `/agentic-dev:resume` is the after-halt human entry point. Cross-session memory (P7) and marketplace polish (P8) follow.

See `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` in the source repository for the full design.

## Install

From a Claude Code session:

```
/plugin marketplace add Pankaj-Bhasin/agenticDev
/plugin install agentic-dev
```

## Bootstrap a host project

In any project where you want to use the agentic loop:

```
/agentic-dev:init
```

This creates a `.claude/agentic/` directory with the state tree, prompts for project-specific configuration (test/lint commands, Telegram chat id, budget defaults), and writes a starter `config.yaml`.

## Inspect current state

```
/agentic-dev:status
```

Reports the current queue, circuit-breaker state, and recent activity.

## Skills shipped

### v0.1
- `/agentic-dev:init` — bootstrap `.claude/agentic/` in the current project
- `/agentic-dev:status` — show current state

### v0.2
- `/agentic-dev:intent <free-form goal>` — draft a structured spec for a new goal. Produces an intent file and a spec file with explicit QUESTION-N blocks at every architectural decision.
- `/agentic-dev:intent --refine <spec-path>` — re-run the drafter on a partially-answered spec. Preserves existing answers; may add new questions if answers exposed ambiguities.
- `/agentic-dev:_check-approval <spec-path>` — run the AI validator on an approved spec. Two checks: measurability of completion criteria, scope coherence with the intent. Concerns are written back into the spec as new QUESTION-N blocks (no silent rejection); `approved` reverts to `false`.

### v0.3
- `/agentic-dev:_run-implementer <spec-path>` — internal lifecycle skill. Creates a dedicated git worktree at `.worktrees/goal-<id>/`, dispatches the `implementer-strict` subagent to write code against the approved spec following TDD discipline, captures a structured completion manifest, and generates a structured diff envelope. Not intended for routine human invocation; called by the orchestrator (P6) or by test scaffolding.

### v0.4
- `/agentic-dev:_run-gates <goal-id>` — internal lifecycle skill. Runs six deterministic verification gates on a completed goal's manifest: scope (no out-of-spec file edits), budget (diff/files within declared budget), sensitive-path (no auth/migrations/etc. touched), test-count (no tests deleted vs baseline), rerun-tests (manifest's test counts match independent re-run), bisect-on-claim (any "pre-existing failure" deferral is verified by re-running the test on the baseline ref). Writes a per-goal verdict file. Halts on first blocking failure.
- `bin/migrate-v0.1-to-v0.2.sh` (shipped in v0.3) — one-shot idempotent migration for existing queue.yaml files.

### v0.5
- `/agentic-dev:_run-reviewer <goal-id>` — internal lifecycle skill. Dispatches the `hardened-reviewer` subagent (read-only, adversarial) on a goal that passed P4's gates. Runs `reviewer-adversary` as a second pass on clean verdicts. Routes concerns by category — mechanical concerns become an auto-fix queue entry (P6 drives the loop), judgment/uncategorized concerns trigger an escalation packet + Telegram notification.
- Telegram notification helper at `bin/telegram-notify.sh` with placeholder-config mode. To enable real notifications, set `telegram.bot_token` and `telegram.chat_id` in `.claude/agentic/config.yaml`. Otherwise all notifications log to `.claude/agentic/notifications-log.txt` and the pipeline continues unaffected.

### v0.6
- `/agentic-dev:start [--until HH:MM | Nm | Nh]` — **public entry point**. Begin a queue run. The orchestrator advances goals one by one (implementer → gates → reviewer → routing). Optional `--until` argument sets a wall-clock cutoff.
- `/agentic-dev:resume <decision>` — **public after-halt entry**. Decisions: `resume | skip | address | replan | abort`. Logs to `.claude/agentic/decisions.log`.
- `/agentic-dev:_advance-goal <id>` — internal single-goal pipeline pass. Handles the auto-fix loop (cap 2 rounds) for mechanical concerns.
- `/agentic-dev:_run-orchestrator` — internal queue-loop driver. Uses ScheduleWakeup to progress overnight.
- State transition helpers: `bin/queue-set-status.sh`, `bin/circuit-breaker.sh`, `bin/cleanup-completed-goal.sh` — atomic, schema-validated updates to queue.yaml and state.json.

## What's coming next

See repo issues / phase plans for P7 onward: cross-session memory + auto-learning from incidents (P7), marketplace polish + community submission (P8).

## Development

Source repository: https://github.com/Pankaj-Bhasin/agenticDev

To run the test suite from the source repo:

```bash
bash tests/phase-1/run_all.sh
```

Design and architecture:
- `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` — full design
- `docs/superpowers/plans/2026-05-20-agentic-dev-phase-1-plugin-skeleton.md` — Phase 1 implementation plan

## Changelog

See `agentic-dev/CHANGELOG.md`.
