# Multi-Component Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one agentic-dev project declare multiple components (e.g. `backend/` + `frontend/`), each with its own working directory and toolchain, and gate only the components a goal actually touches.

**Architecture:** A single shared Python helper (`agentic_components.py`) owns the component model: normalizing config into a component list (with a single-component fallback for back-compat) and mapping touched files to owning components. `worktree-init.sh` and the gate scripts import it so the rules live in exactly one place. Config and manifest schemas gain optional `components` / `tests_by_component`. The implementer and init/status skills are updated to produce and display per-component data.

**Tech Stack:** Bash + embedded Python 3 (stdlib only), JSON Schema (draft 2020-12), YAML config. Tests: Python (`jsonschema`/`pyyaml`) for schemas, Bash for scripts/skills.

## Global Constraints

- **Backward compatibility is load-bearing.** A config with only top-level `commands` (no `components`) must behave exactly as today. The full existing test suite must pass unchanged.
- **Normalization rule (verbatim):** if `components` is present and non-empty, use it; else synthesize `[{name: project.name, path: ".", primary_language: project.primary_language, commands: <top-level commands>}]`.
- **Touched-component detection (verbatim):** file `f` belongs to component `C` when `C.path == "."` (owns all) OR `f == C.path` OR `f` starts with `C.path + "/"`. When several match, the **longest** `C.path` wins. Files owned by no component are surfaced as a warning, never crash.
- Python is **stdlib only** in `bin/` (no new deps). Schemas are JSON Schema draft 2020-12 with `"additionalProperties": false`.
- Run tests with `bash tests/phase-N/<file>.sh` or `python3 tests/phase-N/<file>.py`. Test paths resolve from `__file__`/`$BASH_SOURCE`, not CWD.
- Commit after each task. No commits to anything but the working branch; the user pushes.

## File Structure

- `agentic-dev/bin/agentic_components.py` — **new.** Shared component model: `normalize`, `owner`, `select_touched`, `parse_test_counts`.
- `agentic-dev/schemas/config.schema.json` — add optional `components`.
- `agentic-dev/schemas/manifest.schema.json` — add optional `tests_by_component`.
- `agentic-dev/bin/worktree-init.sh` — per-component baseline + kickoff `components`.
- `agentic-dev/bin/gate-rerun-tests.sh` — rerun touched components.
- `agentic-dev/bin/gate-test-count-check.sh` — per-component baseline compare.
- `agentic-dev/agents/implementer-strict.md` — run + report per touched component.
- `agentic-dev/skills/init/SKILL.md` — multi-component prompts + YAML.
- `agentic-dev/skills/status/SKILL.md` — list components.
- `tests/phase-1`, `tests/phase-3`, `tests/phase-4` — new fixtures + cases.

---

### Task 1: Config schema — `components`

**Files:**
- Modify: `agentic-dev/schemas/config.schema.json`
- Create: `tests/phase-1/fixtures/config-multi-component.yaml`
- Modify: `tests/phase-1/schema_test.py`

**Interfaces:**
- Produces: config files MAY carry a top-level `components` array of `{name, path, primary_language?, commands:{test,lint,typecheck?,build?}}`. Top-level `commands` stays required.

- [ ] **Step 1: Write the failing fixture + test**

Create `tests/phase-1/fixtures/config-multi-component.yaml`:

```yaml
schema_version: "0.1"
project:
  name: fullstack-app
  primary_language: typescript
commands:
  test: "pytest -q"
  lint: "ruff check ."
  typecheck: ~
  build: ~
components:
  - name: backend
    path: backend
    primary_language: python
    commands:
      test: "pytest -q"
      lint: "ruff check ."
      typecheck: "mypy ."
      build: ~
  - name: frontend
    path: frontend
    primary_language: typescript
    commands:
      test: "npm test"
      lint: "npm run lint"
      typecheck: "tsc --noEmit"
      build: "npm run build"
budgets:
  wall_clock_minutes_per_goal: 90
  diff_lines_per_goal: 800
  files_touched_per_goal: 25
sensitive_paths: ["auth/**"]
telegram: ~
push_policy: hold
```

In `tests/phase-1/schema_test.py`, add to the validation list (next to the existing config fixture validation) a call validating `config-multi-component.yaml` against `config.schema.json`. Use the existing `validate(...)` helper and `load_yaml` loader, mirroring the existing config case.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-1/schema_test.py`
Expected: FAIL on `config-multi-component` — `Additional properties are not allowed ('components' was unexpected)`.

- [ ] **Step 3: Add `components` to the schema**

In `agentic-dev/schemas/config.schema.json`, add this property inside `properties` (e.g. after `commands`):

```json
"components": {
  "type": "array",
  "minItems": 1,
  "items": {
    "type": "object",
    "required": ["name", "path", "commands"],
    "additionalProperties": false,
    "properties": {
      "name": { "type": "string", "minLength": 1 },
      "path": { "type": "string", "minLength": 1 },
      "primary_language": { "type": ["string", "null"] },
      "commands": {
        "type": "object",
        "required": ["test", "lint"],
        "additionalProperties": false,
        "properties": {
          "test": { "type": "string", "minLength": 1 },
          "lint": { "type": "string", "minLength": 1 },
          "typecheck": { "type": ["string", "null"] },
          "build": { "type": ["string", "null"] }
        }
      }
    }
  }
}
```

Do **not** add `components` to the top-level `required` array — it stays optional.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-1/schema_test.py`
Expected: PASS for `config-multi-component` and all existing fixtures.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/schemas/config.schema.json tests/phase-1/fixtures/config-multi-component.yaml tests/phase-1/schema_test.py
git commit -m "feat(config): optional components array in config schema"
```

---

### Task 2: Shared component helper `agentic_components.py`

**Files:**
- Create: `agentic-dev/bin/agentic_components.py`
- Create: `tests/phase-3/agentic_components_test.py`

**Interfaces:**
- Produces (imported by Tasks 3, 5, 6):
  - `normalize(cfg: dict) -> list[dict]` — each item `{"name","path","primary_language","commands":{"test","lint","typecheck","build"}}`.
  - `owner(components: list, file_path: str) -> dict | None` — most-specific owning component.
  - `select_touched(components: list, files: list) -> tuple[list, list]` — `(selected_components_in_config_order, unmatched_files)`.
  - `parse_test_counts(output: str) -> dict | None` — `{"passed","failed","skipped"}` or `None`.

- [ ] **Step 1: Write the failing test**

Create `tests/phase-3/agentic_components_test.py`:

```python
"""Unit tests for the shared component helper."""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import agentic_components as ac  # noqa: E402

PASS = FAIL = 0
def check(name, cond):
    global PASS, FAIL
    if cond:
        print(f"PASS {name}"); PASS += 1
    else:
        print(f"FAIL {name}"); FAIL += 1

# normalize: single-component fallback
single = {"project": {"name": "p", "primary_language": "go"},
          "commands": {"test": "go test ./...", "lint": "golangci-lint run"}}
n = ac.normalize(single)
check("single-count", len(n) == 1)
check("single-path", n[0]["path"] == ".")
check("single-cmd", n[0]["commands"]["test"] == "go test ./...")
check("single-typecheck-none", n[0]["commands"]["typecheck"] is None)

# normalize: explicit components
multi = {"project": {"name": "p"},
         "commands": {"test": "x", "lint": "y"},
         "components": [
             {"name": "backend", "path": "backend",
              "commands": {"test": "pytest", "lint": "ruff check ."}},
             {"name": "frontend", "path": "frontend",
              "commands": {"test": "npm test", "lint": "eslint ."}}]}
m = ac.normalize(multi)
check("multi-count", len(m) == 2)
check("multi-names", [c["name"] for c in m] == ["backend", "frontend"])

# owner: prefix & specificity
check("owner-basic", ac.owner(m, "backend/app.py")["name"] == "backend")
check("owner-none", ac.owner(m, "docs/readme.md") is None)
# 'front' must NOT match 'frontend'
check("owner-segment", ac.owner(m, "frontendish/x.ts") is None)
# longest path wins
nested = ac.normalize({"components": [
    {"name": "all", "path": ".", "commands": {"test": "a", "lint": "b"}},
    {"name": "api", "path": "services/api", "commands": {"test": "c", "lint": "d"}}]})
check("owner-specific", ac.owner(nested, "services/api/main.py")["name"] == "api")
check("owner-dot-fallback", ac.owner(nested, "README.md")["name"] == "all")

# select_touched
sel, unmatched = ac.select_touched(m, ["backend/a.py", "backend/b.py", "docs/x.md"])
check("select-names", [c["name"] for c in sel] == ["backend"])
check("select-unmatched", unmatched == ["docs/x.md"])

# parse_test_counts
check("parse-pytest", ac.parse_test_counts("=== 5 passed, 1 failed ===") == {"passed": 5, "failed": 1, "skipped": 0})
check("parse-none", ac.parse_test_counts("no counts here") is None)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-3/agentic_components_test.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'agentic_components'`.

- [ ] **Step 3: Write the helper**

Create `agentic-dev/bin/agentic_components.py`:

```python
"""Shared component model: normalization, ownership, count parsing.

Imported by worktree-init.sh and the gate scripts so the single-vs-multi
component rules live in exactly one place. Stdlib only.
"""
import re


def _cmds(d):
    d = d or {}
    return {
        "test": d.get("test"),
        "lint": d.get("lint"),
        "typecheck": d.get("typecheck"),
        "build": d.get("build"),
    }


def normalize(cfg):
    """Return a list of normalized component dicts from a parsed config.yaml."""
    comps = cfg.get("components") or []
    if comps:
        return [{
            "name": c["name"],
            "path": c["path"],
            "primary_language": c.get("primary_language"),
            "commands": _cmds(c.get("commands")),
        } for c in comps]
    project = cfg.get("project") or {}
    return [{
        "name": project.get("name") or "project",
        "path": ".",
        "primary_language": project.get("primary_language"),
        "commands": _cmds(cfg.get("commands")),
    }]


def _depth(path):
    p = path.strip("/")
    if p in ("", "."):
        return 0
    return p.count("/") + 1


def _owns(component_path, file_path):
    cp = component_path.strip("/")
    fp = file_path.strip("/")
    if cp in ("", "."):
        return True
    return fp == cp or fp.startswith(cp + "/")


def owner(components, file_path):
    """Most-specific component owning file_path, or None."""
    best = None
    best_depth = -1
    for c in components:
        if _owns(c["path"], file_path) and _depth(c["path"]) > best_depth:
            best = c
            best_depth = _depth(c["path"])
    return best


def select_touched(components, files):
    """(selected_components_in_config_order, unmatched_files)."""
    hit = set()
    unmatched = []
    for f in files:
        c = owner(components, f)
        if c is None:
            unmatched.append(f)
        else:
            hit.add(c["name"])
    selected = [c for c in components if c["name"] in hit]
    return selected, unmatched


def parse_test_counts(output):
    """Parse {'passed','failed','skipped'} from test output, or None."""
    passed_n = failed_n = None

    m = re.search(r'Tests?:\s+(\d+)\s+passed', output, re.IGNORECASE)
    if m:
        passed_n = int(m.group(1))
    m2 = re.search(r'Tests?:.*?(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
    if m2:
        failed_n = int(m2.group(1))
    else:
        m2b = re.search(r'(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
        if m2b:
            failed_n = int(m2b.group(1))

    if passed_n is None:
        m = re.search(r'={3,}\s*(\d+)\s+passed', output, re.IGNORECASE)
        if m:
            passed_n = int(m.group(1))
    if failed_n is None:
        m = re.search(r'={3,}.*?(\d+)\s+failed', output, re.IGNORECASE)
        if m:
            failed_n = int(m.group(1))

    if passed_n is None:
        m = re.search(r'(\d+)\s+passed', output, re.IGNORECASE)
        if m:
            passed_n = int(m.group(1))
    if failed_n is None:
        m = re.search(r'(\d+)\s+failed', output, re.IGNORECASE)
        if m:
            failed_n = int(m.group(1))

    if passed_n is None:
        pass_lines = [l for l in output.splitlines() if re.match(r'^(PASS|ok)\b', l.strip())]
        fail_lines = [l for l in output.splitlines() if re.match(r'^FAIL\b', l.strip())]
        if pass_lines or fail_lines:
            passed_n = len(pass_lines)
            failed_n = len(fail_lines)

    if passed_n is None:
        return None

    skipped_n = 0
    m = re.search(r'(\d+)\s+skipped', output, re.IGNORECASE)
    if m:
        skipped_n = int(m.group(1))
    return {
        "passed": passed_n,
        "failed": failed_n if failed_n is not None else 0,
        "skipped": skipped_n,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-3/agentic_components_test.py`
Expected: PASS — `15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/agentic_components.py tests/phase-3/agentic_components_test.py
git commit -m "feat(bin): shared component model helper (normalize/owner/parse)"
```

---

### Task 3: Per-component baseline in `worktree-init.sh`

**Files:**
- Modify: `agentic-dev/bin/worktree-init.sh:64-96` (script-dir + commands block) and the baseline-run block (`:98-180`)
- Modify: `tests/phase-3/worktree_init_test.sh`

**Interfaces:**
- Consumes: `agentic_components.normalize`, `agentic_components.parse_test_counts`.
- Produces: kickoff JSON gains `components: [{name, path, commands, baseline_test_counts}]`. `project_commands` and `baseline.test_counts` remain, populated from `components[0]`.

- [ ] **Step 1: Add a failing assertion to the worktree-init test**

In `tests/phase-3/worktree_init_test.sh`, after the existing kickoff assertions, add a check that the kickoff has a `components` array whose first entry name matches the config's primary component and carries `baseline_test_counts`. Example assertion block (adapt variable names to the file's existing helpers):

```bash
COMPONENTS_LEN="$(python3 -c "import json;print(len(json.load(open('$KICKOFF')).get('components',[])))")"
if [[ "$COMPONENTS_LEN" -ge 1 ]]; then
  pass "kickoff has components array"
else
  fail "kickoff components" "expected >=1 component, got $COMPONENTS_LEN"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-3/worktree_init_test.sh`
Expected: FAIL `kickoff components: expected >=1 component, got 0`.

- [ ] **Step 3: Add SCRIPT_DIR and pass it to the heredoc**

In `agentic-dev/bin/worktree-init.sh`, after `set -euo pipefail` (line 8), add:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Change the kickoff-building invocation (line 73) from:

```bash
python3 - "$GOAL_ID" "$SPEC_PATH" "$ABS_WORKTREE_PATH" "$BASELINE_REF" "$CONFIG_PATH" <<'PY'
```

to additionally pass `SCRIPT_DIR`:

```bash
python3 - "$GOAL_ID" "$SPEC_PATH" "$ABS_WORKTREE_PATH" "$BASELINE_REF" "$CONFIG_PATH" "$SCRIPT_DIR" <<'PY'
```

- [ ] **Step 4: Replace the commands + baseline blocks with a per-component loop**

In the heredoc, update the argv unpack (line 75) to include `script_dir`:

```python
goal_id, spec_path, worktree_abs, baseline_ref, config_path, script_dir = sys.argv[1:7]
```

Immediately after `cfg = yaml.safe_load(open(config_path))` (line 76) add:

```python
sys.path.insert(0, script_dir)
import agentic_components as ac
components_norm = ac.normalize(cfg)
```

Replace the `project_commands = {...}` block (lines 91-96) and the entire baseline-run block (lines 98-180) with:

```python
import subprocess, os as _os

def run_baseline(test_cmd, cwd):
    if not test_cmd:
        return None
    try:
        proc = subprocess.run(
            test_cmd, shell=True, capture_output=True, text=True,
            cwd=cwd, timeout=120,
        )
    except Exception as exc:
        print(f"WARNING: worktree-init: baseline run failed in {cwd}: {exc}", file=sys.stderr)
        return None
    counts = ac.parse_test_counts(proc.stdout + "\n" + proc.stderr)
    if counts is None:
        print(f"WARNING: worktree-init: could not parse test counts for: {test_cmd}", file=sys.stderr)
    return counts

kickoff_components = []
for comp in components_norm:
    comp_cwd = _os.path.join(worktree_abs, comp["path"]) if comp["path"] not in (".", "") else worktree_abs
    kickoff_components.append({
        "name": comp["name"],
        "path": comp["path"],
        "commands": comp["commands"],
        "baseline_test_counts": run_baseline(comp["commands"].get("test"), comp_cwd),
    })

# Back-compat: first component drives the legacy single-command fields.
primary = kickoff_components[0]
project_commands = dict(primary["commands"])
baseline_test_counts = primary["baseline_test_counts"]
```

- [ ] **Step 5: Emit `components` in the kickoff dict**

Find where the kickoff dict is assembled (the object containing `"project_commands": project_commands` at line ~239 and `"baseline": {"test_counts": baseline_test_counts}` at ~242). Add a sibling key:

```python
    "components": kickoff_components,
```

Leave `project_commands` and `baseline.test_counts` exactly as they are (now sourced from `primary`).

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/phase-3/worktree_init_test.sh`
Expected: PASS including `kickoff has components array`.

- [ ] **Step 7: Commit**

```bash
git add agentic-dev/bin/worktree-init.sh tests/phase-3/worktree_init_test.sh
git commit -m "feat(worktree): per-component baseline test counts in kickoff"
```

---

### Task 4: Manifest schema — `tests_by_component`

**Files:**
- Modify: `agentic-dev/schemas/manifest.schema.json:37-48`
- Create: `tests/phase-3/fixtures/manifest-multi-component.json`
- Modify: `tests/phase-3/manifest_schema_test.py`

**Interfaces:**
- Produces: manifests MAY carry `tests_by_component: [{name, ran, passed, failed, skipped}]`. Aggregate `tests` stays required.

- [ ] **Step 1: Write a failing fixture + test**

Create `tests/phase-3/fixtures/manifest-multi-component.json` by copying the existing valid manifest fixture in `tests/phase-3/fixtures/` and adding:

```json
"tests_by_component": [
  { "name": "backend",  "ran": 12, "passed": 12, "failed": 0, "skipped": 0 },
  { "name": "frontend", "ran": 8,  "passed": 8,  "failed": 0, "skipped": 0 }
]
```

(keep its existing aggregate `tests` object as the sum: `ran: 20, passed: 20, failed: 0, skipped: 0`). In `tests/phase-3/manifest_schema_test.py`, add a validation of this fixture against `manifest.schema.json` using the file's existing helper.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-3/manifest_schema_test.py`
Expected: FAIL — `Additional properties are not allowed ('tests_by_component' was unexpected)`.

- [ ] **Step 3: Add `tests_by_component` to the schema**

In `agentic-dev/schemas/manifest.schema.json`, add this property in `properties` after the `tests` object (do **not** add it to `required`):

```json
"tests_by_component": {
  "type": "array",
  "items": {
    "type": "object",
    "required": ["name", "ran", "passed", "failed", "skipped"],
    "additionalProperties": false,
    "properties": {
      "name": { "type": "string", "minLength": 1 },
      "ran": { "type": "integer", "minimum": 0 },
      "passed": { "type": "integer", "minimum": 0 },
      "failed": { "type": "integer", "minimum": 0 },
      "skipped": { "type": "integer", "minimum": 0 }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-3/manifest_schema_test.py`
Expected: PASS for the new and all existing fixtures.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/schemas/manifest.schema.json tests/phase-3/fixtures/manifest-multi-component.json tests/phase-3/manifest_schema_test.py
git commit -m "feat(manifest): optional tests_by_component array"
```

---

### Task 5: `gate-rerun-tests.sh` — rerun touched components

**Files:**
- Modify: `agentic-dev/bin/gate-rerun-tests.sh`
- Modify: `tests/phase-4/gate_rerun_tests_test.sh`

**Interfaces:**
- Consumes: kickoff `components`, manifest `tests_by_component`, manifest `scope_check.{in_spec_files,out_of_spec_files}`, `agentic_components.{owner,parse_test_counts}`.
- Produces: same gate JSON contract (`{gate,result,severity,details,raw}`). Multi-component path runs per touched component; single-component path unchanged.

- [ ] **Step 1: Add a failing multi-component test case**

In `tests/phase-4/gate_rerun_tests_test.sh`, add a test that builds a kickoff with a `components` array (two components, each pointing at a mock runner in its own dir) and a manifest with `tests_by_component` claiming counts that **mismatch** one component's actual output, then asserts the gate returns `result: fail`, `severity: blocking`, and the failing component name appears in `details`. Reuse the file's `make_mock_runner` helper; write the kickoff/manifest with heredocs as the existing cases do.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-4/gate_rerun_tests_test.sh`
Expected: FAIL — the new case fails because the gate ignores `components` and only checks the aggregate.

- [ ] **Step 3: Branch the gate on `components`**

In `agentic-dev/bin/gate-rerun-tests.sh`, add a script dir and pass it to the heredoc. After `set -euo pipefail`, add:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Change the python invocation to pass it:

```bash
python3 - "$MANIFEST" "$KICKOFF" "$SCRIPT_DIR" <<'PY'
```

At the top of the heredoc, after loading `mf` and `kf`, add:

```python
import sys, os
script_dir = sys.argv[3]
sys.path.insert(0, script_dir)
import agentic_components as ac

kf_components = kf.get("components")
mf_by_comp = {c["name"]: c for c in (mf.get("tests_by_component") or [])}

if kf_components and mf_by_comp:
    # ── Multi-component path ────────────────────────────────────────────────
    worktree_path = mf.get("worktree_path")
    changed = (mf.get("scope_check", {}) or {}).get("in_spec_files", []) + \
              (mf.get("scope_check", {}) or {}).get("out_of_spec_files", [])
    touched, _unmatched = ac.select_touched(kf_components, changed)

    if not worktree_path:
        print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                          "severity": "warning",
                          "details": "manifest.worktree_path missing"}))
        sys.exit(0)

    import subprocess, re
    mismatches = []
    checked = []
    for comp in touched:
        test_cmd = comp["commands"].get("test")
        claim = mf_by_comp.get(comp["name"])
        if not test_cmd or claim is None:
            continue
        cwd = os.path.join(worktree_path, comp["path"]) if comp["path"] not in (".", "") else worktree_path
        try:
            proc = subprocess.run(test_cmd, shell=True, capture_output=True,
                                  text=True, cwd=cwd, timeout=300)
        except Exception as exc:
            print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                              "severity": "warning",
                              "details": f"{comp['name']}: test run failed: {exc}"}))
            sys.exit(0)
        counts = ac.parse_test_counts(proc.stdout + "\n" + proc.stderr)
        if counts is None:
            print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                              "severity": "warning",
                              "details": f"{comp['name']}: could not parse counts for {test_cmd}"}))
            sys.exit(0)
        checked.append(comp["name"])
        if counts["passed"] != claim.get("passed") or counts["failed"] != claim.get("failed", 0):
            mismatches.append(
                f"{comp['name']}: actual {counts['passed']}p/{counts['failed']}f vs "
                f"manifest {claim.get('passed')}p/{claim.get('failed', 0)}f")

    if mismatches:
        print(json.dumps({"gate": "rerun-tests", "result": "fail", "severity": "blocking",
                          "details": "per-component test mismatch: " + "; ".join(mismatches),
                          "raw": {"checked": checked}}))
        sys.exit(1)
    print(json.dumps({"gate": "rerun-tests", "result": "pass", "severity": "blocking",
                      "details": f"per-component test counts match: {', '.join(checked) or 'no touched components'}",
                      "raw": {"checked": checked}}))
    sys.exit(0)
# ── Single-component path falls through to existing logic below ─────────────
```

Leave the existing single-component logic untouched after this block.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/phase-4/gate_rerun_tests_test.sh`
Expected: PASS for the new multi-component case and all existing single-component cases.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/gate-rerun-tests.sh tests/phase-4/gate_rerun_tests_test.sh
git commit -m "feat(gate): rerun tests per touched component"
```

---

### Task 6: `gate-test-count-check.sh` — per-component baseline compare

**Files:**
- Modify: `agentic-dev/bin/gate-test-count-check.sh`
- Modify: `tests/phase-4/gate_test_count_test.sh`

**Interfaces:**
- Consumes: kickoff `components[].baseline_test_counts`, manifest `tests_by_component`, `agentic_components`.
- Produces: same gate JSON contract; multi-component compares each component's manifest counts to that component's kickoff baseline.

- [ ] **Step 1: Add a failing multi-component case**

In `tests/phase-4/gate_test_count_test.sh`, add a case with a kickoff carrying `components` (each with `baseline_test_counts`) and a manifest with `tests_by_component` where one component's `passed` is **below** its baseline; assert `result: fail` and the component name in `details`. (The existing gate semantics treat a drop below baseline as a regression — preserve that meaning per component.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-4/gate_test_count_test.sh`
Expected: FAIL — new case not yet handled.

- [ ] **Step 3: Branch the gate on `components`**

In `agentic-dev/bin/gate-test-count-check.sh`, add `SCRIPT_DIR` and pass it to the heredoc (same two edits as Task 5 Step 3). At the top of the heredoc after loading `mf`/`kf`, add a multi-component branch that mirrors the existing single-component baseline comparison but loops components:

```python
import sys, os
script_dir = sys.argv[3]
sys.path.insert(0, script_dir)
import agentic_components as ac

kf_components = {c["name"]: c for c in (kf.get("components") or [])}
mf_by_comp = mf.get("tests_by_component") or []

if kf_components and mf_by_comp:
    regressions = []
    compared = []
    for claim in mf_by_comp:
        base = (kf_components.get(claim["name"]) or {}).get("baseline_test_counts")
        if base is None or base.get("passed") is None:
            continue
        compared.append(claim["name"])
        if claim.get("passed", 0) < base["passed"]:
            regressions.append(
                f"{claim['name']}: manifest {claim.get('passed', 0)} < baseline {base['passed']}")
    if regressions:
        print(json.dumps({"gate": "test-count-check", "result": "fail", "severity": "blocking",
                          "details": "per-component count regression: " + "; ".join(regressions),
                          "raw": {"compared": compared}}))
        sys.exit(1)
    print(json.dumps({"gate": "test-count-check", "result": "pass", "severity": "blocking",
                      "details": f"per-component counts >= baseline: {', '.join(compared) or 'none'}",
                      "raw": {"compared": compared}}))
    sys.exit(0)
# ── Single-component path falls through to existing logic below ─────────────
```

Match the severity/result values to whatever the existing single-component path uses (read the file and copy its conventions; the snippet above assumes `blocking`).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/phase-4/gate_test_count_test.sh`
Expected: PASS for new and existing cases.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/gate-test-count-check.sh tests/phase-4/gate_test_count_test.sh
git commit -m "feat(gate): per-component baseline count comparison"
```

---

### Task 7: Implementer runs + reports per touched component

**Files:**
- Modify: `agentic-dev/agents/implementer-strict.md`
- Modify: `tests/phase-4/run_implementer_skill_modified_test.py` (or `tests/phase-3/implementer_structure_test.py` — whichever asserts manifest fields)

**Interfaces:**
- Consumes: `kickoff.components`.
- Produces: manifest `tests_by_component` + aggregate `tests` (the sum); `self_check` aggregate across touched components.

- [ ] **Step 1: Add a failing structure assertion**

In the implementer structure test, add an assertion that `implementer-strict.md` mentions `kickoff.components` and instructs reporting `tests_by_component`. Example (Python structure test style):

```python
text = (REPO_ROOT / "agentic-dev" / "agents" / "implementer-strict.md").read_text()
assert "kickoff.components" in text, "implementer must read kickoff.components"
assert "tests_by_component" in text, "implementer must report tests_by_component"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-3/implementer_structure_test.py`
Expected: FAIL on the new assertions.

- [ ] **Step 3: Update the implementer instructions**

In `agentic-dev/agents/implementer-strict.md`:

1. In the kickoff-shape JSON block (around line 24), add after `project_commands`:

```json
  "components": [
    { "name": "<component>", "path": "<dir>",
      "commands": { "test": "...", "lint": "...", "typecheck": null, "build": null },
      "baseline_test_counts": { "passed": 0, "failed": 0, "skipped": 0 } }
  ],
```

2. In the calibration table row "You complete a logical unit", change the test instruction to:

> Run the test command for **each component whose directory you touched** (`kickoff.components[].commands.test`, from that component's `path`). If `kickoff.components` is absent, fall back to `kickoff.project_commands.test`.

3. In the manifest-reporting section (around line 105, "`tests` — counts from the LAST test run"), add:

> `tests_by_component` — one entry per component you ran tests for: `{name, ran, passed, failed, skipped}`. The aggregate `tests` object is the **sum** across those entries. `self_check.lint`/`typecheck` are `clean` only if every touched component is clean.

4. In the completion-criteria row ("You finish all in-scope work AND all tests pass AND lint/typecheck pass"), change to:

> ...AND **every touched component's** tests pass AND **every touched component's** lint/typecheck pass.

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 tests/phase-3/implementer_structure_test.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/agents/implementer-strict.md tests/phase-3/implementer_structure_test.py
git commit -m "feat(implementer): run and report tests per touched component"
```

---

### Task 8: Init flow — multi-component prompts + YAML

**Files:**
- Modify: `agentic-dev/skills/init/SKILL.md`
- Modify: `tests/phase-1/init_test.sh`

**Interfaces:**
- Consumes: user answers (interactive) or a YAML file with an optional `components` block.
- Produces: `config.yaml` with a `components` array for multi-component projects; single-component projects produce today's output unchanged.

- [ ] **Step 1: Add a failing init test for multi-component YAML mode**

In `tests/phase-1/init_test.sh`, add a case that runs init with the `config-multi-component.yaml` fixture (Task 1) as `$ARGUMENTS` in a temp project and asserts the resulting `.claude/agentic/config.yaml` contains a `components:` key with two entries (`backend`, `frontend`). Mirror the existing YAML-mode case in the file.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-1/init_test.sh`
Expected: FAIL — init drops `components` (the SKILL never reads or writes it).

- [ ] **Step 3: Update the init SKILL**

In `agentic-dev/skills/init/SKILL.md`:

1. In the `config.yaml` "Required fields" section, add:

> - `components` (optional): if the input YAML contains a `components` array, reproduce it verbatim (same rules as other fields — exact values, YAML `null` preserved). When `components` is present, also write the top-level `commands` mirroring the **first** component (schema requires `commands`).

2. In "Interactive prompts", add a leading question:

> First ask (AskUserQuestion): "Does this project have one component or multiple (e.g. separate backend + frontend directories)?" If **one** → proceed with the existing single-component prompts. If **multiple** → for each component, ask its `name`, its directory `path`, and its `test`/`lint`/`typecheck`/`build` commands; collect into a `components` array. Set top-level `commands` to the first component's commands.

3. In the YAML-mode CRITICAL block, add `components` to the list of keys reproduced exactly.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/phase-1/init_test.sh`
Expected: PASS — config has `components` with `backend` and `frontend`; existing single-component cases still pass.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/skills/init/SKILL.md tests/phase-1/init_test.sh
git commit -m "feat(init): collect and write multi-component config"
```

---

### Task 9: Status lists components

**Files:**
- Modify: `agentic-dev/skills/status/SKILL.md`
- Modify: `tests/phase-1/status_test.sh`

**Interfaces:**
- Consumes: `config.yaml` (normalized via the same rule).
- Produces: status output lists each component (name, path, test/lint).

- [ ] **Step 1: Add a failing status assertion**

In `tests/phase-1/status_test.sh`, add a case seeding a multi-component `config.yaml` (two components) and asserting status output names both components. Mirror the file's existing status-output assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-1/status_test.sh`
Expected: FAIL — status shows only the single command summary.

- [ ] **Step 3: Update the status SKILL**

In `agentic-dev/skills/status/SKILL.md`, in the config-summary section, add: if `config.yaml` has a non-empty `components` array, list each as `  component: <name> (<path>) — test: <test> | lint: <lint>`; otherwise print today's single `test command` / `lint command` lines.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/phase-1/status_test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/skills/status/SKILL.md tests/phase-1/status_test.sh
git commit -m "feat(status): list components in status summary"
```

---

## Final verification

- [ ] Run the affected phase suites and confirm green:

```bash
bash tests/phase-1/run_all.sh
bash tests/phase-3/run_all.sh
bash tests/phase-4/run_all.sh
python3 tests/phase-3/agentic_components_test.py
```

Expected: all pass, including every pre-existing single-component test (proves back-compat).
