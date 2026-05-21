# Phase 4 — Deterministic Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` syntax.

**Goal:** Ship v0.4: six deterministic gate scripts that verify the implementer's manifest claims against the actual worktree state (scope, budget, sensitive paths, test counts, test re-run, pre-existing-failure forensic), a run-gates orchestration wrapper, and a `_run-gates` skill. Zero AI judgment in P4 — that's P5.

**Architecture:** Each gate is an independent bash script that reads manifest + kickoff + worktree, outputs structured JSON to stdout, exits 0/1. The runner chains them, aggregates into a verdict file (`gate-verdict.schema.json`), halts on any blocking failure. All P4 tests are deterministic (no `claude -p`).

**Tech Stack:** Bash, Python (stdlib + jsonschema + pyyaml), JSON, git. **Reference design:** `docs/superpowers/specs/2026-05-21-agentic-dev-phase-4-gates-design.md`. **Cost policy:** `docs/superpowers/test-cost-policy.md` — zero `claude -p` in P4.

---

## File Structure

**Plugin source (new):**
- `agentic-dev/schemas/gate-verdict.schema.json`
- `agentic-dev/bin/gate-scope-check.sh`
- `agentic-dev/bin/gate-budget-check.sh`
- `agentic-dev/bin/gate-sensitive-path-check.sh`
- `agentic-dev/bin/gate-test-count-check.sh`
- `agentic-dev/bin/gate-rerun-tests.sh`
- `agentic-dev/bin/bisect-on-claim.sh`
- `agentic-dev/bin/run-gates.sh`
- `agentic-dev/skills/_run-gates/SKILL.md`

**Plugin source (modified):**
- `agentic-dev/bin/worktree-init.sh` — capture baseline test counts in kickoff JSON

**Tests:**
- `tests/phase-4/gate_verdict_schema_test.py`
- `tests/phase-4/gate_scope_check_test.sh`
- `tests/phase-4/gate_budget_check_test.sh`
- `tests/phase-4/gate_sensitive_path_test.sh`
- `tests/phase-4/gate_test_count_test.sh`
- `tests/phase-4/gate_rerun_tests_test.sh`
- `tests/phase-4/bisect_on_claim_test.sh`
- `tests/phase-4/run_gates_test.sh`
- `tests/phase-4/run_implementer_skill_modified_test.py` (verify kickoff has baseline test counts)
- `tests/phase-4/run_all.sh`
- `tests/phase-4/fixtures/` — kickoff, manifest, verdict fixtures

**Plugin meta:**
- `agentic-dev/.claude-plugin/plugin.json` — version 0.4.0
- `agentic-dev/README.md` — v0.4 section
- `agentic-dev/CHANGELOG.md` — v0.4.0 entry

---

## Task 1: gate-verdict schema + gate-scope-check + gate-budget-check

**Files:**
- Create: `agentic-dev/schemas/gate-verdict.schema.json`
- Create: `agentic-dev/bin/gate-scope-check.sh`
- Create: `agentic-dev/bin/gate-budget-check.sh`
- Create: `tests/phase-4/fixtures/sample-verdict.json`, `sample-manifest-clean.json`, `sample-manifest-out-of-scope.json`, `sample-kickoff.json`
- Create: `tests/phase-4/gate_verdict_schema_test.py`, `gate_scope_check_test.sh`, `gate_budget_check_test.sh`

**Per gate output format (JSON to stdout):**
```json
{
  "gate": "scope-check",
  "result": "pass | fail | inconclusive",
  "severity": "blocking | warning",
  "details": "human summary",
  "raw": { ... gate-specific ... }
}
```

**`gate-scope-check.sh` algorithm:**
1. Args: `<manifest-path> <spec-path>`
2. Parse the spec's `# Files in scope` section (bullet list of globs).
3. Get touched files: `git -C <worktree> diff --name-only <baseline>..HEAD`.
4. For each touched file, check if it matches any in-scope glob (use Python's `fnmatch.fnmatch`).
5. If any file is out-of-scope → `result: fail`, `severity: blocking`, list out-of-spec files in raw.
6. Also: cross-check against `manifest.scope_check.out_of_spec_files`. If they disagree, flag as discipline issue in details.

**`gate-budget-check.sh` algorithm:**
1. Args: `<manifest-path> <kickoff-path>`
2. Read `kickoff.budget.{diff_lines_per_goal, files_touched_per_goal, wall_clock_minutes_per_goal}`.
3. Read `manifest.diff_stats.{files_touched, lines_added, lines_removed}`. Compute `total_lines = added + removed`.
4. Compute wall_clock from `manifest.completed_at - manifest.started_at` (skip if completed_at is null).
5. Check each against budget. Any over → fail.

**Tests:**
- Schema test: positive case + 3 negative cases (bad result enum, missing required field, bad overall enum).
- gate-scope-check: 3 fixtures (all in-scope → pass; one out-of-scope → fail with file listed; manifest's reported out-of-spec matches actual → no discipline flag).
- gate-budget-check: 3 fixtures (under budget → pass; lines over → fail; files over → fail).

**Steps:**

- [ ] **1. Set up test directory + fixtures**

```bash
mkdir -p tests/phase-4/fixtures
```

Create `tests/phase-4/fixtures/sample-kickoff.json`:
```json
{
  "goal_id": "2026-05-21-test-goal",
  "spec_path": "/tmp/spec.md",
  "baseline_ref": "abc1234",
  "budget": {
    "wall_clock_minutes_per_goal": 30,
    "diff_lines_per_goal": 100,
    "files_touched_per_goal": 5
  },
  "sensitive_paths": ["auth/**", "migrations/**"],
  "project_commands": { "test": "echo passed", "lint": "echo lint-clean", "typecheck": null, "build": null },
  "worktree_path": "/tmp/worktree",
  "baseline": {
    "test_counts": { "passed": 10, "failed": 0, "skipped": 0 }
  }
}
```

Create `tests/phase-4/fixtures/sample-manifest-clean.json` (status: complete, diff_stats: files=3 lines+=42 lines-=0, scope_check.out_of_spec_files: [], tests passed=15 — see plan spec for full content; mirror P3's sample-manifest.json shape but with diff stats within budget).

Create `tests/phase-4/fixtures/sample-manifest-out-of-scope.json` — same as clean but with `scope_check.out_of_spec_files: ["src/secrets/leaked.ts"]` to test scope-check failure path.

Create `tests/phase-4/fixtures/sample-verdict.json`:
```json
{
  "schema_version": "0.1",
  "goal_id": "2026-05-21-test-goal",
  "manifest_path": ".claude/agentic/manifests/2026-05-21-test-goal.json",
  "checked_at": "2026-05-21T11:00:00Z",
  "gates": [
    { "name": "scope-check", "result": "pass", "severity": "blocking", "details": "all 3 touched files in scope" }
  ],
  "overall": "pass",
  "blocking_failures": [],
  "warnings": []
}
```

- [ ] **2. Write gate-verdict schema test**

Create `tests/phase-4/gate_verdict_schema_test.py` — mirrors P3's schema test pattern. Positive case validates sample-verdict.json; negatives test bad `overall` enum, bad `gates[].result` enum, missing required field.

- [ ] **3. Write failing schema test; confirm fail**

```bash
python3 tests/phase-4/gate_verdict_schema_test.py; echo "exit: $?"
```

- [ ] **4. Create `gate-verdict.schema.json`**

Required top-level: schema_version (const "0.1"), goal_id (pattern as in queue.schema.json), manifest_path, checked_at (date-time), gates (array), overall, blocking_failures (array of strings), warnings (array of strings).

Gates array items: required `name`, `result` (enum: pass|fail|inconclusive), `severity` (enum: blocking|warning), `details`. Optional `raw` (any object).

Overall: enum `pass|fail|warning`.

`additionalProperties: false` at all levels.

- [ ] **5. Re-run schema test; confirm 4 PASS lines**

- [ ] **6. Write scope-check test**

`tests/phase-4/gate_scope_check_test.sh`:
- Set up a tmp git repo + worktree
- Create a spec with `# Files in scope` listing globs (e.g., `src/**`)
- Make commits that touch in-scope + (in fail fixture) out-of-scope files
- Run gate-scope-check; assert exit code + JSON output's `result` field

- [ ] **7. Run; confirm fail (script doesn't exist)**

- [ ] **8. Create `bin/gate-scope-check.sh`**

```bash
#!/usr/bin/env bash
# gate-scope-check.sh <manifest-path> <spec-path>
# Exits 0 on pass / 1 on fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
SPEC="${2:-}"
if [[ -z "$MANIFEST" || -z "$SPEC" ]]; then
  echo '{"gate":"scope-check","result":"inconclusive","severity":"warning","details":"missing args"}'
  exit 1
fi

python3 - "$MANIFEST" "$SPEC" <<'PY'
import sys, json, re, fnmatch, subprocess
mpath, spec = sys.argv[1:3]
mf = json.load(open(mpath))
spec_text = open(spec).read()

# Extract "Files in scope" globs
m = re.search(r"^# Files in scope\s*$(.+?)(?=^# |\Z)", spec_text, re.MULTILINE | re.DOTALL)
globs = []
if m:
    for line in m.group(1).splitlines():
        line = line.strip()
        if line.startswith("- "):
            globs.append(line[2:].strip().strip("`"))

worktree = mf["worktree_path"]
baseline = mf["baseline_ref"]
head = mf.get("head_ref")

if not head:
    print(json.dumps({"gate":"scope-check","result":"inconclusive","severity":"warning",
                      "details":"head_ref null; no commits to check"}))
    sys.exit(0)

result = subprocess.run(["git","-C",worktree,"diff","--name-only",f"{baseline}..{head}"],
                       capture_output=True, text=True)
if result.returncode != 0:
    print(json.dumps({"gate":"scope-check","result":"inconclusive","severity":"warning",
                      "details":f"git diff failed: {result.stderr.strip()}"}))
    sys.exit(0)
touched = [f for f in result.stdout.strip().splitlines() if f]

out_of_spec = []
for f in touched:
    if not any(fnmatch.fnmatch(f, g) for g in globs):
        out_of_spec.append(f)

manifest_claim = mf.get("scope_check",{}).get("out_of_spec_files", [])
discipline_issue = sorted(out_of_spec) != sorted(manifest_claim)

if out_of_spec:
    print(json.dumps({
        "gate":"scope-check", "result":"fail", "severity":"blocking",
        "details": f"{len(out_of_spec)} out-of-spec file(s): " + ", ".join(out_of_spec),
        "raw":{
            "computed_out_of_spec": out_of_spec,
            "manifest_claim": manifest_claim,
            "discipline_issue": discipline_issue,
            "globs": globs,
            "touched_files": touched
        }
    }))
    sys.exit(1)
print(json.dumps({"gate":"scope-check","result":"pass","severity":"blocking",
                  "details":f"all {len(touched)} touched files in scope",
                  "raw":{"touched_files": touched, "globs": globs}}))
sys.exit(0)
PY
```

Make executable.

- [ ] **9. Re-run scope-check test; confirm pass**

- [ ] **10. Write budget-check test**

3 fixtures: all under budget; lines over; files over. Assertions on exit code + result field.

- [ ] **11. Run; confirm fail**

- [ ] **12. Create `bin/gate-budget-check.sh`**

Same shape as scope-check. Reads manifest.diff_stats + kickoff.budget. Compares. Outputs JSON.

- [ ] **13. Re-run budget-check test; confirm pass**

- [ ] **14. Commit**

`feat(phase-4): gate-verdict schema + scope + budget gates`

---

## Task 2: gate-sensitive-path + gate-test-count + worktree-init mod

**Files:**
- Create: `agentic-dev/bin/gate-sensitive-path-check.sh`
- Create: `agentic-dev/bin/gate-test-count-check.sh`
- Modify: `agentic-dev/bin/worktree-init.sh` (capture baseline test counts in kickoff)
- Create: `tests/phase-4/gate_sensitive_path_test.sh`
- Create: `tests/phase-4/gate_test_count_test.sh`
- Create: `tests/phase-4/run_implementer_skill_modified_test.py` (verify kickoff has baseline.test_counts field after worktree-init runs)

**`gate-sensitive-path-check.sh` algorithm:**
1. Args: `<manifest-path> <config-yaml-path>`
2. Read `config.sensitive_paths` (list of globs).
3. Get touched files from `git diff`.
4. Match against sensitive globs.
5. If any match → fail, severity blocking (always blocking for sensitive paths).

**`gate-test-count-check.sh` algorithm:**
1. Args: `<manifest-path> <kickoff-path>`
2. Read `kickoff.baseline.test_counts.passed`.
3. Read `manifest.tests.passed`.
4. If `manifest.tests.passed < kickoff.baseline.test_counts.passed` → fail blocking.

**worktree-init.sh modification:**
- After creating the worktree, run the project test command on the BASELINE state to capture the baseline test counts.
- Parse test output for counts using common regex (jest/pytest/etc.).
- Add `baseline.test_counts: {passed: N, failed: N, skipped: N}` to kickoff JSON.
- If test command fails or counts can't be parsed, set baseline to null with a warning. Gates that depend on it (test-count) will produce inconclusive.

**Steps:**
- [ ] 1. Write sensitive-path test (fixture: config with sensitive_paths, manifest with diff touching one). Run, expect fail.
- [ ] 2. Create gate-sensitive-path-check.sh; chmod +x.
- [ ] 3. Re-run sensitive-path test; expect pass.
- [ ] 4. Write test-count test (kickoff with baseline.test_counts.passed=10; manifest with tests.passed=8 → fail; passed=12 → pass).
- [ ] 5. Run; expect fail.
- [ ] 6. Create gate-test-count-check.sh; chmod +x.
- [ ] 7. Re-run; expect pass.
- [ ] 8. Write test for worktree-init modification — verify kickoff JSON has `baseline.test_counts` field after invocation.
- [ ] 9. Run; expect fail.
- [ ] 10. Modify worktree-init.sh to capture baseline test counts. Use the project's test command from config.yaml; parse stdout with a regex helper (Python in heredoc). On parse failure, set `baseline.test_counts: null`. Update existing worktree_init_test.sh to assert the new field is present.
- [ ] 11. Re-run all worktree tests (including P3's worktree_init_test.sh which exists — make sure it still passes with the new kickoff shape).
- [ ] 12. Commit `feat(phase-4): sensitive-path + test-count gates + baseline test counts in kickoff`.

---

## Task 3: gate-rerun-tests + bisect-on-claim

**Files:**
- Create: `agentic-dev/bin/gate-rerun-tests.sh`
- Create: `agentic-dev/bin/bisect-on-claim.sh`
- Create: `tests/phase-4/gate_rerun_tests_test.sh`
- Create: `tests/phase-4/bisect_on_claim_test.sh`

**`gate-rerun-tests.sh` algorithm:**
1. Args: `<manifest-path> <kickoff-path>`
2. Read `kickoff.project_commands.test`, `manifest.worktree_path`, `manifest.head_ref`.
3. Run test command in the worktree.
4. Parse output for test counts using regex patterns:
   - jest: `Tests:\s+(\d+)\s+passed`
   - pytest: `=+\s+(\d+)\s+passed`
   - go test: `ok\s+\S+\s+\d`
   - Generic fallback: count lines matching `PASS|FAIL`
5. Compare with `manifest.tests.{passed,failed}`. If counts don't match: fail. If parsing fails: inconclusive (warning).

**`bisect-on-claim.sh` algorithm:**
1. Args: `<manifest-path> <test-identifier>`
2. From manifest: `baseline_ref`, `worktree_path`, `kickoff.project_commands.test`.
3. Create a TEMP worktree at baseline_ref (separate from goal's worktree).
4. Run the test command (or test-identifier-specific subcommand) in the temp.
5. If it fails: pre-existing confirmed (pass).
6. If it passes: pre-existing claim is false (fail blocking).
7. Clean up temp worktree.

**Tests:** Use mock test runners (a script that echoes known output) to make rerun-tests deterministic. For bisect, create a fixture where a test fails on baseline (pre-existing) vs one where it passes (claim false).

**Steps:**
- [ ] 1-5. Write tests + scripts + iterate (same pattern as T1/T2).
- [ ] 6. Commit `feat(phase-4): rerun-tests + bisect-on-claim gates`.

---

## Task 4: run-gates orchestration + _run-gates skill

**Files:**
- Create: `agentic-dev/bin/run-gates.sh`
- Create: `agentic-dev/skills/_run-gates/SKILL.md`
- Create: `tests/phase-4/run_gates_test.sh`
- Create: `tests/phase-4/run_gates_skill_structure_test.py`

**`run-gates.sh` algorithm:**
1. Args: `<goal-id>`
2. Locate `.claude/agentic/manifests/<goal-id>.json`, `.worktrees/goal-<goal-id>/.agentic-kickoff.json`, the spec.
3. Run each gate in order: scope, budget, sensitive-path, test-count, rerun-tests.
4. For each, capture JSON output. Collect into `gates` array.
5. Compute `overall`: if any gate is `fail` AND severity `blocking` → overall `fail`. Else if any `fail/inconclusive` of warning severity → `warning`. Else `pass`.
6. Compute `blocking_failures`: list of gate names with `result: fail` AND `severity: blocking`.
7. Compute `warnings`: list of gate names with `result: fail` or `inconclusive` of warning severity.
8. Write `.claude/agentic/verdicts/<goal-id>.json` matching `gate-verdict.schema.json`.
9. Print summary; exit 0 if overall pass; 1 otherwise.

**`_run-gates` skill:** Pre-check manifest exists, kickoff exists, worktree exists. Call run-gates.sh. Print formatted summary of the verdict.

**Tests:**
- run-gates test: feeds known-good and known-bad manifests, asserts verdict file is written + structure is correct + overall result + blocking_failures list.
- Skill structural test (same pattern as P3-T4's `run_implementer_skill_structure_test.py`): asserts SKILL.md has required phrases.

**Steps:**
- [ ] 1-7. Write tests + scripts + iterate.
- [ ] 8. Commit `feat(phase-4): run-gates orchestration + _run-gates skill`.

---

## Task 5: Phase 4 run_all + completion checks

- [ ] 1. Create `tests/phase-4/run_all.sh` aggregating all P4 tests in order.
- [ ] 2. Run full P4 suite; expect all PASS.
- [ ] 3. Run P1+P2+P3 to confirm no regression.
- [ ] 4. Commit `test(phase-4): run_all aggregator`.

---

## Task 6: Docs + version bump + final verification

- [ ] 1. `agentic-dev/.claude-plugin/plugin.json`: version → "0.4.0".
- [ ] 2. `agentic-dev/README.md`: intro updated to v0.4; new v0.4 subsection; "What's coming next" starts from P5.
- [ ] 3. `agentic-dev/CHANGELOG.md`: new `## [0.4.0] — 2026-05-21` entry above v0.3.0 with all P4 additions.
- [ ] 4. Final run_all across all phases; commit `docs(phase-4): v0.4.0 — README + CHANGELOG + plugin version`.

---

## Phase 4 Completion Checklist

- [ ] `bash tests/phase-4/run_all.sh` exits 0
- [ ] P1, P2, P3 still pass
- [ ] plugin.json version is "0.4.0"
- [ ] CHANGELOG records v0.4.0
- [ ] All 6 task commits on the branch
- [ ] Zero `claude -p` invocations made during P4 dev
