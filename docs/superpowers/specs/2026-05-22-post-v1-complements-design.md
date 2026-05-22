# Post-v1 Complements Design — Borrowing from ruflo's Strengths

**Status:** Draft (autonomous decision-mode)
**Date:** 2026-05-22
**Phase:** Post-v1 (informally "Phase 9" if we ever ship it as one block; more likely shipped as separate minor versions v1.2.0 → v1.5.0)
**Related:** `docs/superpowers/ruflo-integration-notes.md` (boundary rules), umbrella spec §6.5 step 4 (walkthrough is the long-standing gap)

---

## 1. Intent

Four ruflo capabilities are genuinely additive to agentic-dev's pipeline. This doc scopes each as a standalone implementation that we ship in agentic-dev directly (not as ruflo dependencies) — borrowing ruflo's open-source code where useful but keeping our runtime untouched. Each can be shipped independently as a minor version.

## 2. The four complements

| Complement | Maps to ruflo plugin | Agentic-dev value | Standalone size |
|---|---|---|---|
| Usage / cost observability | `ruflo-cost-tracker` | "Where did my API spend go this week?" | **Small** — a new skill + a usage rollup file |
| Walkthrough verification (Playwright) | `ruflo-browser` | Fills the umbrella §6.5 step 4 gap. Reviewer-clean + walkthrough-clean = much stronger completion signal for UI work. | **Large** — new gate, new subagent, new schema, new spec section |
| PII / prompt-injection scanning | `ruflo-aidefence` | Prevents secrets from leaking into escalation packets / decisions.log / memory.yaml | **Medium** — a deterministic check script + hook wiring |
| Semantic checklist search | `ruflo-rag-memory` | When `checklist.yaml` grows past ~50 entries, grep stops surfacing the right rule at reviewer dispatch | **Medium** — adds embeddings to `log-incident.sh`; reviewer prompt updated to do similarity query |

## 3. Order of recommended implementation

1. **v1.2.0 — Usage observability** (~half a day). Smallest. Pure additive value. Doesn't change pipeline behavior.
2. **v1.3.0 — PII / prompt-injection scanning** (~1-2 days). Pre-storage filter. Doesn't change pipeline behavior. Borrows ruflo's regex set.
3. **v1.4.0 — Walkthrough verification** (~3-5 days, new phase). Real pipeline change. Requires a new spec section, schema, subagent, gate. The big-value win for UI projects.
4. **v1.5.0 — Semantic checklist** (deferable). Only worth doing when `checklist.yaml` grows large enough that grep becomes lossy. Currently 0 entries in tradexpert — defer until empirical signal.

---

## 4. Complement A — Usage / cost observability (v1.2.0)

### Goal

A `/agentic-dev:cost` skill (or enriched `/agentic-dev:status`) that reports:
- Per-goal: started_at, completed_at or halted_at, duration, # of subagent dispatches (countable from manifests + reviewer-verdicts + verdicts), diff stats
- Queue rollup: N completed, N halted, total subagent dispatches, est. token usage range

### Honest scope

We **cannot** read the Anthropic Console billing API from inside a Claude Code plugin. The plugin can only count artifacts on disk and present an estimate. The user cross-references with https://console.anthropic.com/settings/billing for actual numbers.

### Design

New skill: `agentic-dev/skills/cost/SKILL.md` (public, no underscore prefix).

```
Usage: /agentic-dev:cost [--since YYYY-MM-DD] [--goal <goal-id>]
```

Behavior:
1. Walk `.claude/agentic/manifests/*.json`, `.claude/agentic/reviewer-verdicts/*.json`, `.claude/agentic/verdicts/*.json`.
2. For each goal:
   - Compute duration (completed_at - started_at or halted_at - started_at)
   - Count subagent dispatches: 1 implementer + 1 gate-runner + 1 reviewer + (0 or 1) adversary, plus auto-fix loop rounds × 3
   - Read diff_stats from manifest
3. Print:
```
agentic-dev: usage report (filtered: <filter>)

Completed goals: <N>
Halted goals: <N>
Abandoned goals: <N>

Total subagent dispatches (estimate): <N>
Total wall-clock time across all goals: <duration>

Per-goal breakdown:
  <goal-id>  | status     | duration | dispatches | diff lines
  ...

Note: actual API token usage is in https://console.anthropic.com/settings/billing.
This report counts artifacts on disk to help you correlate.
```

### Borrowing from ruflo

ruflo's `ruflo-cost-tracker` reads from `~/.claude/sessions/*.json` to get actual prompt/completion tokens. We could borrow that approach if Claude Code exposes a stable per-session usage file. Worth checking the path; if available, our skill becomes more accurate.

Action item: spike on whether Claude Code writes per-session usage JSON we can read. If yes, use it. If no, fall back to artifact-counting.

### Test plan

Deterministic. Pure file-walking + arithmetic.
- `tests/phase-9/cost_skill_structure_test.py` — structural
- `tests/phase-9/cost_rollup_test.sh` — feeds hand-authored manifest fixtures + asserts the printed rollup numbers

---

## 5. Complement B — PII / prompt-injection scanning (v1.3.0)

### Goal

Prevent sensitive data (API keys, OAuth tokens, personal identifiable info) from being written into:
- `.claude/agentic/escalations/*.md` (which the user might share / email)
- `.claude/agentic/decisions.log` (audit trail)
- `.claude/agentic/memory.yaml` (cross-session memory)
- `.claude/agentic/checklist.yaml` (cross-session rules)
- `.claude/agentic/notifications-log.txt` (when Telegram unconfigured)

And separately, scan **specs** before they're approved for embedded secrets (e.g., a developer pasted an API key into the Intent section by accident).

### Design

`bin/check-pii.sh <file>` — exits 0 if clean; exits 1 with redaction suggestions if patterns matched. Patterns:

- AWS access key: `AKIA[0-9A-Z]{16}`
- AWS secret key (heuristic): high-entropy 40-char base64-like strings near "secret"
- OpenAI / Anthropic API keys: `sk-(ant-)?api[0-9]{2}-[A-Za-z0-9_-]{20,}`
- GitHub personal access tokens: `gh[oprsu]_[A-Za-z0-9]{36,}`
- Slack bot tokens: `xox[abprs]-[A-Za-z0-9-]{10,}`
- Email addresses (lower confidence; allowlist per project)
- Phone numbers (lower confidence; allowlist per project)
- Connection strings: `(mongodb|postgres|mysql|redis)://[^@]+:[^@]+@`
- Long high-entropy strings without obvious code context

Hook wiring:
- New `PostToolUse` hook on `Write|Edit` for files matching `.claude/agentic/{escalations,memory.yaml,checklist.yaml,decisions.log,notifications-log.txt}`.
- Hook output (per cost policy: stdout, not stderr) describes findings. **Non-blocking** — auto-storage discipline (P7-L4) means notification side-channels never block the pipeline. But warnings go to the operator's transcript.

Spec-pre-approval check:
- `_check-approval`'s pre-checks add: invoke `bin/check-pii.sh <spec-path>`. If non-empty findings → refuse with the redaction list. User cleans up, re-approves, retries.

### Borrowing from ruflo

`plugins/ruflo-aidefence/` has a curated PII regex set. MIT-licensed; we can copy the regex constants with attribution in the comment header. Don't depend on the runtime.

### Test plan

Deterministic.
- `tests/phase-9/check_pii_test.sh` — feeds files with known PII patterns; asserts each is detected
- Negative cases: code containing high-entropy strings that are NOT secrets (e.g., git SHAs, UUIDs) must not false-positive

---

## 6. Complement C — Walkthrough verification (v1.4.0)

### Goal

Fill the umbrella spec §6.5 step 4 gap: after the AI reviewer returns clean, run an actual UI walkthrough (Playwright) that exercises the goal's acceptance criteria. Catches things the manifest's test counts and the reviewer's code-read can't see (visual regressions, broken interactions, console errors).

For UI-touching goals only. Backend / library goals skip.

### Design

New spec section: `# Walkthrough`. Drafter prompts the user (or autofills "skip — non-UI goal") for:
- `acceptance_url` — what URL to load (relative to the dev server)
- `acceptance_criteria` — natural language list of behaviors to verify
- `start_command` — how to launch the dev server (e.g., `npm run dev`)

New subagent: `agents/walkthrough-runner.md`. Tools: `Read, Bash, mcp__playwright__*` (when available). Reads the spec's Walkthrough section, brings up the dev server, exercises the criteria, screenshots, reports JSON.

New schema: `schemas/walkthrough-verdict.schema.json` — JSON with verdict (clean | concern | blocking), per-criterion results, screenshots, console-error count.

New pipeline step in `_advance-goal`:
- After `_run-reviewer` returns clean
- Before queue advance
- Dispatches walkthrough-runner with the worktree path
- On verdict:
  - clean → goal completed
  - concern → re-dispatch implementer via auto-fix loop with walkthrough concerns as input
  - blocking → escalate

Worktree-init writes the dev server launch info into the kickoff package; walkthrough-runner reads it.

### Borrowing from ruflo

`plugins/ruflo-browser/` is a Playwright wrapper. Our use case is narrower (just walkthrough, not arbitrary browsing). Likely easier to use Playwright directly via the MCP `mcp__playwright__*` tools (which are already available in our environment, per the deferred-tools list) than to take a runtime dependency on ruflo-browser. We can borrow ruflo's session-as-skill pattern (their ADR-0001 documents it).

### Test plan

Mixed: deterministic for the schema + subagent prompt structure, agent-dispatched for one end-to-end smoke against a minimal Vite/React fixture. NO `claude -p`.

### Why this is a real phase (not a quick add)

- 4-5 new files
- A new spec section affects the drafter calibration table
- New schema, new subagent, new lifecycle step
- New gate that depends on a running dev server (long-running side effect — needs careful start/teardown)
- Integration tests need a small UI fixture

Best shipped as its own phase plan, similar to P3-P8 structure.

---

## 7. Complement D — Semantic checklist search (v1.5.0)

### Goal

When `checklist.yaml` grows past ~50 entries, grep-based lookup at reviewer dispatch becomes lossy — the reviewer reads ALL entries (long prompt context) and may not give equal attention to each. Semantic search would let us retrieve only the most-relevant 3-5 entries per goal.

### Design

Replace the all-entries-read-at-dispatch with a similarity-based retrieval:

1. `bin/log-incident.sh checklist` becomes `bin/log-incident.sh checklist` + a step that computes an embedding of the rule text and stores it alongside the YAML entry.
2. Embedding storage: SQLite database at `.claude/agentic/checklist.db` with `(id, date, rule, caught_by, embedding BLOB)` rows.
3. New helper: `bin/query-checklist.sh <text>` returns the top-K most-similar rules by cosine.
4. Reviewer subagent prompt updated: instead of reading all checklist.yaml, query it with the diff envelope's summary + spec body and get the top 5 most-relevant rules.

### Embedding model choice

- Option A: `sentence-transformers/all-MiniLM-L6-v2` via the `sentence-transformers` python package. Small (~80MB), CPU-fast, free.
- Option B: Anthropic's embeddings API (when available) or OpenAI text-embedding-3-small. Has a per-token cost but no model download.
- Option C: ruflo's RaBitQ-quantized embeddings (their ruvector library). Performant but adds dependency.

Recommendation: A. Free, CPU-only, no external deps.

### Borrowing from ruflo

ruflo's `ruflo-rag-memory` does exactly this with AgentDB + RaBitQ. We could borrow the AgentDB schema design but should NOT depend on their runtime (different memory backend; we'd be running both).

### Deferable

Currently `tradexpert`'s checklist.yaml has 0 entries. No empirical signal that we need semantic search. Build only when:
- Any project's `checklist.yaml` exceeds ~50 entries, OR
- Operator reports "the reviewer didn't catch X even though we had a checklist rule for it"

### Test plan

Deterministic. Embed-then-query tests with hand-authored rules; assert top-K results are the intended ones.

---

## 8. Test cost expectations

All four complements are designed to be deterministic-first per `docs/superpowers/test-cost-policy.md`:

| Complement | claude -p invocations | Agent-dispatched smoke | API cost estimate |
|---|---|---|---|
| Usage observability | 0 | 0 (file walking + arithmetic) | $0 |
| PII scanning | 0 | 0 (regex matching) | $0 |
| Walkthrough | 0 | 1 (end-to-end smoke at the end) | ~$2 |
| Semantic checklist | 0 | 0 (deterministic embedding + cosine) | $0 |

## 9. Out of scope for this design

- ruflo-federation-equivalent (cross-machine swarms) — not relevant
- ruflo-intelligence-equivalent (4-step learning pipeline) — conflicts with our reviewer's "find what's wrong THIS time" philosophy
- ruflo-autopilot-equivalent — we already have `_run-orchestrator`
- ruflo-swarm-equivalent (parallel goal execution) — explicitly rejected (linear queue is intentional)

## 10. References

- `docs/superpowers/ruflo-integration-notes.md` — boundary rules
- Umbrella spec §6.5 (verification flow), §13 (memory)
- ruflo repo: https://github.com/ruvnet/claude-flow (MIT licensed; safe to borrow code with attribution)
