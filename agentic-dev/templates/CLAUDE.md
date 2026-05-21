# Agentic-dev workflow active in this project

This project uses the `agentic-dev` Claude Code plugin to structure changes through a deliberate workflow:

1. **Intent** — capture what you want via `/agentic-dev:intent "<goal>"`. The drafter produces a spec with explicit `QUESTION-N` blocks for every architectural decision.
2. **Approval** — answer the QUESTION blocks in the spec file, set `approved: true` in the frontmatter, run `/agentic-dev:_check-approval <spec-path>` to dispatch the AI validator. Iterate until clean.
3. **Run** — `/agentic-dev:start` advances approved goals one by one. The orchestrator chains implementer → gates → reviewer → routing. Auto-fix loop handles mechanical concerns (cap 2 rounds). Halts (judgment concerns, blocking issues, gate failures) trip the circuit breaker.
4. **Resume** — after a halt, `/agentic-dev:resume <decision>` decides: `resume | skip | address <text> | replan | abort`.

## For Claude Code sessions in this project

When working in this project:

- **Do not commit directly to `main`/`master`** for substantive changes. Use the agentic-dev workflow: `/agentic-dev:intent "..."` to start.
- **Do not bypass spec approval** for non-trivial changes. The spec drafter's QUESTION-N blocks exist to surface architectural decisions before code; bypassing them defeats the system's quality property.
- **For tiny edits** (typo fixes, README polish, single-line corrections): direct commits are fine, no spec needed. Use judgment.
- **State files in `.claude/agentic/`** are managed by the agentic-dev plugin. Do not edit `state.json`, `queue.yaml`, manifests, or verdicts manually. You CAN edit specs (in `.claude/agentic/specs/`), the checklist.yaml, memory.yaml, and config.yaml.
- **`.worktrees/`** is where the implementer subagent writes code per goal. Don't operate in worktrees directly — let the orchestrator manage them.

## Current state

To see what's happening at any time:

```
/agentic-dev:status
```

## Configuration

`.claude/agentic/config.yaml` has the project's settings — test command, lint command, sensitive-path globs, budget defaults, optional Telegram notification credentials.

To enable real Telegram notifications, add to `.claude/agentic/config.yaml`:
```yaml
telegram:
  bot_token: "<your-bot-token>"
  chat_id: <your-chat-id>
```

Without configured Telegram, notifications log to `.claude/agentic/notifications-log.txt`. The pipeline never blocks on notification failures.

## Cross-session memory

The plugin learns from incidents:
- `.claude/agentic/checklist.yaml` — rules from past reviewer concerns. Hardened reviewer and adversary read this at each dispatch.
- `.claude/agentic/memory.yaml` — observations from past halts. Spec drafter reads this when drafting new specs.

Both are append-only by the system; you can prune/edit them with any text editor.

## Cost notes

- Interactive Claude Code sessions (this is one) bill against your Max plan.
- The orchestrator's subagent dispatches (implementer, reviewer, drafter) are part of the interactive session — Max-billed.
- Test scripts that invoke `claude -p` (headless) bill against Anthropic Console API credits. Most tests in this project are deterministic (no claude -p). End-to-end smoke tests are gated behind `AGENTIC_E2E=1`.

## Further reading

The agentic-dev plugin's design is documented at:
- `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` — umbrella design
- `agentic-dev/CHANGELOG.md` — per-version additions

If you're seeing this file in a project that ALSO uses agentic-dev on itself (recursive), no special handling needed — agentic-dev is just a Claude plugin like any other.
