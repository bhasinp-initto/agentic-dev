# agentic-dev

A Claude Code plugin that automates the **three-role development pattern**: a human (Role 1) directs, two AI subagent roles (spec drafter + hardened reviewer) cooperate with an implementer subagent (Role 3) under deterministic gates, escalating to the human only when quality demands it. Designed for **overnight autonomous progress on architecturally substantive work where quality is the prime concern**.

This is **v1.0** — the complete pipeline ships: intent capture → spec drafting → approval (with AI validator) → implementation in dedicated git worktrees with TDD discipline → deterministic verification gates → AI reviewer with adversarial second pass → human escalation only when needed.

See `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` (umbrella design doc) for the full design rationale.

## Quickstart

```bash
# 1. Install (in any Claude Code session)
/plugin marketplace add Pankaj-Bhasin/agenticDev
/plugin install agentic-dev

# 2. Bootstrap a host project
cd ~/my-project
/agentic-dev:init      # creates .claude/agentic/ with config, queue, state

# 3. Draft a goal
/agentic-dev:intent "Add per-tenant rate limiting to the API"
# → spec drafter creates a markdown spec with QUESTION-N blocks for every
#   architectural decision. Open the spec, answer the questions in place.

# 4. Approve the spec
# Edit the spec frontmatter: approved: true
# Save. The validator runs automatically.
/agentic-dev:_check-approval .claude/agentic/specs/<id>.md
# AI validator either confirms clean or adds new QUESTION-N blocks for concerns.

# 5. Run the queue
/agentic-dev:start --until 07:00   # overnight progress; halt at 7am or on issue
```

## Workflow overview

```
   Human                       Plugin                       Claude Code
     │                           │                              │
     │ /agentic-dev:intent ─────►│  spec-drafter (subagent)     │
     │                           │  ─ QUESTION-N blocks in spec │
     │ answer questions, set    │                              │
     │ approved: true ──────────►│  _check-approval             │
     │                           │  ─ AI validator              │
     │                           │  ─ writes new QUESTIONs or   │
     │                           │    confirms clean            │
     │                           │                              │
     │ /agentic-dev:start ──────►│  _run-orchestrator (LOOP)    │
     │                           │   ├─ _advance-goal           │
     │                           │   │  ├─ _run-implementer     │
     │                           │   │  │  ├─ worktree-init     │
     │                           │   │  │  └─ implementer-strict│
     │                           │   │  ├─ _run-gates           │
     │                           │   │  │  └─ 6 gate scripts    │
     │                           │   │  ├─ _run-reviewer        │
     │                           │   │  │  ├─ hardened-reviewer │
     │                           │   │  │  └─ reviewer-adversary│
     │                           │   │  └─ route concerns       │
     │                           │   │     ├─ mechanical: loop  │
     │                           │   │     │  (cap 2 rounds)    │
     │                           │   │     ├─ judgment: escalate│
     │                           │   │     └─ clean: cleanup +  │
     │                           │   │        advance to next   │
     │ Telegram push ◄───────────┤  ─ escalation packet         │
     │ (or notifications-log)    │   ─ circuit-breaker halted   │
     │                           │                              │
     │ /agentic-dev:resume ─────►│   ─ resume|skip|address|     │
     │   <decision>              │     replan|abort             │
```

## Skills shipped

| Skill | Purpose |
|---|---|
| **`/agentic-dev:init`** | Bootstrap `.claude/agentic/` in the current project. |
| **`/agentic-dev:status`** | Show current queue, circuit-breaker state, configuration summary. |
| **`/agentic-dev:intent <text>`** | Draft a structured spec for a new goal. |
| **`/agentic-dev:intent --refine <spec-path>`** | Re-run the drafter on a partially-answered spec; preserves existing answers. |
| **`/agentic-dev:_check-approval <spec-path>`** | Run the AI validator on an approved spec. |
| **`/agentic-dev:start [--until HH:MM\|Nm\|Nh]`** | Begin the autonomous queue run. |
| **`/agentic-dev:resume <decision> [args]`** | After a halt, decide: `resume | skip | address <text> | replan | abort`. |

Internal lifecycle skills (`_run-implementer`, `_run-gates`, `_run-reviewer`, `_run-orchestrator`, `_advance-goal`) are invoked by the orchestrator. You can invoke them directly for testing or debugging.

## Configuration

`.claude/agentic/config.yaml` (created by `/agentic-dev:init`):

```yaml
schema_version: "0.1"
project:
  name: my-project
  primary_language: python
commands:
  test: "pytest -q"
  lint: "ruff check ."
  typecheck: "mypy ."
  build: null
budgets:
  wall_clock_minutes_per_goal: 90
  diff_lines_per_goal: 800
  files_touched_per_goal: 25
sensitive_paths:
  - "auth/**"
  - "migrations/**"
  - "schema/**"
  - "secrets/**"
  - "payments/**"
  - "infra/**"
telegram: null          # or { bot_token: "...", chat_id: <id> }
push_policy: hold       # 'hold' = human pushes; 'auto' = orchestrator pushes
```

### Telegram notifications

Set `telegram` to enable real notifications:
```yaml
telegram:
  bot_token: "<bot-token-from-BotFather>"
  chat_id: <your-chat-id>
```

Without configured Telegram, notifications log to `.claude/agentic/notifications-log.txt`. The pipeline never blocks on notification failures.

## State files

| File | Purpose |
|---|---|
| `.claude/agentic/state.json` | Orchestrator state + circuit breaker (idle / running / halted / completed). |
| `.claude/agentic/queue.yaml` | Goal queue (per-goal status, paths to spec/manifest/diff/worktree). |
| `.claude/agentic/config.yaml` | Per-project config. |
| `.claude/agentic/intents/<id>.md` | Human-written intent (input to drafter). |
| `.claude/agentic/specs/<id>.md` | Structured spec (drafter output; human approves). |
| `.claude/agentic/manifests/<id>.json` | Implementer completion manifest. |
| `.claude/agentic/diffs/<id>.json` | Structured git-diff envelope. |
| `.claude/agentic/verdicts/<id>.json` | Deterministic-gate verdict. |
| `.claude/agentic/reviewer-verdicts/<id>.json` | AI reviewer verdict. |
| `.claude/agentic/escalations/<timestamp>-<id>.md` | Human-readable escalation packets. |
| `.claude/agentic/checklist.yaml` | Cross-session reviewer-pattern rules (append-only). |
| `.claude/agentic/memory.yaml` | Cross-session orchestrator observations (append-only). |
| `.claude/agentic/decisions.log` | Human-reset decisions audit trail. |
| `.worktrees/goal-<id>/` | Per-goal git worktree (created by implementer; cleaned on success). |

## CLAUDE.md template

For host projects, `agentic-dev/templates/CLAUDE.md` is a starter you can copy to your project's `.claude/CLAUDE.md` (or merge into existing). It surfaces the agentic-dev workflow to future Claude Code sessions, including reminders not to bypass the workflow for substantive changes.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `agentic-dev: not initialized` | No `.claude/agentic/` in project | Run `/agentic-dev:init` |
| `spec validation failed: unresolved QUESTION blocks` | Setting `approved: true` while QUESTION-N markers remain | Answer them or set `approved: false` |
| `Credit balance is too low` from `claude -p` tests | API account out of credits | Top up at https://console.anthropic.com/settings/billing, or run only deterministic tests (default in `run_all.sh`) |
| Orchestrator halted unexpectedly | Reviewer or gate flagged a blocking issue | Read the escalation packet in `.claude/agentic/escalations/`, then `/agentic-dev:resume <decision>` |
| Worktree not cleaned after success | Manual fix: `bin/worktree-cleanup.sh <goal-id>` | (Usually the orchestrator cleans automatically) |

## Development

Source repo: this directory (or wherever you cloned `agentic-dev` from).

```bash
# Run the full deterministic test suite (no API cost)
bash tests/phase-1/run_all.sh
bash tests/phase-2/run_all.sh
bash tests/phase-3/run_all.sh
bash tests/phase-4/run_all.sh
bash tests/phase-5/run_all.sh
bash tests/phase-6/run_all.sh
bash tests/phase-7/run_all.sh
bash tests/phase-8/run_all.sh

# Run end-to-end tests that invoke `claude -p` (uses API credits)
AGENTIC_E2E=1 bash tests/phase-2/run_e2e.sh
```

Design docs:
- `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` — umbrella design
- `docs/superpowers/specs/2026-05-21-agentic-dev-phase-N-*-design.md` — per-phase designs
- `docs/superpowers/plans/2026-05-2N-agentic-dev-phase-N-*.md` — per-phase implementation plans
- `docs/superpowers/test-cost-policy.md` — test cost discipline

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
