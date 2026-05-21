# Phase 3 — agentic-dev Implementer + Worktree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.3 of `agentic-dev`: an implementer-strict subagent with worktree-per-goal isolation, manifest + diff-envelope schemas, queue schema v0.2 with explicit new goal-item fields, and a `/agentic-dev:_run-implementer` lifecycle skill that wires it all together.

**Architecture:** Worktree-per-goal under `.worktrees/goal-<id>/`. The lifecycle skill creates the worktree from current HEAD via `git worktree add`, writes a kickoff JSON file with spec/baseline/budget/project-commands, dispatches the implementer-strict subagent with `cwd=.worktrees/goal-<id>/`. The implementer follows TDD discipline, halts on ambiguity, writes a structured manifest. The skill validates the manifest against `manifest.schema.json`, generates a diff envelope, writes both to `.claude/agentic/`.

**Tech Stack:** Markdown (skills, agent prompts), JSON (schemas, manifest, diff envelope), YAML (queue), Bash (worktree management + migration), Python stdlib + `jsonschema[format-nongpl]` + `pyyaml` (tests, already in tests/requirements.txt), Claude Code Agent tool (for subagent dispatch), git worktree.

**Reference spec:** `docs/superpowers/specs/2026-05-21-agentic-dev-phase-3-implementer-design.md`.

**Cost policy:** Per `docs/superpowers/test-cost-policy.md`. ALL P3 tests are deterministic — no `claude -p` invocations. One controller-driven Agent-dispatch smoke at task T6 final verification (Max-billed, zero API cost).

---

## File Structure

**Plugin source (new and modified):**
- `agentic-dev/schemas/queue.schema.json` — MODIFY: bump schema_version to "0.2", add new optional goal-item fields
- `agentic-dev/schemas/manifest.schema.json` — NEW: completion manifest schema
- `agentic-dev/schemas/diff-envelope.schema.json` — NEW: structured diff schema
- `agentic-dev/bin/worktree-init.sh` — NEW
- `agentic-dev/bin/worktree-cleanup.sh` — NEW
- `agentic-dev/bin/migrate-v0.1-to-v0.2.sh` — NEW
- `agentic-dev/agents/implementer-strict.md` — NEW
- `agentic-dev/skills/_run-implementer/SKILL.md` — NEW

**Tests (new under `tests/phase-3/`):**
- `tests/phase-3/queue_schema_v02_test.py`
- `tests/phase-3/manifest_schema_test.py`
- `tests/phase-3/diff_envelope_schema_test.py`
- `tests/phase-3/migration_test.sh`
- `tests/phase-3/worktree_init_test.sh`
- `tests/phase-3/worktree_cleanup_test.sh`
- `tests/phase-3/implementer_structure_test.py`
- `tests/phase-3/run_implementer_skill_structure_test.py`
- `tests/phase-3/run_all.sh`
- `tests/phase-3/fixtures/sample-queue-v02.yaml`
- `tests/phase-3/fixtures/sample-queue-v01.yaml` (input for migration test)
- `tests/phase-3/fixtures/sample-manifest.json`
- `tests/phase-3/fixtures/sample-diff-envelope.json`

**Repo-level:**
- `DEFERRED.md` — close P1-DEF-001
- `agentic-dev/README.md` — v0.3 update
- `agentic-dev/CHANGELOG.md` — v0.3.0 entry

---

## Task 1: Queue schema v0.2 + manifest schema + diff envelope schema + migration

**Files:**
- Modify: `agentic-dev/schemas/queue.schema.json`
- Create: `agentic-dev/schemas/manifest.schema.json`
- Create: `agentic-dev/schemas/diff-envelope.schema.json`
- Create: `agentic-dev/bin/migrate-v0.1-to-v0.2.sh`
- Create: `tests/phase-3/fixtures/sample-queue-v02.yaml`
- Create: `tests/phase-3/fixtures/sample-queue-v01.yaml`
- Create: `tests/phase-3/fixtures/sample-manifest.json`
- Create: `tests/phase-3/fixtures/sample-diff-envelope.json`
- Create: `tests/phase-3/queue_schema_v02_test.py`
- Create: `tests/phase-3/manifest_schema_test.py`
- Create: `tests/phase-3/diff_envelope_schema_test.py`
- Create: `tests/phase-3/migration_test.sh`

- [ ] **Step 1: Create test directory + fixtures**

```bash
mkdir -p tests/phase-3/fixtures
```

Create `tests/phase-3/fixtures/sample-queue-v01.yaml`:
```yaml
schema_version: "0.1"
goals:
  - id: 2026-05-21-example-goal
    spec_path: .claude/agentic/specs/2026-05-21-example-goal.md
    intent_path: null
    status: approved
    added_at: "2026-05-21T10:00:00Z"
```

Create `tests/phase-3/fixtures/sample-queue-v02.yaml`:
```yaml
schema_version: "0.2"
goals:
  - id: 2026-05-21-example-goal
    spec_path: .claude/agentic/specs/2026-05-21-example-goal.md
    intent_path: null
    status: running
    added_at: "2026-05-21T10:00:00Z"
    started_at: "2026-05-21T10:05:00Z"
    completed_at: null
    halted_at: null
    baseline_ref: "abc1234"
    head_ref: null
    worktree_path: ".worktrees/goal-2026-05-21-example-goal"
    manifest_path: null
    budget_overrides: null
```

Create `tests/phase-3/fixtures/sample-manifest.json`:
```json
{
  "schema_version": "0.1",
  "goal_id": "2026-05-21-example-goal",
  "spec_path": ".claude/agentic/specs/2026-05-21-example-goal.md",
  "worktree_path": ".worktrees/goal-2026-05-21-example-goal",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:42:00Z",
  "diff_stats": { "files_touched": 3, "lines_added": 42, "lines_removed": 0 },
  "tests": { "ran": 5, "passed": 5, "failed": 0, "skipped": 0, "logs_path": ".worktrees/goal-2026-05-21-example-goal/test-output.log" },
  "self_check": { "lint": "clean", "typecheck": "n/a" },
  "scope_check": { "in_spec_files": ["src/health.ts"], "out_of_spec_files": [] },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [],
  "artifacts": [],
  "commits": [
    { "sha": "def5678", "subject": "[2026-05-21-example-goal] add /health endpoint" }
  ]
}
```

Create `tests/phase-3/fixtures/sample-diff-envelope.json`:
```json
{
  "schema_version": "0.1",
  "goal_id": "2026-05-21-example-goal",
  "baseline_ref": "abc1234",
  "head_ref": "def5678",
  "generated_at": "2026-05-21T10:42:00Z",
  "files": [
    {
      "path": "src/health.ts",
      "change_kind": "added",
      "lines_added": 18,
      "lines_removed": 0,
      "hunks": [
        { "old_start": 0, "old_count": 0, "new_start": 1, "new_count": 18, "content": "+export function health() {\n+  return { status: 'ok' };\n+}\n" }
      ]
    }
  ],
  "raw_patch": "diff --git a/src/health.ts b/src/health.ts\nnew file mode 100644\nindex 0000000..1234abc\n--- /dev/null\n+++ b/src/health.ts\n@@ -0,0 +1,18 @@\n+export function health() {\n+  return { status: 'ok' };\n+}\n"
}
```

- [ ] **Step 2: Write failing schema tests**

Create `tests/phase-3/queue_schema_v02_test.py`:
```python
"""Validate queue.yaml fixtures against queue.schema.json v0.2."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(f"ERROR: missing dep ({e.name}); pip install -r tests/requirements.txt", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "queue.schema.json"
FIX = REPO_ROOT / "tests" / "phase-3" / "fixtures"


def main():
    results = []

    if not SCHEMA.exists():
        print(f"FAIL queue-v02-positive: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())

    # Positive: v0.2 fixture validates
    good = yaml.safe_load((FIX / "sample-queue-v02.yaml").read_text())
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS queue-v02-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL queue-v02-positive: {e.message}")
        results.append(False)

    # Negative: schema_version 0.1 fails (we bumped const to 0.2)
    bad_version = dict(good)
    bad_version["schema_version"] = "0.1"
    try:
        jsonschema.validate(bad_version, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL queue-v02-rejects-v01: v0.1 wrongly validated against v0.2 schema")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS queue-v02-rejects-v01")
        results.append(True)

    # Negative: goal with invalid status enum
    bad_status_goal = json.loads(json.dumps(good))
    bad_status_goal["goals"][0]["status"] = "nonsense"
    try:
        jsonschema.validate(bad_status_goal, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL queue-v02-bad-status: bad status wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS queue-v02-bad-status")
        results.append(True)

    # Negative: goal with extra unknown field (additionalProperties:false on items)
    extra_field = json.loads(json.dumps(good))
    extra_field["goals"][0]["unexpected_field"] = "x"
    try:
        jsonschema.validate(extra_field, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL queue-v02-extra-field: extra field wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS queue-v02-extra-field")
        results.append(True)

    # Positive: minimum goal (only id, status — new fields all optional)
    min_goal = {"schema_version": "0.2", "goals": [{"id": "2026-05-21-min", "status": "drafted"}]}
    try:
        jsonschema.validate(min_goal, schema, format_checker=jsonschema.FormatChecker())
        print("PASS queue-v02-minimum-goal")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL queue-v02-minimum-goal: {e.message}")
        results.append(False)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

Create `tests/phase-3/manifest_schema_test.py`:
```python
"""Validate manifest.json fixtures against manifest.schema.json."""
import json
import sys
from pathlib import Path

try:
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(f"ERROR: missing dep ({e.name}); pip install -r tests/requirements.txt", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "manifest.schema.json"
FIX = REPO_ROOT / "tests" / "phase-3" / "fixtures"


def main():
    results = []

    if not SCHEMA.exists():
        print(f"FAIL manifest-positive: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())
    good = json.loads((FIX / "sample-manifest.json").read_text())

    # Positive
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS manifest-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL manifest-positive: {e.message}")
        results.append(False)

    # Negative: bad status enum
    bad_status = json.loads(json.dumps(good))
    bad_status["status"] = "almost-done"
    try:
        jsonschema.validate(bad_status, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL manifest-bad-status: bad status wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS manifest-bad-status")
        results.append(True)

    # Negative: missing required field (goal_id)
    missing = {k: v for k, v in good.items() if k != "goal_id"}
    try:
        jsonschema.validate(missing, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL manifest-missing-goal-id: wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS manifest-missing-goal-id")
        results.append(True)

    # Negative: tests counts inconsistent (passed > ran)
    bad_counts = json.loads(json.dumps(good))
    bad_counts["tests"] = {"ran": 5, "passed": 6, "failed": 0, "skipped": 0, "logs_path": "x"}
    # NOTE: schema-level enforcement of passed<=ran would need conditional. For v0.3
    # we accept this and document; full constraint is a future polish item.
    # This test asserts the SHAPE is preserved even with logically-inconsistent values.
    try:
        jsonschema.validate(bad_counts, schema, format_checker=jsonschema.FormatChecker())
        print("PASS manifest-accepts-counts-shape (semantic validity is implementer's job)")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL manifest-accepts-counts-shape: {e.message}")
        results.append(False)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

Create `tests/phase-3/diff_envelope_schema_test.py`:
```python
"""Validate diff-envelope.json fixtures."""
import json, sys
from pathlib import Path

try:
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(f"ERROR: {e.name} missing", file=sys.stderr); sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "diff-envelope.schema.json"
FIX = REPO_ROOT / "tests" / "phase-3" / "fixtures"


def main():
    results = []
    if not SCHEMA.exists():
        print(f"FAIL diff-envelope-positive: schema not found at {SCHEMA}")
        sys.exit(1)
    schema = json.loads(SCHEMA.read_text())
    good = json.loads((FIX / "sample-diff-envelope.json").read_text())
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS diff-envelope-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL diff-envelope-positive: {e.message}")
        results.append(False)

    # Negative: bad change_kind
    bad = json.loads(json.dumps(good))
    bad["files"][0]["change_kind"] = "frobnicated"
    try:
        jsonschema.validate(bad, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL diff-envelope-bad-change-kind: wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS diff-envelope-bad-change-kind")
        results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run all three schema tests; confirm they fail (schemas not yet created)**

```bash
python3 tests/phase-3/queue_schema_v02_test.py; echo "exit: $?"
python3 tests/phase-3/manifest_schema_test.py; echo "exit: $?"
python3 tests/phase-3/diff_envelope_schema_test.py; echo "exit: $?"
```

Expected: all three exit 1 with "schema not found" or similar.

- [ ] **Step 4: Update `queue.schema.json` to v0.2**

Replace `agentic-dev/schemas/queue.schema.json` with:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Goal Queue",
  "description": "Ordered list of goals processed by the orchestrator. v0.2 adds optional fields populated as a goal progresses through the lifecycle.",
  "type": "object",
  "required": ["schema_version", "goals"],
  "additionalProperties": false,
  "properties": {
    "schema_version": {
      "type": "string",
      "const": "0.2"
    },
    "goals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "status"],
        "additionalProperties": false,
        "properties": {
          "id": {
            "type": "string",
            "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$",
            "description": "YYYY-MM-DD-<topic-slug>"
          },
          "spec_path": { "type": ["string", "null"] },
          "intent_path": { "type": ["string", "null"] },
          "status": {
            "type": "string",
            "enum": ["intent_only", "drafted", "approved", "running", "completed", "halted", "abandoned"]
          },
          "added_at": { "type": ["string", "null"], "format": "date-time" },
          "started_at": { "type": ["string", "null"], "format": "date-time" },
          "completed_at": { "type": ["string", "null"], "format": "date-time" },
          "halted_at": { "type": ["string", "null"], "format": "date-time" },
          "baseline_ref": { "type": ["string", "null"] },
          "head_ref": { "type": ["string", "null"] },
          "worktree_path": { "type": ["string", "null"] },
          "manifest_path": { "type": ["string", "null"] },
          "budget_overrides": {
            "type": ["object", "null"],
            "additionalProperties": false,
            "properties": {
              "wall_clock_minutes_per_goal": { "type": "integer", "minimum": 1 },
              "diff_lines_per_goal": { "type": "integer", "minimum": 1 },
              "files_touched_per_goal": { "type": "integer", "minimum": 1 }
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 5: Create `manifest.schema.json`**

Create `agentic-dev/schemas/manifest.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Completion Manifest",
  "description": "Structured output the implementer subagent produces at the end of a goal.",
  "type": "object",
  "required": [
    "schema_version", "goal_id", "spec_path", "worktree_path",
    "baseline_ref", "status", "started_at",
    "diff_stats", "tests", "self_check", "scope_check",
    "adrs_filed", "spec_change_requests", "deferrals",
    "clarifying_questions_asked", "artifacts", "commits"
  ],
  "additionalProperties": false,
  "properties": {
    "schema_version": { "type": "string", "const": "0.1" },
    "goal_id": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$" },
    "spec_path": { "type": "string", "minLength": 1 },
    "worktree_path": { "type": "string", "minLength": 1 },
    "baseline_ref": { "type": "string", "minLength": 1 },
    "head_ref": { "type": ["string", "null"] },
    "status": {
      "type": "string",
      "enum": ["complete", "blocked-on-clarification", "blocked-on-budget", "interrupted", "implementer-output-malformed"]
    },
    "started_at": { "type": "string", "format": "date-time" },
    "completed_at": { "type": ["string", "null"], "format": "date-time" },
    "diff_stats": {
      "type": "object",
      "required": ["files_touched", "lines_added", "lines_removed"],
      "additionalProperties": false,
      "properties": {
        "files_touched": { "type": "integer", "minimum": 0 },
        "lines_added": { "type": "integer", "minimum": 0 },
        "lines_removed": { "type": "integer", "minimum": 0 }
      }
    },
    "tests": {
      "type": "object",
      "required": ["ran", "passed", "failed", "skipped"],
      "additionalProperties": false,
      "properties": {
        "ran": { "type": "integer", "minimum": 0 },
        "passed": { "type": "integer", "minimum": 0 },
        "failed": { "type": "integer", "minimum": 0 },
        "skipped": { "type": "integer", "minimum": 0 },
        "logs_path": { "type": ["string", "null"] }
      }
    },
    "self_check": {
      "type": "object",
      "required": ["lint", "typecheck"],
      "additionalProperties": false,
      "properties": {
        "lint": { "type": "string", "enum": ["clean", "failures", "not-run", "n/a"] },
        "typecheck": { "type": "string", "enum": ["clean", "failures", "not-run", "n/a"] }
      }
    },
    "scope_check": {
      "type": "object",
      "required": ["in_spec_files", "out_of_spec_files"],
      "additionalProperties": false,
      "properties": {
        "in_spec_files": { "type": "array", "items": { "type": "string" } },
        "out_of_spec_files": { "type": "array", "items": { "type": "string" } }
      }
    },
    "adrs_filed": { "type": "array", "items": { "type": "string" } },
    "spec_change_requests": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["what", "reason"],
        "additionalProperties": false,
        "properties": {
          "what": { "type": "string" },
          "reason": { "type": "string" }
        }
      }
    },
    "deferrals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["item", "reason"],
        "additionalProperties": false,
        "properties": {
          "item": { "type": "string" },
          "reason": { "type": "string" }
        }
      }
    },
    "clarifying_questions_asked": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["question", "resolved_by"],
        "additionalProperties": false,
        "properties": {
          "question": { "type": "string" },
          "resolved_by": { "type": "string", "enum": ["spec_text", "escalated", "pending"] },
          "answer": { "type": ["string", "null"] }
        }
      }
    },
    "artifacts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind", "path"],
        "additionalProperties": false,
        "properties": {
          "kind": { "type": "string" },
          "path": { "type": "string" }
        }
      }
    },
    "commits": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["sha", "subject"],
        "additionalProperties": false,
        "properties": {
          "sha": { "type": "string", "minLength": 7 },
          "subject": { "type": "string", "minLength": 1 }
        }
      }
    }
  }
}
```

- [ ] **Step 6: Create `diff-envelope.schema.json`**

Create `agentic-dev/schemas/diff-envelope.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Diff Envelope",
  "description": "Structured wrapper around a goal's git diff. Generated by the lifecycle skill, consumed by reviewer (P5).",
  "type": "object",
  "required": ["schema_version", "goal_id", "baseline_ref", "head_ref", "generated_at", "files", "raw_patch"],
  "additionalProperties": false,
  "properties": {
    "schema_version": { "type": "string", "const": "0.1" },
    "goal_id": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$" },
    "baseline_ref": { "type": "string", "minLength": 1 },
    "head_ref": { "type": "string", "minLength": 1 },
    "generated_at": { "type": "string", "format": "date-time" },
    "files": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["path", "change_kind", "lines_added", "lines_removed"],
        "additionalProperties": false,
        "properties": {
          "path": { "type": "string", "minLength": 1 },
          "change_kind": { "type": "string", "enum": ["added", "modified", "deleted", "renamed"] },
          "lines_added": { "type": "integer", "minimum": 0 },
          "lines_removed": { "type": "integer", "minimum": 0 },
          "hunks": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["old_start", "old_count", "new_start", "new_count", "content"],
              "additionalProperties": false,
              "properties": {
                "old_start": { "type": "integer", "minimum": 0 },
                "old_count": { "type": "integer", "minimum": 0 },
                "new_start": { "type": "integer", "minimum": 0 },
                "new_count": { "type": "integer", "minimum": 0 },
                "content": { "type": "string" }
              }
            }
          }
        }
      }
    },
    "raw_patch": { "type": "string" }
  }
}
```

- [ ] **Step 7: Run the three schema tests; confirm they pass**

```bash
python3 tests/phase-3/queue_schema_v02_test.py
python3 tests/phase-3/manifest_schema_test.py
python3 tests/phase-3/diff_envelope_schema_test.py
```

Expected: 5 + 4 + 2 = 11 PASS lines, all exit 0.

- [ ] **Step 8: Write the migration script**

Create `agentic-dev/bin/migrate-v0.1-to-v0.2.sh`:
```bash
#!/usr/bin/env bash
# Migrate .claude/agentic/queue.yaml from schema v0.1 to v0.2.
#
# v0.2 adds optional fields to goal items (started_at, completed_at, halted_at,
# baseline_ref, head_ref, worktree_path, manifest_path, budget_overrides). Since
# they're optional, existing v0.1 goal items are valid in v0.2 — the only
# required change is bumping schema_version.
#
# Idempotent. Validates the result against queue.schema.json before writing.
set -euo pipefail

QUEUE_FILE="${1:-.claude/agentic/queue.yaml}"
if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "ERROR: queue file not found: $QUEUE_FILE" >&2
  exit 1
fi

# Detect plugin directory (we need queue.schema.json)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEMA="$PLUGIN_ROOT/schemas/queue.schema.json"

# Read current schema_version
CURRENT_VERSION="$(python3 -c "
import yaml, sys
data = yaml.safe_load(open('$QUEUE_FILE'))
print(data.get('schema_version', 'unknown'))
")"

if [[ "$CURRENT_VERSION" == "0.2" ]]; then
  echo "queue.yaml already at v0.2; no migration needed"
  exit 0
fi

if [[ "$CURRENT_VERSION" != "0.1" ]]; then
  echo "ERROR: queue.yaml has unexpected schema_version: $CURRENT_VERSION" >&2
  echo "  expected 0.1 (to migrate) or 0.2 (already migrated)" >&2
  exit 1
fi

# Migration: bump schema_version to "0.2". Existing fields stay; new fields
# remain absent (they're all optional).
python3 <<PY
import yaml, json, jsonschema
data = yaml.safe_load(open("$QUEUE_FILE"))
data["schema_version"] = "0.2"
# Validate before writing
schema = json.load(open("$SCHEMA"))
jsonschema.validate(data, schema, format_checker=jsonschema.FormatChecker())
# Write back with stable formatting
with open("$QUEUE_FILE", "w") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
PY

echo "migrated $QUEUE_FILE from v0.1 to v0.2"
```

Make executable: `chmod +x agentic-dev/bin/migrate-v0.1-to-v0.2.sh`.

- [ ] **Step 9: Write the migration test**

Create `tests/phase-3/migration_test.sh`:
```bash
#!/usr/bin/env bash
# Tests for bin/migrate-v0.1-to-v0.2.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIGRATE="$REPO_ROOT/agentic-dev/bin/migrate-v0.1-to-v0.2.sh"
V01_FIXTURE="$REPO_ROOT/tests/phase-3/fixtures/sample-queue-v01.yaml"
SCHEMA="$REPO_ROOT/agentic-dev/schemas/queue.schema.json"

TMP_DIR="$(mktemp -d -t agentic-migrate-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_DIR" || rm -rf "$TMP_DIR"' EXIT

# Copy v0.1 fixture into tmp
cp "$V01_FIXTURE" "$TMP_DIR/queue.yaml"

# Run migration
"$MIGRATE" "$TMP_DIR/queue.yaml"

# Assert schema_version is now 0.2
NEW_VERSION="$(python3 -c "import yaml; print(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['schema_version'])")"
if [[ "$NEW_VERSION" != "0.2" ]]; then
  echo "FAIL: schema_version did not bump (got: $NEW_VERSION)" >&2
  exit 1
fi
echo "PASS schema_version bumped from 0.1 to 0.2"

# Assert result validates against v0.2 schema
python3 <<PY
import yaml, json, jsonschema
data = yaml.safe_load(open("$TMP_DIR/queue.yaml"))
schema = json.load(open("$SCHEMA"))
jsonschema.validate(data, schema, format_checker=jsonschema.FormatChecker())
print("PASS migrated queue.yaml validates against queue.schema.json")
PY

# Assert existing goal items preserved
GOAL_COUNT="$(python3 -c "import yaml; print(len(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['goals']))")"
if [[ "$GOAL_COUNT" != "1" ]]; then
  echo "FAIL: goal count changed (expected 1, got $GOAL_COUNT)" >&2
  exit 1
fi
echo "PASS goal items preserved through migration"

# Idempotency: re-run migration; should no-op
"$MIGRATE" "$TMP_DIR/queue.yaml"
VERSION_AFTER="$(python3 -c "import yaml; print(yaml.safe_load(open('$TMP_DIR/queue.yaml'))['schema_version'])")"
if [[ "$VERSION_AFTER" != "0.2" ]]; then
  echo "FAIL: idempotent re-run changed schema_version (got $VERSION_AFTER)" >&2
  exit 1
fi
echo "PASS migration is idempotent (re-running on v0.2 keeps it at v0.2)"

# Reject unknown schema_version
echo 'schema_version: "9.9"' > "$TMP_DIR/bad.yaml"
echo 'goals: []' >> "$TMP_DIR/bad.yaml"
if "$MIGRATE" "$TMP_DIR/bad.yaml" 2>/dev/null; then
  echo "FAIL: migration on unknown version did not error" >&2
  exit 1
fi
echo "PASS migration rejects unknown schema_version"

echo "migration_test: OK"
```

Make executable: `chmod +x tests/phase-3/migration_test.sh`.

- [ ] **Step 10: Run the migration test**

```bash
bash tests/phase-3/migration_test.sh
```

Expected: 4 PASS lines + "migration_test: OK"; exit 0.

- [ ] **Step 11: Commit**

```bash
git add agentic-dev/schemas/queue.schema.json agentic-dev/schemas/manifest.schema.json agentic-dev/schemas/diff-envelope.schema.json agentic-dev/bin/migrate-v0.1-to-v0.2.sh tests/phase-3/
git commit -m "feat(phase-3): queue.schema.json v0.2 + manifest + diff-envelope schemas + migration

Resolves P1-DEF-001 per user decision (bump schema_version + add fields
explicitly, additionalProperties:false preserved).

- queue.schema.json bumped to v0.2 with eight new optional goal-item
  fields: started_at, completed_at, halted_at, baseline_ref, head_ref,
  worktree_path, manifest_path, budget_overrides.
- manifest.schema.json — completion manifest the implementer subagent
  produces. Strict schema with five status values, structured tests
  + self_check + scope_check + spec_change_requests + deferrals +
  clarifying_questions_asked.
- diff-envelope.schema.json — structured wrapper around git diff,
  reusable by reviewer in P5.
- bin/migrate-v0.1-to-v0.2.sh — one-shot idempotent migration script
  for existing queue.yaml files. Validates result against v0.2 schema
  before writing.
- tests/phase-3/ — 4 schema/migration tests covering positive cases,
  enum negative cases, missing-required-field cases, and idempotency.
  11 total PASS assertions; zero claude -p invocations.

Phase 3 task 1/6."
```

---

## Task 2: Worktree management scripts + tests

**Files:**
- Create: `agentic-dev/bin/worktree-init.sh`
- Create: `agentic-dev/bin/worktree-cleanup.sh`
- Create: `tests/phase-3/worktree_init_test.sh`
- Create: `tests/phase-3/worktree_cleanup_test.sh`

- [ ] **Step 1: Write the worktree-init test**

Create `tests/phase-3/worktree_init_test.sh`:
```bash
#!/usr/bin/env bash
# Tests for bin/worktree-init.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKTREE_INIT="$REPO_ROOT/agentic-dev/bin/worktree-init.sh"

TMP_PROJECT="$(mktemp -d -t agentic-worktree-init-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Create a spec file
mkdir -p .claude/agentic/{intents,specs}
SPEC=.claude/agentic/specs/2026-05-21-test-goal.md
cat > "$SPEC" <<'SPEC_EOF'
---
id: 2026-05-21-test-goal
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-21-test-goal.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test goal.

# Files in scope
- src/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC_EOF

echo "stub" > .claude/agentic/intents/2026-05-21-test-goal.md

# Create a minimal config.yaml (worktree-init reads project commands)
cat > .claude/agentic/config.yaml <<'CFG_EOF'
schema_version: "0.1"
project:
  name: test-project
  primary_language: javascript
commands:
  test: "npm test"
  lint: "npm run lint"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 90
  diff_lines_per_goal: 800
  files_touched_per_goal: 25
sensitive_paths:
  - "auth/**"
telegram: null
push_policy: hold
CFG_EOF

# Run worktree-init
WORKTREE_PATH="$("$WORKTREE_INIT" 2026-05-21-test-goal)"
echo "Created worktree at: $WORKTREE_PATH"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "FAIL: worktree directory not created" >&2
  exit 1
fi
echo "PASS worktree directory created at expected path"

if [[ "$WORKTREE_PATH" != *".worktrees/goal-2026-05-21-test-goal"* ]]; then
  echo "FAIL: worktree path doesn't match .worktrees/goal-<id> pattern: $WORKTREE_PATH" >&2
  exit 1
fi
echo "PASS worktree path follows .worktrees/goal-<id>/ pattern"

# Kickoff file should exist
KICKOFF="$WORKTREE_PATH/.agentic-kickoff.json"
if [[ ! -f "$KICKOFF" ]]; then
  echo "FAIL: kickoff file not created at $KICKOFF" >&2
  exit 1
fi
echo "PASS kickoff file created"

# Kickoff should have required fields
python3 <<PY
import json
k = json.load(open("$KICKOFF"))
required = ["goal_id", "spec_path", "baseline_ref", "budget", "sensitive_paths", "project_commands"]
missing = [r for r in required if r not in k]
if missing:
    print(f"FAIL: kickoff missing fields: {missing}")
    import sys; sys.exit(1)
print("PASS kickoff has all required fields")

# Specific value checks
assert k["goal_id"] == "2026-05-21-test-goal", f"goal_id mismatch: {k['goal_id']}"
assert k["spec_path"].endswith(".claude/agentic/specs/2026-05-21-test-goal.md"), f"spec_path: {k['spec_path']}"
assert k["budget"]["wall_clock_minutes_per_goal"] == 90, f"budget: {k['budget']}"
assert k["project_commands"]["test"] == "npm test", f"commands: {k['project_commands']}"
print("PASS kickoff field values are correct")
PY

# Refuses to create duplicate worktree
if "$WORKTREE_INIT" 2026-05-21-test-goal 2>/dev/null; then
  echo "FAIL: worktree-init did not refuse on duplicate goal-id" >&2
  exit 1
fi
echo "PASS worktree-init refuses on duplicate goal-id"

echo "worktree_init_test: OK"
```

Make executable.

- [ ] **Step 2: Run, confirm fail (script not yet created)**

```bash
bash tests/phase-3/worktree_init_test.sh; echo "exit: $?"
```

Expected: fail; exit 1.

- [ ] **Step 3: Create `worktree-init.sh`**

Create `agentic-dev/bin/worktree-init.sh`:
```bash
#!/usr/bin/env bash
# Create a fresh git worktree for an agentic-dev goal and write the kickoff
# package the implementer subagent reads.
#
# Usage: worktree-init.sh <goal-id>
# Output (stdout): absolute path to the created worktree
# Exits 1 on error.
set -euo pipefail

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: worktree-init.sh <goal-id>" >&2
  exit 1
fi

# Validate goal-id format
if [[ ! "$GOAL_ID" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$ ]]; then
  echo "ERROR: goal-id must match YYYY-MM-DD-<slug>; got: $GOAL_ID" >&2
  exit 1
fi

# Must run from inside an initialized project
if [[ ! -f .claude/agentic/state.json ]]; then
  echo "ERROR: not an agentic-dev project (no .claude/agentic/state.json)" >&2
  exit 1
fi

SPEC_PATH=".claude/agentic/specs/${GOAL_ID}.md"
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "ERROR: spec file not found: $SPEC_PATH" >&2
  exit 1
fi

# Spec must be approved
APPROVED="$(python3 -c "
import sys
text = open('$SPEC_PATH').read()
if not text.startswith('---'):
    print('false')
    sys.exit(0)
parts = text.split('---', 2)
if len(parts) < 3:
    print('false')
    sys.exit(0)
import yaml
fm = yaml.safe_load(parts[1])
print('true' if fm.get('approved') else 'false')
")"

if [[ "$APPROVED" != "true" ]]; then
  echo "ERROR: spec is not approved (approved: false)" >&2
  exit 1
fi

WORKTREE_PATH=".worktrees/goal-${GOAL_ID}"
ABS_WORKTREE_PATH="$(pwd)/${WORKTREE_PATH}"

if [[ -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree already exists at $WORKTREE_PATH" >&2
  echo "  Run worktree-cleanup.sh ${GOAL_ID} first if you want to start fresh." >&2
  exit 1
fi

# Create worktree from current HEAD
mkdir -p .worktrees
BASELINE_REF="$(git rev-parse HEAD)"
git worktree add "$WORKTREE_PATH" HEAD --quiet

# Read project commands from config.yaml
CONFIG_PATH=".claude/agentic/config.yaml"

# Build kickoff JSON
python3 - "$GOAL_ID" "$SPEC_PATH" "$ABS_WORKTREE_PATH" "$BASELINE_REF" "$CONFIG_PATH" <<'PY'
import sys, json, yaml, os
goal_id, spec_path, worktree_abs, baseline_ref, config_path = sys.argv[1:6]
cfg = yaml.safe_load(open(config_path))

# Override budgets if the spec carries a Diff budget section with non-default values
# (P3 simplification: read budgets from config.yaml; per-goal overrides come in v0.3.x)
budget = {
    "wall_clock_minutes_per_goal": cfg["budgets"]["wall_clock_minutes_per_goal"],
    "diff_lines_per_goal": cfg["budgets"]["diff_lines_per_goal"],
    "files_touched_per_goal": cfg["budgets"]["files_touched_per_goal"],
}

# spec_path passed to implementer should be relative to the worktree root,
# but the SPEC LIVES in the main project's .claude/agentic/specs/, NOT in the
# worktree. So we pass an absolute path so the implementer can read it.
abs_spec_path = os.path.abspath(spec_path)

kickoff = {
    "goal_id": goal_id,
    "spec_path": abs_spec_path,
    "baseline_ref": baseline_ref,
    "budget": budget,
    "sensitive_paths": cfg["sensitive_paths"],
    "project_commands": {
        "test": cfg["commands"]["test"],
        "lint": cfg["commands"]["lint"],
        "typecheck": cfg["commands"].get("typecheck"),
        "build": cfg["commands"].get("build"),
    },
    "worktree_path": worktree_abs,
}

with open(os.path.join(worktree_abs, ".agentic-kickoff.json"), "w") as f:
    json.dump(kickoff, f, indent=2)
PY

# Print worktree path on stdout (caller captures this)
echo "$ABS_WORKTREE_PATH"
```

Make executable.

- [ ] **Step 4: Re-run worktree-init test; confirm pass**

```bash
bash tests/phase-3/worktree_init_test.sh; echo "exit: $?"
```

Expected: 5 PASS lines + "worktree_init_test: OK"; exit 0.

- [ ] **Step 5: Write worktree-cleanup test**

Create `tests/phase-3/worktree_cleanup_test.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKTREE_INIT="$REPO_ROOT/agentic-dev/bin/worktree-init.sh"
WORKTREE_CLEANUP="$REPO_ROOT/agentic-dev/bin/worktree-cleanup.sh"

TMP_PROJECT="$(mktemp -d -t agentic-cleanup-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo x > x.txt
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Set up minimal project state
mkdir -p .claude/agentic/{intents,specs}
echo '{"schema_version":"0.1","circuit_breaker":{"state":"idle","halted_reason":null,"halted_at":null,"halted_goal_id":null},"current_goal":null,"last_updated":"2026-05-21T10:00:00Z"}' > .claude/agentic/state.json

SPEC=.claude/agentic/specs/2026-05-21-cleanup-goal.md
cat > "$SPEC" <<'SPEC_EOF'
---
id: 2026-05-21-cleanup-goal
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-21-cleanup-goal.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test.

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC_EOF
echo stub > .claude/agentic/intents/2026-05-21-cleanup-goal.md

cat > .claude/agentic/config.yaml <<'CFG'
schema_version: "0.1"
project:
  name: t
  primary_language: javascript
commands:
  test: "npm test"
  lint: "npm run lint"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 100
  files_touched_per_goal: 5
sensitive_paths: ["auth/**"]
telegram: null
push_policy: hold
CFG

# Create a worktree first
"$WORKTREE_INIT" 2026-05-21-cleanup-goal > /dev/null

if [[ ! -d .worktrees/goal-2026-05-21-cleanup-goal ]]; then
  echo "FAIL setup: worktree not created" >&2
  exit 1
fi
echo "PASS setup: worktree exists"

# Run cleanup
"$WORKTREE_CLEANUP" 2026-05-21-cleanup-goal

if [[ -d .worktrees/goal-2026-05-21-cleanup-goal ]]; then
  echo "FAIL: worktree still exists after cleanup" >&2
  exit 1
fi
echo "PASS worktree removed after cleanup"

# Refuses unknown goal-id
if "$WORKTREE_CLEANUP" no-such-goal 2>/dev/null; then
  echo "FAIL: cleanup did not error on unknown goal-id" >&2
  exit 1
fi
echo "PASS cleanup errors on unknown goal-id"

echo "worktree_cleanup_test: OK"
```

Make executable.

- [ ] **Step 6: Create `worktree-cleanup.sh`**

Create `agentic-dev/bin/worktree-cleanup.sh`:
```bash
#!/usr/bin/env bash
# Remove an agentic-dev goal's worktree.
# Usage: worktree-cleanup.sh <goal-id>
set -euo pipefail

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: worktree-cleanup.sh <goal-id>" >&2
  exit 1
fi

WORKTREE_PATH=".worktrees/goal-${GOAL_ID}"
if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree not found at $WORKTREE_PATH" >&2
  exit 1
fi

# Remove via git worktree (safer than rm -rf — handles git's bookkeeping)
git worktree remove "$WORKTREE_PATH" --force
git worktree prune

echo "removed worktree: $WORKTREE_PATH"
```

Make executable.

- [ ] **Step 7: Re-run cleanup test**

```bash
bash tests/phase-3/worktree_cleanup_test.sh; echo "exit: $?"
```

Expected: 3 PASS + "worktree_cleanup_test: OK"; exit 0.

- [ ] **Step 8: Commit**

```bash
git add agentic-dev/bin/worktree-init.sh agentic-dev/bin/worktree-cleanup.sh tests/phase-3/worktree_init_test.sh tests/phase-3/worktree_cleanup_test.sh
git commit -m "feat(phase-3): worktree-init.sh + worktree-cleanup.sh + tests

- bin/worktree-init.sh: validates goal-id format, requires approved
  spec, refuses duplicates, runs `git worktree add` from current HEAD,
  writes .agentic-kickoff.json with goal_id, spec_path (absolute),
  baseline_ref, budget, sensitive_paths, project_commands, worktree_path.
- bin/worktree-cleanup.sh: removes a goal's worktree via
  `git worktree remove --force` + prune. Errors on unknown goal-id.
- worktree_init_test.sh: 5 assertions (creation, path pattern, kickoff
  presence, kickoff field shape + values, duplicate refusal).
- worktree_cleanup_test.sh: 3 assertions (setup, removal, error on
  unknown goal-id).

Per cost policy: zero claude -p invocations. All assertions deterministic.

Phase 3 task 2/6."
```

---

## Task 3: implementer-strict subagent

**Files:**
- Create: `agentic-dev/agents/implementer-strict.md`
- Create: `tests/phase-3/implementer_structure_test.py`

- [ ] **Step 1: Write the structural test for the agent**

Create `tests/phase-3/implementer_structure_test.py`:
```python
"""Verify implementer-strict.md has required structure and content.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the agent file has the right shape and
key phrases that encode anti-eagerness discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agentic-dev" / "agents" / "implementer-strict.md"


def main():
    failures = []

    if not AGENT.exists():
        print(f"FAIL setup: {AGENT} does not exist")
        sys.exit(1)
    text = AGENT.read_text()

    # Frontmatter present
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener")

    # Required frontmatter fields
    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter not parseable")
    else:
        fm = fm_match.group(1)
        for field in ["name:", "description:", "tools:"]:
            if not re.search(rf"^{field}", fm, re.MULTILINE):
                failures.append(f"frontmatter missing field: {field}")

        # Tools list: must include Read, Edit, Write, Bash, Glob, Grep
        tools_line = re.search(r"^tools:\s*(.+)$", fm, re.MULTILINE)
        if tools_line:
            tools = tools_line.group(1)
            for required in ["Read", "Edit", "Write", "Bash"]:
                if required not in tools:
                    failures.append(f"tools missing: {required}")

    # Anti-eagerness key phrases — these are load-bearing
    required_phrases = [
        "Files in scope",
        "halt with",
        "clarifying_question",
        "test-driven",
        "TDD",
        "never commit to main",
        "never push",
        "manifest",
        "out_of_spec_files",
        "do not guess",
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Calibration table must have specific rows (situations)
    situations = [
        "Files in scope",
        "outside",  # "outside Files in scope" or "outside scope"
        "spec doesn't say",
        "dependency",
        "budget",
        "test fails",
        "pre-existing",
        "wall-clock",
        "in-scope work",
    ]
    for s in situations:
        if s.lower() not in text.lower():
            failures.append(f"calibration row missing concept: {s!r}")

    # Output contract: must produce manifest as JSON object
    if "manifest" not in text.lower() or "json" not in text.lower():
        failures.append("output contract doesn't describe manifest as JSON")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS implementer-strict.md has frontmatter, tools, anti-eagerness phrases, calibration table, output contract")
    sys.exit(0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run, confirm fail**

```bash
python3 tests/phase-3/implementer_structure_test.py; echo "exit: $?"
```

Expected: fail (`FAIL setup: ... does not exist`); exit 1.

- [ ] **Step 3: Create the implementer-strict agent**

Create `agentic-dev/agents/implementer-strict.md`:
````markdown
---
name: implementer-strict
description: Implements an approved agentic-dev spec inside a dedicated git worktree. Follows TDD discipline strictly. Halts on ambiguity rather than guessing. Never commits to main; never pushes. Produces a structured completion manifest.
tools: Read, Write, Edit, Glob, Grep, Bash
---

You are the agentic-dev strict implementer. You take an approved spec and write code that satisfies it, in a dedicated git worktree. You operate under heavy discipline — your job is to be honest, scoped, and methodical, not fast.

## How you are invoked

You are dispatched by `/agentic-dev:_run-implementer` (or, in P3, by the controller for testing). Your working directory is the worktree path (something like `.worktrees/goal-<id>/`). The kickoff package at `.agentic-kickoff.json` (in the worktree root) contains:

```
{
  "goal_id": "<YYYY-MM-DD-slug>",
  "spec_path": "<absolute path to the spec file>",
  "baseline_ref": "<git SHA at the start of work>",
  "budget": {
    "wall_clock_minutes_per_goal": <int>,
    "diff_lines_per_goal": <int>,
    "files_touched_per_goal": <int>
  },
  "sensitive_paths": ["..."],
  "project_commands": {
    "test": "...",
    "lint": "...",
    "typecheck": null | "...",
    "build": null | "..."
  },
  "worktree_path": "<absolute path>"
}
```

## What to do first

1. Read `.agentic-kickoff.json` in your CWD.
2. Read the spec file at `kickoff.spec_path` (absolute path).
3. Verify the spec has `approved: true` in its frontmatter. If not, halt immediately — your kickoff is broken.
4. Extract from the spec: "Files in scope", "Scope — In", "Architectural decisions" (answered), "Test strategy", "Completion criteria".
5. Plan the test cases you will write. Plan the implementation. Keep this internal — do not write a plan file in the worktree.

## Calibration table

For each situation, behave as specified. **You may not improvise outside this table.**

| Situation | Behavior |
|---|---|
| "Files in scope" is missing/empty | Halt with `clarifying_question`. Refuse to start. |
| File you want to touch is OUTSIDE "Files in scope" | Halt with `clarifying_question` asking for scope amendment. **Never silently expand scope.** This is load-bearing. |
| Spec doesn't specify what behavior X should be (e.g., what an API returns, what error code on edge case) | Halt with `clarifying_question`. **Do not guess** at expected outputs. |
| You need a new dependency/library/tool the spec doesn't mention | Halt with `clarifying_question`. Do not add dependencies. |
| You're approaching budget (80%+ of diff_lines_per_goal or files_touched_per_goal) | Halt at next clean commit with `status: blocked-on-budget` + `clarifying_question` asking whether to continue, descope, or escalate. |
| You're approaching wall-clock budget | Halt at the next clean commit boundary with `status: interrupted`. |
| A test FAILS that you just wrote (TDD red phase) | Expected. Continue to implementation. |
| A test FAILS that previously passed (pre-existing test broke from your change) | INVESTIGATE before continuing. If your change broke it, fix the issue. If the failure looks pre-existing, do a forensic check (run on baseline_ref to confirm). Note in manifest if it's pre-existing. |
| A test fails for ambiguous reasons | Note in manifest with `deferrals` item; halt or descope as appropriate; do not paper over. |
| You complete a logical unit | Run `kickoff.project_commands.test` (extract from kickoff). If pass, commit in the worktree with subject `[<goal_id>] <one-line summary>`. Do NOT commit to main; you're in a worktree so `git commit` operates on the worktree's HEAD, which is the intended behavior. |
| You finish all in-scope work AND all tests pass AND lint/typecheck pass | Write the final manifest with `status: complete`. |

## Forbidden actions

You MUST NOT:
- Edit any file outside the worktree path from kickoff.
- Commit to main branch. (You're in a worktree; `git commit` is safe because it operates on the worktree's branch.)
- Push to remote. **Ever.**
- Modify `.claude/agentic/queue.yaml`, `state.json`, or any other orchestrator state.
- Edit the spec file. The spec is read-only to you. If you think the spec is wrong, record a `spec_change_requests` entry in the manifest.
- Run another subagent (no nested Agent dispatch).
- Add new dependencies without an explicit spec entry permitting them.
- Mark the goal "done" — that's the reviewer's job in P5.

## TDD discipline

For every behavior you implement:

1. Identify the test that proves the behavior works.
2. Write the test FIRST. Save the file.
3. Run the project test command. The new test should fail (red phase).
4. Write minimal implementation to make the test pass.
5. Run again. Tests should pass (green phase).
6. Run lint/typecheck if available.
7. Commit in the worktree with subject `[<goal_id>] <summary>`.

If you cannot follow TDD for a specific change (e.g., refactoring), say so in the manifest's `deferrals` array with `item: <change>` and `reason: TDD not applicable for refactor`. Do not silently skip the discipline.

## Output contract

When you are done — whether successful, blocked, or interrupted — output your manifest as a single JSON object. Use the `Bash` tool to write it to stdout via `cat`, or simply output it as your final response. The invoking skill captures your response and writes it to `.claude/agentic/manifests/<goal_id>.json` after validating against `manifest.schema.json`.

Your output MUST be:
- A single JSON object
- No preamble, no commentary, no code fences around the JSON
- All fields per `manifest.schema.json` (the skill validates)
- `status` reflects your actual end state: `complete`, `blocked-on-clarification`, `blocked-on-budget`, `interrupted`, or — if your work itself is broken — leave the skill to mark it `implementer-output-malformed`

## Manifest fields you populate

- `goal_id`, `spec_path`, `worktree_path`, `baseline_ref` — copy from kickoff
- `head_ref` — the git SHA at the end of your work: run `git rev-parse HEAD` in the worktree
- `started_at` — your wall-clock UTC ISO 8601 at the moment of dispatch (use `date -u +"%Y-%m-%dT%H:%M:%SZ"`)
- `completed_at` — wall-clock when you finish (or null if blocked)
- `diff_stats` — `git diff --stat baseline_ref..HEAD` (parse the output)
- `tests` — counts from the LAST test run + path to the log
- `self_check` — lint and typecheck status (`clean`, `failures`, `not-run`, `n/a`)
- `scope_check.in_spec_files` — files in scope per the spec
- `scope_check.out_of_spec_files` — files YOU touched that were NOT in scope (should be empty; if not, this is a discipline failure)
- `adrs_filed` — any ADRs you wrote (paths)
- `spec_change_requests` — if you think the spec is wrong, log it here
- `deferrals` — items you didn't do and why
- `clarifying_questions_asked` — every question you had: include `question`, `resolved_by` (`spec_text`, `escalated`, or `pending`), and `answer` if resolved
- `artifacts` — any logs/screenshots/etc. you generated
- `commits` — list of `{sha, subject}` for every commit you made in the worktree

## Reminders

- The spec is your contract. Re-read it whenever you're tempted to do something not explicitly in scope.
- "I assumed X, hope that's right" is not allowed. Ask via clarifying_question.
- Test failures are facts, not opinions — record them honestly.
- Out-of-scope file edits are a discipline failure. P4's deterministic gates will catch this, but you should catch yourself first.
- You don't decide if the work is "done" — that's the reviewer's job.
````

- [ ] **Step 4: Run structural test; confirm pass**

```bash
python3 tests/phase-3/implementer_structure_test.py; echo "exit: $?"
```

Expected: 1 PASS line; exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/agents/implementer-strict.md tests/phase-3/implementer_structure_test.py
git commit -m "feat(phase-3): implementer-strict subagent + structural test

The implementer is Role 3 of the three-role pattern. Operates in worktree
only; never touches main; never pushes; halts on ambiguity rather than
guessing; produces a structured manifest.

Key anti-eagerness rules in the calibration table:
- Out-of-scope file edits → halt + clarifying_question
- Missing spec details → halt + clarifying_question
- Unspecified dependencies → halt + clarifying_question
- Budget approach → halt at next clean commit
- TDD discipline (test-first → red → green → commit)
- Honest test reporting (failed tests in manifest.tests.failed)
- Pre-existing failures forensically checked, not papered over

Test is purely structural (parses the agent file, asserts frontmatter
+ tools list + required phrases + calibration concepts + output contract
mention). Zero claude -p invocations.

Phase 3 task 3/6."
```

---

## Task 4: `/agentic-dev:_run-implementer` skill + structural test

**Files:**
- Create: `agentic-dev/skills/_run-implementer/SKILL.md`
- Create: `tests/phase-3/run_implementer_skill_structure_test.py`

- [ ] **Step 1: Write the structural test**

Create `tests/phase-3/run_implementer_skill_structure_test.py`:
```python
"""Verify _run-implementer/SKILL.md has required structure."""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-implementer" / "SKILL.md"


def main():
    failures = []
    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)
    text = SKILL.read_text()

    # Frontmatter
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener")
    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter unparseable")
    else:
        if not re.search(r"^description:", fm_match.group(1), re.MULTILINE):
            failures.append("frontmatter missing description")

    # Required steps / concepts
    required_phrases = [
        "$ARGUMENTS",
        "spec path",
        "approved",
        "worktree-init",
        "kickoff",
        "implementer-strict",
        "Agent tool",
        "manifest",
        "manifest.schema.json",
        "diff-envelope",
        "validate",
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Pre-checks for unapproved spec
    if "approved: false" not in text.lower() and "not approved" not in text.lower():
        failures.append("no pre-check for unapproved spec")

    # Error path documented
    if "malformed" not in text.lower() and "invalid manifest" not in text.lower():
        failures.append("no error path for invalid manifest")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS _run-implementer/SKILL.md has required structure and references")
    sys.exit(0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run, confirm fail**

```bash
python3 tests/phase-3/run_implementer_skill_structure_test.py; echo "exit: $?"
```

Expected: fail; exit 1.

- [ ] **Step 3: Create the skill**

Create `agentic-dev/skills/_run-implementer/SKILL.md`:
````markdown
---
description: Internal lifecycle skill (orchestrator-invoked). Sets up a worktree for an approved spec, dispatches implementer-strict subagent, captures the structured manifest, generates a diff envelope. Does NOT decide if work is "done" — that's reviewer's job in P5.
---

# /agentic-dev:_run-implementer

You are the lifecycle skill that runs one implementer pass for one approved spec. You are invoked explicitly (in P3) for testing, or by the orchestrator (P6+) as part of the autonomous loop.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the path to an approved spec file: `.claude/agentic/specs/<goal-id>.md`. If empty, print: `agentic-dev: /agentic-dev:_run-implementer requires a spec file path. Example: /agentic-dev:_run-implementer .claude/agentic/specs/2026-05-21-x.md` and exit.

## Pre-checks

1. Verify the spec file exists.
2. Verify the spec path matches `.claude/agentic/specs/*.md`.
3. Verify `approved: true` in the spec frontmatter. If `approved: false` or absent, refuse with `agentic-dev: spec not approved; cannot run implementer`.
4. Run `agentic-dev/bin/validate-spec.sh <spec-path>` to ensure mechanical correctness. If it exits non-zero, surface the validator's output and exit — do not proceed with a broken spec.

## Initialize the worktree

Extract the `goal_id` from the spec's filename (`.claude/agentic/specs/<goal-id>.md`).

Run `agentic-dev/bin/worktree-init.sh <goal-id>` via the Bash tool. Capture stdout — this is the absolute path to the new worktree. If the command exits non-zero, surface the error and exit.

## Dispatch the implementer

Use the Agent tool with `subagent_type: implementer-strict`. Pass a prompt that instructs the subagent to:

1. Change working directory to the worktree path (via Bash).
2. Read `.agentic-kickoff.json` in that working directory.
3. Begin implementation per the spec.
4. Output its final manifest as a JSON object (no preamble, no fences).

Example dispatch prompt:

```
You are dispatched as implementer-strict for goal <goal_id>.

Worktree path (cd here first): <absolute worktree path>
Kickoff package: <absolute worktree path>/.agentic-kickoff.json
Spec path: <absolute spec path>

Per your calibration table and output contract:
- Read the kickoff and spec
- Plan tests, write tests first (TDD red), implement (green), commit in worktree
- Halt on ambiguity with clarifying_questions; never guess
- Out_of_spec_files must stay empty — that's a discipline failure
- When done (or blocked or interrupted), output your manifest as a single JSON
  object. No preamble. No code fences. Just JSON.
```

## Capture the manifest

The implementer's response should be a single JSON object. Parse it:

1. Use Python (Bash + heredoc) to parse the response as JSON. If parsing fails, write a stub manifest with `status: implementer-output-malformed` and log the raw response to `.claude/agentic/validation-log.txt`.

2. Validate the parsed manifest against `agentic-dev/schemas/manifest.schema.json` (use Python + jsonschema). If validation fails, save the malformed manifest to `.claude/agentic/manifests/<goal-id>.raw.json` and write a fallback manifest with `status: implementer-output-malformed`.

3. If validation passes, write the manifest to `.claude/agentic/manifests/<goal-id>.json` using the Write tool.

## Generate the diff envelope

After the manifest is written, generate the structured diff:

1. Read the manifest's `baseline_ref` and `head_ref`.
2. If `head_ref` is null (implementer halted before committing): skip diff envelope generation; note in stdout.
3. Otherwise:
   - Use Bash to run `git -C <worktree_path> diff --stat <baseline_ref> <head_ref>` (and full `git diff` for the raw patch).
   - Build the diff-envelope JSON per `agentic-dev/schemas/diff-envelope.schema.json`.
   - Validate against the schema.
   - Write to `.claude/agentic/diffs/<goal-id>.json`.

## Output

Print a structured summary:

```
agentic-dev: implementer run complete

  goal: <goal_id>
  status: <manifest.status>
  worktree: <worktree_path>
  manifest: .claude/agentic/manifests/<goal_id>.json
  diff envelope: .claude/agentic/diffs/<goal_id>.json (or "skipped - no commits")

  diff stats: <files_touched> files / +<lines_added> -<lines_removed>
  tests: <ran> ran / <passed> passed / <failed> failed / <skipped> skipped
  lint: <lint>  typecheck: <typecheck>

  clarifying questions: <count>
  spec change requests: <count>
  deferrals: <count>
  out-of-spec files: <count>  <- should be 0; non-zero is a discipline failure

Next:
  - (P5) reviewer checks the manifest + diff envelope
  - (P6) orchestrator decides whether to advance, escalate, or halt
```

## Do NOT

- Do NOT clean up the worktree. Successful goals are cleaned by the orchestrator (P6) only after the reviewer (P5) approves. Halted goals are preserved for forensics.
- Do NOT mark the goal "complete" in the queue. That's the orchestrator's job after reviewer approval.
- Do NOT edit the spec file.
- Do NOT push anything.
- Do NOT call another skill (no nested skill invocation).
````

- [ ] **Step 4: Run structural test; confirm pass**

```bash
python3 tests/phase-3/run_implementer_skill_structure_test.py; echo "exit: $?"
```

Expected: 1 PASS line; exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/skills/_run-implementer/SKILL.md tests/phase-3/run_implementer_skill_structure_test.py
git commit -m "feat(phase-3): /agentic-dev:_run-implementer skill + structural test

Lifecycle skill (orchestrator-invoked; user-invocable for testing):
- Pre-checks: spec exists, is approved, deterministic validator passes
- worktree-init.sh creates .worktrees/goal-<id>/
- Dispatches implementer-strict subagent with cwd=worktree
- Captures manifest from subagent response; validates against
  manifest.schema.json
- Generates structured diff envelope via git diff (validated against
  diff-envelope.schema.json)
- Writes manifest + diff envelope to .claude/agentic/{manifests,diffs}/

Error paths: malformed manifest -> raw saved to <goal-id>.raw.json
plus a stub with status: implementer-output-malformed; logs to
validation-log.txt.

Structural test (no Claude) verifies SKILL.md has frontmatter +
required references to worktree-init, implementer-strict, manifest
schema, diff-envelope schema, error path.

Phase 3 task 4/6."
```

---

## Task 5: Phase 3 run_all aggregator + DEFERRED.md update

**Files:**
- Create: `tests/phase-3/run_all.sh`
- Modify: `DEFERRED.md`

- [ ] **Step 1: Create run_all aggregator**

Create `tests/phase-3/run_all.sh`:
```bash
#!/usr/bin/env bash
# Phase 3 test aggregator. Per docs/superpowers/test-cost-policy.md,
# all P3 tests are deterministic (no claude -p). Zero API cost.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== queue_schema_v02_test ==="
python3 "$DIR/queue_schema_v02_test.py"

echo
echo "=== manifest_schema_test ==="
python3 "$DIR/manifest_schema_test.py"

echo
echo "=== diff_envelope_schema_test ==="
python3 "$DIR/diff_envelope_schema_test.py"

echo
echo "=== migration_test ==="
bash "$DIR/migration_test.sh"

echo
echo "=== worktree_init_test ==="
bash "$DIR/worktree_init_test.sh"

echo
echo "=== worktree_cleanup_test ==="
bash "$DIR/worktree_cleanup_test.sh"

echo
echo "=== implementer_structure_test ==="
python3 "$DIR/implementer_structure_test.py"

echo
echo "=== run_implementer_skill_structure_test ==="
python3 "$DIR/run_implementer_skill_structure_test.py"

echo
echo "All Phase 3 tests passed (deterministic; no claude -p)."
```

Make executable.

- [ ] **Step 2: Run the full P3 suite**

```bash
bash tests/phase-3/run_all.sh
```

Expected: each section passes; final "All Phase 3 tests passed" + exit 0.

- [ ] **Step 3: Update DEFERRED.md — close P1-DEF-001**

In `DEFERRED.md`, find the `### P1-DEF-001 — Queue goal schema extension strategy` entry. After the existing **Target:** line, add:

```markdown
**Status:** ✅ CLOSED in Phase 3 (commit produced by T1 of P3 plan) — user-chosen path was "bump schema_version + add fields explicitly". queue.schema.json bumped to v0.2 with 8 new optional goal-item fields (started_at, completed_at, halted_at, baseline_ref, head_ref, worktree_path, manifest_path, budget_overrides). additionalProperties:false preserved on goal items.
```

- [ ] **Step 4: Commit**

```bash
git add tests/phase-3/run_all.sh DEFERRED.md
git commit -m "test(phase-3): run_all aggregator + close P1-DEF-001 in DEFERRED.md

- tests/phase-3/run_all.sh runs all 8 deterministic Phase 3 tests in
  order. Zero claude -p invocations; zero API cost.
- DEFERRED.md: marks P1-DEF-001 as CLOSED with reference to the P3-T1
  resolution.

Phase 3 task 5/6."
```

---

## Task 6: README + CHANGELOG + plugin version bump + smoke verification

**Files:**
- Modify: `agentic-dev/.claude-plugin/plugin.json` (version bump)
- Modify: `agentic-dev/README.md`
- Modify: `agentic-dev/CHANGELOG.md`

- [ ] **Step 1: Bump plugin version**

In `agentic-dev/.claude-plugin/plugin.json`, change `"version": "0.2.0"` to `"version": "0.3.0"`.

- [ ] **Step 2: Update README**

In `agentic-dev/README.md`:

Update the intro paragraph from "This is **v0.2** —..." to:
```markdown
This is **v0.3** — the plugin scaffold + spec-drafting layer + the implementer subagent with worktree-per-goal isolation. Approved specs can now be turned into committed code in a worktree via the internal `/agentic-dev:_run-implementer` skill. The reviewer (P5) and autonomous orchestrator (P6) ship in subsequent phases.
```

Add a v0.3 subsection under "## Skills shipped":
```markdown
### v0.3
- `/agentic-dev:_run-implementer <spec-path>` — internal lifecycle skill. Creates a worktree, dispatches the implementer-strict subagent against an approved spec, captures the structured manifest + diff envelope. Not for direct human invocation in the typical flow — used by the orchestrator (P6) or by tests.
```

- [ ] **Step 3: Update CHANGELOG**

Insert at the top of `agentic-dev/CHANGELOG.md` (after the title block, before `## [0.2.0]`):

```markdown
## [0.3.0] — 2026-05-21

Implementer layer ships. An approved spec can be turned into committed code in a dedicated worktree via the new internal lifecycle skill. Closing the loop (reviewer + orchestrator + queue) lands in P5–P6.

### Added
- `agents/implementer-strict.md` — implementer subagent with anti-eagerness calibration. Operates only in worktree; halts on ambiguity; honest test reporting; never commits to main; never pushes.
- `skills/_run-implementer/SKILL.md` — internal lifecycle skill (orchestrator-invoked). Creates worktree, dispatches implementer, captures manifest + diff envelope.
- `bin/worktree-init.sh` — creates `.worktrees/goal-<id>/` from current HEAD and writes the kickoff package.
- `bin/worktree-cleanup.sh` — removes a worktree (post-success only; halted worktrees preserved for forensics).
- `bin/migrate-v0.1-to-v0.2.sh` — one-shot idempotent migration for existing queue.yaml.
- `schemas/manifest.schema.json` — completion manifest schema.
- `schemas/diff-envelope.schema.json` — structured git-diff schema (consumed by P5 reviewer).
- `schemas/queue.schema.json` — bumped to v0.2 with eight new optional goal-item fields.
- `tests/phase-3/` — 8 deterministic tests covering schemas, migration, worktree management, and structural verification of the implementer + lifecycle skill. Zero `claude -p` invocations.

### Resolved
- P1-DEF-001 (queue goal schema extension strategy) — user chose explicit-fields-with-version-bump.

### Notes
- The implementer is a SUBAGENT, not user-invocable as a skill. The lifecycle skill `_run-implementer` is the only user-visible entry, prefixed with `_` to signal internal use.
- v0.3 does not yet check the implementer's output (that's P4's deterministic gates and P5's reviewer). Goals "complete" per the manifest's `status: complete` are accepted at face value in v0.3; this changes in v0.4+.
- Test cost policy (docs/superpowers/test-cost-policy.md) is now in effect for all future phases. P3 burned <$2 in API credits during development.
```

- [ ] **Step 4: Final P3 verification**

Run the full P3 suite:
```bash
bash tests/phase-3/run_all.sh
echo "p3 exit: $?"
```

Run all earlier phases to confirm no regression:
```bash
bash tests/phase-1/run_all.sh
echo "p1 exit: $?"
bash tests/phase-2/run_all.sh
echo "p2 exit: $?"
```

All must exit 0.

- [ ] **Step 5: Commit + P3 closer**

```bash
git add agentic-dev/.claude-plugin/plugin.json agentic-dev/README.md agentic-dev/CHANGELOG.md
git commit -m "docs(phase-3): v0.3.0 — plugin version bump + README + CHANGELOG

- plugin.json version: 0.2.0 -> 0.3.0
- README intro updated; v0.3 skills section added
- CHANGELOG records v0.3.0 with all P3 additions and P1-DEF-001 closure
- Test cost policy (docs/superpowers/test-cost-policy.md) is in
  effect: P3 burned <\$2 in API credits during development vs ~\$30+
  for P2.

Phase 3 task 6/6 — Phase 3 complete."
```

---

## Phase 3 Completion Checklist

- [ ] `bash tests/phase-3/run_all.sh` exits 0
- [ ] `bash tests/phase-1/run_all.sh` and `bash tests/phase-2/run_all.sh` still pass (no regression)
- [ ] `agentic-dev/.claude-plugin/plugin.json` version is `"0.3.0"`
- [ ] `agentic-dev/CHANGELOG.md` records v0.3.0
- [ ] `DEFERRED.md` marks P1-DEF-001 as CLOSED
- [ ] All 6 task commits on the branch
- [ ] Zero `claude -p` invocations made during P3 dev (cost policy compliance)
