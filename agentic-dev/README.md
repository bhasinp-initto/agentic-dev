# agentic-dev

A Claude Code plugin that automates the three-role development pattern: a hardened agentic loop that implements, reviews, and escalates to the human only when quality requires it.

This is **v0.5** — adds the AI judgment layer (hardened reviewer + second-pass adversary) with structured verdicts, escalation packets, and Telegram notifications (placeholder config — fill in `.claude/agentic/config.yaml`'s `telegram` field with `bot_token` + `chat_id` to enable real notifications; otherwise notifications log to file). The autonomous orchestrator (P6) wires the auto-fix loop and overnight queue next.

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

## What's coming next

See repo issues / phase plans for P6 onward: overnight queue + circuit breaker + drafter-running-ahead + auto-fix loop wiring (P6), cross-session memory + auto-learning (P7), marketplace polish + community submission (P8).

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
