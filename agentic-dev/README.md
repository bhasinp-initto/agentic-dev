# agentic-dev

A Claude Code plugin that automates the three-role development pattern: a hardened agentic loop that implements, reviews, and escalates to the human only when quality requires it.

This is **v0.1** — only the plugin skeleton and the `/agentic-dev:init` and `/agentic-dev:status` skills are shipped. The full agentic loop ships in subsequent phases (P2–P8).

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

## What's coming next

See repo issues / phase plans for P3 onward: implementer subagent with worktree isolation (P3), deterministic gates and hook wiring for scope/budget/sensitive-paths (P4), hardened reviewer + Telegram notifications (P5), overnight queue + circuit breaker (P6), cross-session memory (P7), marketplace polish + community submission (P8).

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
