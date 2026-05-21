# Phase 8 — Marketplace Polish + v1.0 Design

**Date:** 2026-05-21 · **Phase:** P8/8 (FINAL) · **Umbrella spec:** §22 (v1 scope item 10), §23 (distribution lifecycle)

## 1. Intent

P8 closes out v1.0 of `agentic-dev`. The plugin is functionally complete after P3-P7. P8 polishes the distribution surface: marketplace catalog validation, README for first-time users, an optional CLAUDE.md template for host projects (so new sessions land with appropriate context), a final integrated smoke test, and bumps the plugin version to **1.0.0**.

## 2. Goals

- **G1** — Marketplace catalog (`.claude-plugin/marketplace.json`) validated against Anthropic's documented schema; install command tested end-to-end via `claude --plugin-dir ./agentic-dev` smoke.
- **G2** — Plugin README rewritten for v1.0 — clear "what is this," "how do I install," "how do I use" structure. Includes a quickstart, a usage flowchart, a configuration reference, and a troubleshooting section.
- **G3** — CLAUDE.md template for host projects at `agentic-dev/templates/CLAUDE.md` — a starter file a new project can copy to surface the agentic-dev workflow context to future Claude Code sessions.
- **G4** — Final smoke test that exercises the plugin loading + skill discovery (no claude -p required — just static checks on the plugin manifest + plugin-dir loading).
- **G5** — Version bump to **1.0.0** with CHANGELOG entry summarizing the full P1-P8 arc.
- **G6** — Final DEFERRED.md review: close any entries that P1-P7 actually addressed; preserve genuinely future-deferred items.

## 3. Non-goals

- Public marketplace submission to Anthropic's community catalog (out of scope; user can do this manually after v1.0 ships)
- CI integration (host project responsibility)
- Multi-developer collaboration features (umbrella spec calls these out as out-of-scope for v1)

## 4. Scope of v1.0 build (5 tasks)

### T1: Marketplace catalog polish + smoke test

Verify `.claude-plugin/marketplace.json` is fully compliant with [Anthropic's marketplace docs](https://code.claude.com/docs/en/plugin-marketplaces). Add a smoke test (`tests/phase-8/marketplace_smoke_test.sh`) that:
- Confirms `.claude-plugin/marketplace.json` exists at repo root
- Validates JSON syntax
- Verifies required fields: name, owner, plugins
- Confirms the plugin source path resolves
- Loads the plugin via `claude --plugin-dir ./agentic-dev --print` and confirms no manifest errors (this is the only optional API call; can be gated by env)

### T2: README v1.0 rewrite

`agentic-dev/README.md` should have:
- Brief project description (1-2 paragraphs)
- Quickstart (5 commands)
- Skills reference (all skills + flags)
- Configuration reference (config.yaml fields)
- Workflow overview (intent → spec → approval → start → orchestrator → completion/halt → resume)
- Troubleshooting (common issues + fixes)
- Architecture pointer to umbrella spec
- Cost note (Max billing for interactive, API for headless `claude -p` tests)

### T3: CLAUDE.md template

`agentic-dev/templates/CLAUDE.md` — a starter file a new project can copy to `.claude/CLAUDE.md` (or merge into existing). Contains:
- Brief note that the project uses `agentic-dev`
- Workflow summary (intent → approval → start)
- Reminder for Claude sessions to NOT bypass the workflow (e.g., not to commit on main without going through implementer)
- Pointer to `/agentic-dev:status` for current state

### T4: Final DEFERRED.md review

Walk through every entry in DEFERRED.md. Close any that P1-P7 addressed. Re-target any still-deferred items to v1.x or post-v1 with explicit rationale.

### T5: v1.0.0 closer

- plugin.json: version → "1.0.0"
- CHANGELOG: comprehensive v1.0.0 entry covering the P1-P8 arc + DEFERRED carryforward summary
- Final P1-P8 regression run (all deterministic suites)
- Commit + (optional, user-controlled) git tag v1.0.0

## 5. Testing strategy

Deterministic. Zero `claude -p` except optionally in T1's marketplace smoke (gated behind AGENTIC_E2E=1 per cost policy).

## 6. Out of scope / Carries to post-v1

- Drafter-running-ahead parallelism
- Cross-model reviewer (B/D paths)
- Walkthrough/Playwright integration
- Multi-developer support
- Public Anthropic community marketplace submission
- CI/CD workflows
