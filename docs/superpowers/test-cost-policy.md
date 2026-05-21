# Test-cost policy

How we keep API spend low without sacrificing quality.

## The three test classes

Every test in `tests/phase-N/` must be classed as one of:

### 1. Deterministic (preferred — zero API cost)

Pure Python or bash. No Claude invocations. Tests filesystem state, parses files, validates schemas, runs scripts with simulated inputs.

**Examples in this repo:**
- `tests/phase-1/schema_test.py` — JSON-Schema validation
- `tests/phase-2/spec_schema_test.py` — spec frontmatter schema validation
- `tests/phase-2/validate_spec_test.py` — feeds validate-spec.sh hand-authored fixtures
- `tests/phase-2/hook_test.sh` — pipes simulated PostToolUse JSON into validate-spec.sh
- Structural tests of SKILL.md / agents/*.md files: parse the file, assert required sections, frontmatter, key instructions are present

Run these on every `run_all.sh`. They're free and fast.

### 2. Agent-dispatched (Max-billed — no API cost)

A controller (this Claude Code session) dispatches a subagent via the `Agent` tool to do the LLM work, then verifies state. Bills against your Max plan's interactive budget, not Anthropic Console credits.

Used for: occasional smoke verification of LLM-driven behavior during development. The controller runs the test pattern manually.

**Cannot be used from shell test scripts** — the `Agent` tool is only available from inside a Claude Code session.

### 3. `claude -p` headless (real API cost — last resort)

Shell scripts that invoke `claude -p` to drive Claude Code through skills/subagents. This burns Anthropic Console prepaid credits at full API rates.

**Examples that exist today:**
- `tests/phase-2/intent_fresh_test.sh`
- `tests/phase-2/intent_refine_test.sh`
- `tests/phase-2/approval_gate_test.sh`

All `claude -p` tests must:
1. Skip by default in `run_all.sh` (gate behind `AGENTIC_E2E=1` env var).
2. Be invokable via a separate `run_e2e.sh` (or per-test direct invocation with the env var set).
3. Have a corresponding deterministic test that covers the structural assertions (the LLM-needing assertions are the only ones that survive in the E2E test).

## Rules going forward

**For every new test in a future phase:**

1. **Default to class 1 (deterministic).** Most assertions about plugin behavior are about file structure, schema validity, frontmatter, and validator output — none of these need Claude.
2. **If you need to verify an LLM follows instructions in a skill, write a structural test** (does the SKILL.md have the right content?) — not an E2E test.
3. **Only use `claude -p`** when the test is genuinely verifying end-to-end LLM behavior AND a structural test isn't sufficient. Even then: gate behind `AGENTIC_E2E=1`.
4. **Implementation plans must class every test.** No `claude -p` test ships unjustified.

## Development discipline

Beyond test design, run discipline matters:

- **Run tests once per implementation change, not per fix-loop iteration.** Code-review fixes that only touch docs/CHANGELOG/comments do not need a test re-run.
- **Use `KEEP_TMP=1`** to inspect a failed test's state before re-running.
- **Trust spec compliance reviews** — if the spec reviewer confirms the implementation matches the plan, don't re-run E2E tests just to "double-check."
- **For multi-task phases**, run the full phase suite ONCE at the end (phase closer), not after every task.

## Reviewer model selection

Subagent dispatches bill against the Max plan (no API $) but still consume your Max usage budget:

- **Implementers and AI judgment subagents** (spec-drafter, spec-validator-ai, reviewer-adversary): use `sonnet`. Reasoning quality matters.
- **Spec compliance reviewers and code quality reviewers**: use `haiku` for tasks under ~5 files. Sonnet for tasks touching 10+ files or with cross-cutting design concerns.
- **Final holistic reviewers** (per-phase closer): `sonnet`. Worth the higher capability for catching cumulative drift.

## When to suspect cost regression

If a phase's API spend exceeds **~$5**, something's wrong. Stop and investigate:

- Are tests running in fix-loops that don't need them?
- Are `claude -p` tests firing when they should be gated?
- Are subagent dispatches inadvertently calling `claude -p` internally (verify the subagent's prompt doesn't include shell commands that invoke it)?

A full phase under the new policy should land in the **$2–5 API spend** range, mostly from one E2E smoke run at the end.
