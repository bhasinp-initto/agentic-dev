# ruflo integration notes

Status: **active guidance** as of agentic-dev v1.1.0 (2026-05-22). Re-evaluate when either project ships a major release.

## Why this doc exists

`ruflo` (the rebrand of `claude-flow`) is a 30+ plugin ecosystem for multi-agent orchestration in Claude Code: `ruflo-core`, `ruflo-swarm`, `ruflo-autopilot`, `ruflo-rag-memory`, `ruflo-intelligence`, `ruflo-aidefence`, `ruflo-browser`, `ruflo-federation`, etc. It overlaps heavily with `agentic-dev`'s problem space but with a different design philosophy — and naively combining the two will produce silent state-drift, race conditions, or quality regressions.

This doc records which ruflo plugins are safe to use alongside `agentic-dev`, which to avoid, and the specific integration points where care is required.

## Fundamental philosophy difference

| | agentic-dev | ruflo |
|---|---|---|
| **Prime concern** | Quality (anti-eagerness, halt-on-ambiguity, deliberate escalation) | Throughput + self-learning (pattern-matching, swarm coordination, autonomy) |
| **Reviewer** | Read-only at the tool level, adversarial framing, doesn't see implementer prose | General-purpose; learns from past tasks |
| **Implementer** | `implementer-strict` — refuses to expand scope, asks for clarification rather than guessing | `ruflo-core:coder` — generalist, follows prompts |
| **Memory** | Append-only YAML files; human curates | RAG-backed vector store; auto-consolidates |
| **Loop driver** | `_run-orchestrator` with explicit cap on auto-fix rounds | `ruflo-autopilot` with neural pattern prediction |
| **Failure mode tolerated** | Halt and ask the human | Improvise and learn |

These are not the same goals. ruflo optimizes for the case "I want autonomous agents getting things done." `agentic-dev` optimizes for "I want quality work, even if it costs more halts." If you have a quality-sensitive workload, ruflo's improvise-and-learn behavior will undermine the discipline `agentic-dev` enforces.

## Install mode you should stay on

ruflo has two install modes:

- **Path A — Claude Code plugins** (`/plugin marketplace add ruvnet/ruflo` + `/plugin install ruflo-*@ruflo`). Adds slash commands and subagent definitions only. **No MCP server registered. No daemon. No files written to your project.** Stay on this.
- **Path B — Full CLI install** (`npx ruvflo init`). Writes `.claude/`, `.claude-flow/`, `CLAUDE.md`, settings, helpers; registers MCP server with 300+ tools; starts a daemon. **Conflicts with `agentic-dev`'s `.claude/agentic/` state files** (same directory). Do not run.

`agentic-dev` assumes Path A. If you ever need Path B's MCP tools, install Path B in a separate project that isn't agentic-dev-managed.

## Verdict per ruflo plugin

### ✅ Safe to use alongside agentic-dev (additive, orthogonal)

| Plugin | Use it for |
|---|---|
| `ruflo-cost-tracker` | Cost observability dashboards. We bake a smaller version into `/agentic-dev:status` (see v1.2.0+). ruflo-cost-tracker is richer if you have heavy multi-project usage. |
| `ruflo-browser` | Playwright-driven walkthrough verification (the gap in `agentic-dev`'s pipeline between reviewer-clean and queue-advance). Targeted insertion as a new step in `_advance-goal`. |
| `ruflo-aidefence` | PII / prompt-injection scanning on sensitive files (escalation packets, decisions.log, memory.yaml). Pure pre-storage filter; doesn't change pipeline behavior. |
| `ruflo-observability` | Telemetry sink for monitoring fleet metrics across many agents. Read-only; safe. |
| `ruflo-docs` | Documentation generation. Read-only; safe. |
| `ruflo-jujutsu`, `ruflo-adr`, `ruflo-knowledge-graph`, `ruflo-graph-intelligence` | Specialty tools. Read-only or scoped to their own files. Safe. |

### ⚠️ Use with care (conflicts in the same problem space)

| Plugin | Why care |
|---|---|
| `ruflo-rag-memory` | Different memory backend than our `checklist.yaml`/`memory.yaml`. If you adopt it, decide which is the source of truth and remove the other — don't run both. Could replace `bin/log-incident.sh` and the YAML files entirely if you prefer semantic search. |
| `ruflo-intelligence` | Has its own RETRIEVE→JUDGE→DISTILL→CONSOLIDATE pipeline. Could be a richer reviewer-pre-pass, but the auto-distill step pattern-matches past concerns, which conflicts with our reviewer's "find what's wrong THIS time" discipline. |

### ❌ Do not use alongside agentic-dev

| Plugin | Why not |
|---|---|
| `ruflo-autopilot` | Two competing autonomous loops on the same state files. `_run-orchestrator` (us) + `ruflo-autopilot` both fire on `/loop` or ScheduleWakeup. Race conditions on `queue.yaml`. |
| `ruflo-swarm` (parallel goal execution) | Our linear queue is intentional. Parallel goals on shared codebase = consistency hell. (`ruflo-swarm`'s worktree-per-agent is fine in principle but useless without parallelism, and `agentic-dev` already has worktree isolation.) |
| `ruflo-core:coder` / `ruflo-core:reviewer` as substitutes for our subagents | `ruflo-core:coder` has no anti-eagerness — it will silently expand scope when asked to "fix concerns." `ruflo-core:reviewer` is not read-only or adversarial. Replacing our subagents undoes the quality properties. |
| `ruflo-loop-workers` | Background worker daemon; overlaps with our orchestrator. |
| `ruflo-federation` | Cross-machine agent communication. Not relevant to our single-developer use case; adds attack surface. |
| `ruflo-daa` (decentralized autonomous agents) | Voting-based agent coordination. Conflicts with the human-in-the-loop philosophy. |

## Specific integration touch-points

If you do install ruflo plugins alongside agentic-dev, watch these:

### Hooks ordering

Both stacks use `PostToolUse` hooks on `Edit|Write`. Our `validate-spec.sh` is registered in `agentic-dev/hooks/hooks.json`. ruflo registers `hooks_route` from `ruflo-core` (Path B only).

Claude Code's hooks ordering is plugin-load-order-dependent and not deterministic across sessions. **If both fire on a spec edit:** undefined which sees the post-edit state first. Solution: stay on ruflo Path A (no MCP, no `hooks_route` registration).

### Subagent disambiguation

If both `ruflo-core:coder` and `agentic-dev:implementer-strict` are loaded, the Agent tool's `subagent_type` parameter disambiguates. Our `_run-implementer` skill explicitly says `subagent_type: implementer-strict` — that's safe. But if you write any new dispatcher prompt that just says "coder" or "implementer" without a fully-qualified name, you'll get ruflo's version, which doesn't follow our discipline.

**Rule:** every Agent dispatch in agentic-dev SKILL.md files must use `subagent_type: <our-fully-qualified-name>`.

### Memory files

`.claude/agentic/checklist.yaml` and `.claude/agentic/memory.yaml` are agentic-dev's append-only files. ruflo's `memory_store` (Path B MCP tool) writes to a SQLite/AgentDB backend, not these files. There's no conflict on disk — but if you query `memory_search` and it returns "user values quality over speed" while our checklist says nothing about that, you have an invisible knowledge gap. Subagents read OUR files at dispatch; they don't query ruflo's store.

If you want ruflo's semantic memory, replace `bin/log-incident.sh` and update subagent prompts to query `memory_search` instead of reading the yamls. Don't run both.

### Cost / billing

ruflo-cost-tracker reads from `~/.claude/sessions/` and similar. We track usage by counting subagent dispatches per goal. Both readings of the same underlying data; pick one for your dashboards.

## When ruflo would be a better fit than agentic-dev

Be honest about when to switch wholesale:

- **You're orchestrating many agents across machines.** ruflo-federation has zero-trust cross-machine comms; we have nothing.
- **You have a high-volume, repetitive workload** where pattern-matching past successes is the right optimization. ruflo's autopilot learning is built for this.
- **You're building agent-to-agent protocols rather than human-in-the-loop development.** ruflo's hive-mind consensus, swarm topologies, federation — these are for autonomous fleets, not for "human approves, agent implements, human reviews."

If your problem looks like that, archive `agentic-dev` and use ruflo directly. The two philosophies don't merge well in the middle.

## Borrowing code (not the runtime)

ruflo is MIT-licensed (https://github.com/ruvnet/claude-flow). If a specific piece of their code solves a problem we have (e.g., their PII regex set, their cost-tracker reading logic), we can copy it into agentic-dev with attribution. Borrowing code is fine; running their runtime in our pipeline is not.

Files in their repo worth knowing about:
- `v3/@claude-flow/cli/src/mcp-tools/*` — MCP tool implementations (~300 tools)
- `plugins/ruflo-aidefence/` — PII / prompt-injection regex sets
- `plugins/ruflo-cost-tracker/` — cost computation
- `plugins/ruflo-browser/` — Playwright-as-skill wrapper

## Re-evaluation triggers

Revisit this doc when:
- ruflo ships a "lite" install mode that doesn't write files into the project
- ruflo's reviewer subagent gains read-only enforcement at the tool level
- agentic-dev gains a real need for cross-machine federation
- The checklist.yaml grows past ~50 entries and grep stops finding the relevant rule
