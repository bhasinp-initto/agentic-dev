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

## Skills shipped in v0.1

- `/agentic-dev:init` — bootstrap `.claude/agentic/` in the current project
- `/agentic-dev:status` — show current state

## What's coming next

See repo issues / phase plans for P2 onward: spec drafter, implementer, hardened reviewer, deterministic gates, overnight queue, escalation.
