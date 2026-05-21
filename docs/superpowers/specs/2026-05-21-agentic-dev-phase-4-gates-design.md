# Phase 4 — Deterministic Gates Design

**Status:** Draft (autonomous decision-mode per user authorization)
**Date:** 2026-05-21
**Phase:** P4 of P1–P8
**Umbrella spec:** `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` (§6.5 Verification, §8 Escalation policy gates)

---

## 1. Intent

Phase 4 ships the deterministic verification layer that runs AFTER the implementer (P3) produces a manifest, BEFORE the AI reviewer (P5). These gates are mechanical shell scripts — no Claude, no judgment. They catch the load-bearing failure modes the implementer's discipline alone shouldn't be the only line of defense for: out-of-scope file edits, budget exceedance, sensitive-path touches, test-count drops, lint/typecheck regressions, and false "pre-existing failure" claims. Each gate produces a structured pass/fail with details; the gate-runner aggregates them into a per-goal verdict.

The implementer is supposed to self-check these things in its manifest. The gates verify INDEPENDENTLY against the actual worktree state — never trusting the implementer's claims. This is the "trust artifacts, not claims" principle from the umbrella spec made deterministic.

## 2. Goals

- **G1** — Six independent gate scripts in `agentic-dev/bin/`, each takes the goal-id (or manifest path) + flags, exits 0 on pass / 1 on fail, prints structured details to stdout.
- **G2** — A `bin/run-gates.sh` orchestration wrapper that runs all gates in order, writes a verdict file, halts on first blocking failure.
- **G3** — `gate-verdict.schema.json` for the per-goal verdict file.
- **G4** — A `/agentic-dev:_run-gates` skill (internal, like `_run-implementer`) that wraps `run-gates.sh` with proper error reporting.
- **G5** — `bin/bisect-on-claim.sh` for the "is this really pre-existing?" forensic check from umbrella §6.5 step 6.
- **G6** — All tests deterministic per `docs/superpowers/test-cost-policy.md`. Zero `claude -p` in P4.

## 3. Non-goals

- AI judgment on diffs (P5's reviewer).
- Walkthrough / Playwright integration (umbrella §6.5 step 4 — not P4).
- Escalation packet generation (P5).
- Telegram notifications (P5).
- Automated invocation from the orchestrator (P6 wires this).

## 4. Architecture

```
agentic-dev/
├── schemas/
│   └── gate-verdict.schema.json    NEW — per-goal verdict structure
├── bin/
│   ├── gate-scope-check.sh         NEW — out-of-spec file edits
│   ├── gate-budget-check.sh        NEW — diff_lines / files_touched / wall_clock
│   ├── gate-sensitive-path-check.sh NEW — config.sensitive_paths globs touched
│   ├── gate-test-count-check.sh    NEW — tests.passed >= baseline tests.passed
│   ├── gate-rerun-tests.sh         NEW — independently re-runs tests in worktree
│   ├── bisect-on-claim.sh          NEW — verifies "pre-existing failure" claims
│   └── run-gates.sh                NEW — orchestration wrapper
├── skills/
│   └── _run-gates/SKILL.md         NEW — lifecycle wrapper
└── (existing files unchanged)
```

### Gate-runner pipeline

```
1. /agentic-dev:_run-gates <goal-id>
   ↓
2. run-gates.sh <goal-id>
   ↓
3. For each gate in order:
   a. gate-scope-check       → exits 0/1 + writes single-gate verdict to stdout
   b. gate-budget-check      → same
   c. gate-sensitive-path-check → same
   d. gate-test-count-check  → same
   e. gate-rerun-tests       → independently runs tests; compares to manifest
   ↓
4. run-gates.sh aggregates: writes .claude/agentic/verdicts/<goal-id>.json
   ↓
5. If overall.result == fail: prints failures; exits 1
   If pass: prints summary; exits 0
```

Each gate is independent — runs and exits cleanly even if others fail. `run-gates.sh` collects all results and decides the overall verdict.

### Read/write boundaries

| Component | Reads | Writes |
|---|---|---|
| Each `gate-*.sh` | manifest, kickoff, worktree, config | nothing (stdout only) |
| `run-gates.sh` | manifest, kickoff, all gate outputs | verdict file |
| `_run-gates` skill | manifest, kickoff | verdict file (via run-gates) |
| `bisect-on-claim.sh` | manifest, git history | nothing (stdout only) |

Gates are pure functions. Only `run-gates.sh` and `_run-gates` write the verdict file.

## 5. Gate details

### 5.1 `gate-scope-check.sh`

**Purpose:** Detect files outside the spec's "Files in scope" that were edited.

**Inputs:** manifest path, spec path.

**Algorithm:**
1. Parse `Files in scope` section from spec markdown (lines under `# Files in scope` heading).
2. Each entry is a glob (e.g., `src/**`, `tests/middleware/*.test.ts`).
3. Run `git diff --name-only <baseline_ref>..HEAD` in worktree.
4. For each touched file: check it matches at least one in-scope glob.
5. Files that don't match → out-of-spec.
6. Output: `{"gate": "scope-check", "result": "pass|fail", "out_of_spec_files": [...], "details": "..."}`.

Notes:
- Cross-check against `manifest.scope_check.out_of_spec_files`. If the implementer's self-reported list AND the gate's computed list disagree, this is a discipline failure — flag it.
- Glob matching uses Python's `fnmatch` for portability (bash globbing has shell-dependent extensions).

### 5.2 `gate-budget-check.sh`

**Purpose:** Diff didn't exceed declared budgets.

**Inputs:** manifest path, kickoff path.

**Algorithm:**
1. Read `kickoff.budget` (wall_clock_minutes_per_goal, diff_lines_per_goal, files_touched_per_goal).
2. Read `manifest.diff_stats`. Compute `lines_added + lines_removed`.
3. Compare against budget.
4. Output: pass if all under budget; fail if any over.

Wall-clock: derive from `manifest.completed_at - manifest.started_at`. If completed_at is null (interrupted/blocked), skip the wall-clock check and just note it.

### 5.3 `gate-sensitive-path-check.sh`

**Purpose:** Any file in a sensitive path was touched (auth, migrations, schema, secrets, payments, infra).

**Inputs:** manifest path, config path.

**Algorithm:**
1. Read `config.yaml`'s `sensitive_paths` globs.
2. Run `git diff --name-only <baseline_ref>..HEAD` in worktree.
3. Match touched files against globs.
4. Output: pass if no matches; fail with list of matched files if any.

This is one of the highest-severity gates — even a single sensitive-path touch should escalate to human regardless of other gates.

### 5.4 `gate-test-count-check.sh`

**Purpose:** Test count didn't drop. Catches deleted tests.

**Inputs:** manifest path, kickoff path.

**Algorithm:**
1. Read `manifest.tests.passed` and `manifest.tests.ran`.
2. Read `kickoff.baseline.test_counts` (added in P4 — kickoff now includes this).
3. If `manifest.tests.passed < kickoff.baseline.test_counts.passed`: fail.
4. Output: pass/fail + count comparison.

Note: P3's kickoff doesn't include baseline test counts. P4 adds this — `worktree-init.sh` will be updated to capture `kickoff.baseline.test_counts` by running the test command on the baseline.

This requires `worktree-init.sh` modification — captured as part of P4-T2.

### 5.5 `gate-rerun-tests.sh`

**Purpose:** Trust artifacts, not claims. Independently re-run the project's test command in the worktree to verify the manifest's reported counts.

**Inputs:** manifest path, kickoff path.

**Algorithm:**
1. Read `kickoff.project_commands.test`.
2. Run it in the worktree (via `git -C <worktree>` and shell exec).
3. Parse the output for pass/fail counts (test framework specific — best-effort: look for common patterns like "N tests passed" / "N tests failed").
4. Compare against `manifest.tests.{passed,failed}`.
5. Output: pass if match; fail with details if mismatch.

Notes:
- Test-output parsing is fragile across runners. v0.4 supports common patterns (jest, pytest, go test, mocha) via regex; framework-specific adapters defer to v0.4.x.
- If parsing fails, the gate reports inconclusive (neither pass nor fail) and the gate-runner decides — for v0.4, inconclusive counts as a warning, not a blocking failure.

### 5.6 `bisect-on-claim.sh`

**Purpose:** When a manifest's `deferrals` mentions "pre-existing failure", verify the failure existed before the goal's baseline_ref.

**Inputs:** manifest path, test command, failing test identifier.

**Algorithm:**
1. Check out `baseline_ref` in a TEMPORARY worktree (separate from goal's worktree to avoid disturbing it).
2. Run the test in the temp worktree.
3. If the test fails on baseline: confirmed pre-existing. Output: pass with confirmation.
4. If the test passes on baseline: pre-existing claim was false. Output: fail with timestamp range to git-bisect.
5. Clean up temp worktree.

Notes:
- Only invoked when a manifest claims a pre-existing failure.
- Run-gates calls bisect-on-claim only for manifests with relevant deferrals.

## 6. Gate verdict schema

`agentic-dev/schemas/gate-verdict.schema.json`:

```json
{
  "schema_version": "0.1",
  "goal_id": "...",
  "manifest_path": "...",
  "checked_at": "...",
  "gates": [
    {
      "name": "scope-check",
      "result": "pass | fail | inconclusive",
      "severity": "blocking | warning",
      "details": "human-readable summary",
      "raw": { ... gate-specific payload ... }
    }
  ],
  "overall": "pass | fail | warning",
  "blocking_failures": ["scope-check", ...],
  "warnings": [...]
}
```

`overall`:
- `pass` — all gates passed (or only warnings, no blocking failures)
- `fail` — at least one blocking failure
- `warning` — passed but with non-blocking warnings (e.g., test-output parse inconclusive)

Severity per gate:
- `scope-check` failure → blocking (out-of-scope edit is always a discipline failure)
- `budget-check` failure → blocking (budget exceeded means escalation)
- `sensitive-path-check` failure → blocking (always escalate)
- `test-count-check` failure → blocking (tests deleted)
- `rerun-tests` failure → blocking (claims diverge from reality)
- `rerun-tests` inconclusive (parse failure) → warning
- `bisect-on-claim` failure → blocking (false pre-existing claim is a discipline failure)

## 7. Lifecycle

```
1. P3's _run-implementer completes; manifest at .claude/agentic/manifests/<goal-id>.json
2. Caller invokes: /agentic-dev:_run-gates <goal-id>
3. Skill validates manifest exists, kickoff exists, worktree exists
4. Skill calls bin/run-gates.sh <goal-id>
5. run-gates.sh chains the gates; aggregates results; writes verdict
6. Skill prints summary; exits with overall verdict's exit code
7. (Out of P4 scope: P5's reviewer reads the verdict + manifest)
```

## 8. Testing strategy

All deterministic per `docs/superpowers/test-cost-policy.md`. Zero `claude -p`.

### 8.1 Deterministic unit tests

For each gate script, a bash test feeds hand-authored manifest + kickoff + worktree fixtures and asserts exit code + stdout patterns. Each gate gets ~3-4 fixtures (clean pass, clean fail, edge case).

### 8.2 Gate-verdict schema test

JSON Schema validation on hand-authored verdict fixtures (good + 3 negative cases).

### 8.3 Run-gates orchestration test

Feed a known-failing manifest (out-of-scope file in scope_check.out_of_spec_files) and assert run-gates exits 1 with the right blocking_failures.

### 8.4 No agent-dispatch smoke for P4

Gates are deterministic. Their behavior is verifiable from fixtures alone. No need for an LLM-driven E2E test. (P5 will run a smoke that exercises P3+P4+P5 end-to-end.)

Estimated P4 dev cost: **<$1** in API credits (no claude -p; just subagent dispatch tokens).

## 9. Load-bearing properties

- **P4-L1** — Gates verify INDEPENDENTLY from the manifest. The implementer's self-reported scope_check / tests counts are useful signals but not authoritative.
- **P4-L2** — Sensitive-path touches escalate regardless of any other gate's result.
- **P4-L3** — `rerun-tests` is the deciding artifact for test-count integrity. If parsing fails, it's a warning (not a green light).
- **P4-L4** — A failed gate cannot be downgraded by another gate. Multiple blocking failures all surface in `blocking_failures`.
- **P4-L5** — Gates are pure functions: read manifest/kickoff/worktree; output to stdout only. Only the runner writes the verdict file.

## 10. Scope of P4 v1 build

1. Schema: `gate-verdict.schema.json` + tests.
2. Six gate scripts: scope, budget, sensitive-path, test-count, rerun-tests, bisect-on-claim.
3. `worktree-init.sh` modification: capture baseline test counts in kickoff.
4. `run-gates.sh` orchestration wrapper.
5. `/agentic-dev:_run-gates` skill.
6. Tests for each gate + orchestration test.
7. Aggregator + README + CHANGELOG + plugin version → v0.4.0.

## 11. Out of scope (deferred)

- Walkthrough/Playwright integration (umbrella §6.5 step 4) — P5 or later.
- AI judgment on diffs (P5).
- Escalation packets (P5).
- Hook-fired auto-invocation of gates from spec save (P6 orchestrator).
- Framework-specific test-output adapters beyond regex (v0.4.x).
- Forensic git bisect across multiple commits (v0.4 supports single-commit check; full bisect is v0.4.x).

## 12. References

- Umbrella spec: §6.5 (verification flow), §8 (escalation gates), §11 (circuit breaker on gate fail)
- P3 design: `docs/superpowers/specs/2026-05-21-agentic-dev-phase-3-implementer-design.md`
- Test-cost policy: `docs/superpowers/test-cost-policy.md`
