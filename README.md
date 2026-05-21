# agentic-dev (development repo)

This is the development home for the **`agentic-dev`** Claude Code plugin — a system that automates the three-role development pattern: a human (Role 1) directs; AI subagents (spec drafter, implementer, hardened reviewer, second-pass adversary) cooperate under deterministic gates; escalation goes to the human only when quality demands it.

Designed for **overnight autonomous progress on architecturally substantive work where quality is the prime concern.**

## Install (for users)

In any Claude Code session:

```
/plugin marketplace add bhasinp-initto/agentic-dev
/plugin install agentic-dev
```

Then in any host project:

```
/agentic-dev:init
/agentic-dev:intent "Add per-tenant rate limiting to /api"
# ... answer the spec questions in place, set approved: true ...
/agentic-dev:_check-approval .claude/agentic/specs/<id>.md
/agentic-dev:start
```

See [`agentic-dev/README.md`](agentic-dev/README.md) for full installation, configuration, workflow, troubleshooting, and skills reference.

## Prerequisites

The plugin's bash scripts call `python3` with `pyyaml`, `jsonschema`, and `rfc3339_validator`. Install once:

```bash
python3 -m pip install --break-system-packages pyyaml 'jsonschema[format-nongpl]'
```

## Repo layout

```
.
├── agentic-dev/               # Plugin source (this is what /plugin install loads)
│   ├── .claude-plugin/        # Plugin manifest (name, version, homepage)
│   ├── agents/                # Subagent definitions (drafter, reviewer, implementer, etc.)
│   ├── bin/                   # Shell helpers (worktree mgmt, gates, validator, etc.)
│   ├── hooks/                 # PostToolUse hook config
│   ├── schemas/               # JSON schemas (queue, state, spec, manifest, verdict, etc.)
│   ├── skills/                # User-facing + internal skills
│   │   ├── init/              # /agentic-dev:init
│   │   ├── status/            # /agentic-dev:status
│   │   ├── intent/            # /agentic-dev:intent + --refine
│   │   ├── _check-approval/   # AI validator + auto-enqueue on clean
│   │   ├── _run-implementer/  # Implementer dispatch + manifest capture
│   │   ├── _run-gates/        # 6 deterministic gates
│   │   ├── _run-reviewer/     # Hardened reviewer + adversary
│   │   ├── _advance-goal/     # Single-goal pipeline pass (with auto-fix loop)
│   │   ├── _run-orchestrator/ # Queue loop
│   │   ├── start/             # /agentic-dev:start
│   │   └── resume/            # /agentic-dev:resume
│   ├── templates/             # CLAUDE.md template for host projects
│   ├── README.md              # Plugin's user-facing docs (install, workflow, config)
│   └── CHANGELOG.md           # Per-version additions
│
├── .claude-plugin/            # Marketplace catalog (/plugin marketplace add reads this)
│   └── marketplace.json
│
├── docs/superpowers/          # Internal design documentation
│   ├── specs/                 # Per-phase design specs (P1–P8) + umbrella design
│   ├── plans/                 # Per-phase implementation plans
│   └── test-cost-policy.md    # Test classification + cost discipline
│
├── tests/                     # 8 phase-suites + helpers
│   ├── phase-1/ … phase-8/    # Each phase has a run_all.sh + deterministic tests
│   ├── requirements.txt       # pyyaml + jsonschema[format-nongpl] + rfc3339-validator
│   └── README.md              # Per-suite test docs
│
├── three-role-pattern.md      # Original informal write-up that started the project
└── DEFERRED.md                # Tracked items not addressed in P1–P8 (post-v1 work)
```

## Design

The full design lives at `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` (umbrella spec). Per-phase design docs at `docs/superpowers/specs/2026-05-21-agentic-dev-phase-N-*.md`. Implementation plans at `docs/superpowers/plans/2026-05-2N-agentic-dev-phase-N-*.md`.

The system was built phase-by-phase using its own intended pattern (subagent-driven development with two-stage review per task), with discipline enforced by `docs/superpowers/test-cost-policy.md` after the first two phases revealed unsustainable test API spend.

## Running the test suites

All deterministic (no API cost) by default:

```bash
for p in 1 2 3 4 5 6 7 8; do bash tests/phase-${p}/run_all.sh; done
```

End-to-end tests that invoke `claude -p` (real API spend) are gated behind `AGENTIC_E2E=1`:

```bash
AGENTIC_E2E=1 bash tests/phase-2/run_e2e.sh
```

## Status

**v1.0.2** — the full three-role pattern is shippable. v1.0.0 was the initial release; v1.0.1 and v1.0.2 are post-ship fixes caught by the first real-project install (init message, intent → queue chain, QUESTION-marker validator semantics).

Future work (drafter-running-ahead parallelism, cross-model reviewer, walkthrough/Playwright, multi-developer support) is tracked in `DEFERRED.md`.

## License

MIT (see `agentic-dev/.claude-plugin/plugin.json`).
