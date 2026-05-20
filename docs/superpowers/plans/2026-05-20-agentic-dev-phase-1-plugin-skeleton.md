# Phase 1 — agentic-dev Plugin Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.1 of the `agentic-dev` Claude plugin: an installable scaffold with two working skills (`/agentic-dev:init` to bootstrap a host project's `.claude/agentic/` state tree, and `/agentic-dev:status` to inspect that state), plus the schemas and tests that the later phases will build on.

**Architecture:** A standalone Claude plugin directory (`agentic-dev/`) containing a manifest, two SKILL.md skill files, JSON Schemas for the per-project state files (`state.json`, `queue.yaml`, `config.yaml`), and a `marketplace.json` at the repo root that lets `agentic-dev` be installed via `/plugin marketplace add`. End-to-end testing is done with bash test scripts that drive `claude --plugin-dir ./agentic-dev` programmatically against throwaway host projects. No subagents, no hooks, no notification helpers in this phase — those land in P2–P5.

**Tech Stack:** Markdown (skills), JSON (manifest, schemas), YAML (per-project state files), Bash (test scripts), Python stdlib + `jsonschema` (schema validation in tests), `claude --plugin-dir` (local plugin testing).

**Reference spec:** `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md`, especially §5 (execution substrate), §14.1 (plugin layout), §14.2 (per-project layout), §22 (build scope), §23 (distribution lifecycle).

---

## File Structure

Files created in Phase 1:

**Plugin source (everything under `agentic-dev/`):**
- `agentic-dev/.claude-plugin/plugin.json` — plugin manifest
- `agentic-dev/README.md` — install + init usage
- `agentic-dev/skills/init/SKILL.md` — bootstraps a host project
- `agentic-dev/skills/status/SKILL.md` — inspects state of current host project
- `agentic-dev/schemas/state.schema.json` — schema for `.claude/agentic/state.json`
- `agentic-dev/schemas/queue.schema.json` — schema for `.claude/agentic/queue.yaml`
- `agentic-dev/schemas/config.schema.json` — schema for `.claude/agentic/config.yaml`
- `agentic-dev/.gitkeep` files in empty directories that should be tracked

**Repo-root files:**
- `marketplace.json` — declares `agentic-dev` plugin for the marketplace

**Test infrastructure:**
- `tests/README.md` — how to run phase-1 tests
- `tests/phase-1/schema_test.py` — validates sample fixtures against JSON Schemas
- `tests/phase-1/init_test.sh` — runs the init skill end-to-end and asserts file structure
- `tests/phase-1/status_test.sh` — sets up known state and asserts status output
- `tests/phase-1/smoke_test.sh` — full init → status workflow
- `tests/phase-1/run_all.sh` — runs all phase-1 tests
- `tests/phase-1/fixtures/sample-state.json`
- `tests/phase-1/fixtures/sample-queue.yaml`
- `tests/phase-1/fixtures/sample-config.yaml`

Each file has one clear responsibility. The plugin scaffold is intentionally minimal in P1 — no subagents, no hooks, no notification helpers — so the surface stays small and testable.

---

## Notes on testing strategy

The plugin's skills are markdown prompts that instruct Claude to do work. We can't unit-test the LLM's compliance with a prompt directly, so the test approach is:

- **Schemas** get strict unit tests via Python's `jsonschema` library against good and bad fixtures.
- **Skills** get end-to-end smoke tests via `claude --plugin-dir ./agentic-dev -p '<skill invocation>'` against throwaway directories, with bash assertions on the resulting file structure / stdout.
- The smoke tests use `claude -p` (headless mode). This counts as programmatic billing per Anthropic's policy — accept the test-time cost; it's our own dev/CI work.
- Production use of the plugin remains interactive (human-launched Claude Code sessions), preserving Path A's Max-interactive billing — see spec §5 and Appendix B.

---

## Task 1: Plugin scaffold (manifest + README + marketplace.json)

**Files:**
- Create: `agentic-dev/.claude-plugin/plugin.json`
- Create: `agentic-dev/README.md`
- Create: `marketplace.json`

- [ ] **Step 1: Create the plugin directory and manifest**

Run:
```bash
mkdir -p agentic-dev/.claude-plugin
```

Create `agentic-dev/.claude-plugin/plugin.json` with:
```json
{
  "name": "agentic-dev",
  "description": "Three-role agentic development pattern: autonomous overnight loop with hardened reviewer and human-in-the-loop escalation. See repo README for design.",
  "version": "0.1.0",
  "author": {
    "name": "Pankaj Bhasin"
  },
  "homepage": "https://github.com/Pankaj-Bhasin/agenticDev",
  "license": "MIT"
}
```

- [ ] **Step 2: Create plugin-level README**

Create `agentic-dev/README.md` with:
````markdown
# agentic-dev

A Claude Code plugin that automates the three-role development pattern: a hardened agentic loop that implements, reviews, and escalates to the human only when quality requires it.

This is **v0.1** — only the plugin skeleton and the `/agentic-dev:init` and `/agentic-dev:status` skills are shipped. The full agentic loop ships in subsequent phases (P2–P8).

See `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` in the source repository for the full design.

## Install

From a Claude Code session:

```
/plugin marketplace add Pankaj-Bhasin/agenticDev
/plugin install agentic-dev
```

## Bootstrap a host project

In any project where you want to use the agentic loop:

```
/agentic-dev:init
```

This creates a `.claude/agentic/` directory with the state tree, prompts for project-specific configuration (test/lint commands, Telegram chat id, budget defaults), and writes a starter `config.yaml`.

## Inspect current state

```
/agentic-dev:status
```

Reports the current queue, circuit-breaker state, and recent activity.

## Skills shipped in v0.1

- `/agentic-dev:init` — bootstrap `.claude/agentic/` in the current project
- `/agentic-dev:status` — show current state

## What's coming next

See repo issues / phase plans for P2 onward: spec drafter, implementer, hardened reviewer, deterministic gates, overnight queue, escalation.
````

- [ ] **Step 3: Create the repo-root marketplace.json**

Create `/Users/pankajbhasin/Pankaj/gitdev/agenticDev/marketplace.json` with:
```json
{
  "name": "agentic-dev-marketplace",
  "description": "Marketplace hosting the agentic-dev plugin",
  "plugins": [
    {
      "name": "agentic-dev",
      "source": "./agentic-dev",
      "description": "Three-role agentic development pattern with hardened reviewer and human-in-the-loop escalation"
    }
  ]
}
```

- [ ] **Step 4: Validate the plugin loads without error**

Run:
```bash
claude --plugin-dir ./agentic-dev --print "echo plugin-loaded-ok" 2>&1 | tail -5
```

Expected: no errors about plugin manifest; output contains `plugin-loaded-ok` or similar evidence Claude Code started cleanly. If the command emits `error: invalid manifest` or similar, fix the manifest before continuing.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/.claude-plugin/plugin.json agentic-dev/README.md marketplace.json
git commit -m "$(cat <<'EOF'
feat(plugin): add agentic-dev plugin scaffold

Empty plugin manifest, README, and marketplace.json. Plugin loads cleanly
via --plugin-dir but ships no skills yet.

Phase 1 task 1/6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: JSON Schemas for state, queue, and config

**Files:**
- Create: `agentic-dev/schemas/state.schema.json`
- Create: `agentic-dev/schemas/queue.schema.json`
- Create: `agentic-dev/schemas/config.schema.json`
- Create: `tests/phase-1/fixtures/sample-state.json`
- Create: `tests/phase-1/fixtures/sample-queue.yaml`
- Create: `tests/phase-1/fixtures/sample-config.yaml`
- Create: `tests/phase-1/schema_test.py`

- [ ] **Step 1: Set up test directory and write the failing schema test**

Run:
```bash
mkdir -p tests/phase-1/fixtures agentic-dev/schemas
```

Create `tests/phase-1/schema_test.py` with:
```python
"""Validate sample fixtures against the plugin's JSON Schemas."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
except ImportError:
    print("ERROR: install dependencies first: pip install pyyaml jsonschema", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = REPO_ROOT / "agentic-dev" / "schemas"
FIXTURE_DIR = REPO_ROOT / "tests" / "phase-1" / "fixtures"


def load_json(path: Path):
    with path.open() as f:
        return json.load(f)


def load_yaml(path: Path):
    with path.open() as f:
        return yaml.safe_load(f)


def validate(name: str, schema_path: Path, fixture_path: Path, loader) -> bool:
    if not schema_path.exists():
        print(f"FAIL {name}: schema not found at {schema_path}")
        return False
    if not fixture_path.exists():
        print(f"FAIL {name}: fixture not found at {fixture_path}")
        return False
    schema = load_json(schema_path)
    data = loader(fixture_path)
    try:
        jsonschema.validate(instance=data, schema=schema)
    except jsonschema.ValidationError as e:
        print(f"FAIL {name}: {e.message}")
        return False
    print(f"PASS {name}")
    return True


def main():
    results = [
        validate(
            "state",
            SCHEMA_DIR / "state.schema.json",
            FIXTURE_DIR / "sample-state.json",
            load_json,
        ),
        validate(
            "queue",
            SCHEMA_DIR / "queue.schema.json",
            FIXTURE_DIR / "sample-queue.yaml",
            load_yaml,
        ),
        validate(
            "config",
            SCHEMA_DIR / "config.schema.json",
            FIXTURE_DIR / "sample-config.yaml",
            load_yaml,
        ),
    ]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the test, confirm it fails (no schemas yet)**

Run:
```bash
python3 -m pip install --quiet pyyaml jsonschema && python3 tests/phase-1/schema_test.py
```

Expected: output shows `FAIL state: schema not found at .../state.schema.json` and similar for queue and config. Exit code 1.

- [ ] **Step 3: Create state.schema.json**

Create `agentic-dev/schemas/state.schema.json` with:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic State",
  "description": "Orchestrator state and circuit breaker for a host project.",
  "type": "object",
  "required": ["schema_version", "circuit_breaker", "current_goal", "last_updated"],
  "additionalProperties": false,
  "properties": {
    "schema_version": {
      "type": "string",
      "const": "0.1"
    },
    "circuit_breaker": {
      "type": "object",
      "required": ["state"],
      "additionalProperties": false,
      "properties": {
        "state": {
          "type": "string",
          "enum": ["running", "halted", "completed", "idle"]
        },
        "halted_reason": {
          "type": ["string", "null"]
        },
        "halted_at": {
          "type": ["string", "null"],
          "format": "date-time"
        },
        "halted_goal_id": {
          "type": ["string", "null"]
        }
      }
    },
    "current_goal": {
      "type": ["string", "null"],
      "description": "Goal id currently executing, or null if idle/halted"
    },
    "last_updated": {
      "type": "string",
      "format": "date-time"
    }
  }
}
```

- [ ] **Step 4: Create sample-state.json fixture**

Create `tests/phase-1/fixtures/sample-state.json` with:
```json
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "idle",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": null,
  "last_updated": "2026-05-20T12:00:00Z"
}
```

- [ ] **Step 5: Create queue.schema.json**

Create `agentic-dev/schemas/queue.schema.json` with:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Goal Queue",
  "description": "Ordered list of goals to be processed by the orchestrator.",
  "type": "object",
  "required": ["schema_version", "goals"],
  "additionalProperties": false,
  "properties": {
    "schema_version": {
      "type": "string",
      "const": "0.1"
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
          "spec_path": {
            "type": ["string", "null"]
          },
          "intent_path": {
            "type": ["string", "null"]
          },
          "status": {
            "type": "string",
            "enum": ["intent_only", "drafted", "approved", "running", "completed", "halted", "abandoned"]
          },
          "added_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      }
    }
  }
}
```

- [ ] **Step 6: Create sample-queue.yaml fixture**

Create `tests/phase-1/fixtures/sample-queue.yaml` with:
```yaml
schema_version: "0.1"
goals: []
```

- [ ] **Step 7: Create config.schema.json**

Create `agentic-dev/schemas/config.schema.json` with:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Per-Project Config",
  "description": "Project-specific configuration written by /agentic-dev:init.",
  "type": "object",
  "required": ["schema_version", "project", "commands", "budgets", "sensitive_paths"],
  "additionalProperties": false,
  "properties": {
    "schema_version": { "type": "string", "const": "0.1" },
    "project": {
      "type": "object",
      "required": ["name"],
      "additionalProperties": false,
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "primary_language": { "type": ["string", "null"] }
      }
    },
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
    },
    "budgets": {
      "type": "object",
      "required": ["wall_clock_minutes_per_goal", "diff_lines_per_goal", "files_touched_per_goal"],
      "additionalProperties": false,
      "properties": {
        "wall_clock_minutes_per_goal": { "type": "integer", "minimum": 1 },
        "diff_lines_per_goal": { "type": "integer", "minimum": 1 },
        "files_touched_per_goal": { "type": "integer", "minimum": 1 }
      }
    },
    "sensitive_paths": {
      "type": "array",
      "items": { "type": "string", "minLength": 1 },
      "description": "Glob patterns that trip immediate escalation when touched"
    },
    "telegram": {
      "type": ["object", "null"],
      "additionalProperties": false,
      "properties": {
        "chat_id": { "type": ["string", "integer"] }
      }
    },
    "push_policy": {
      "type": "string",
      "enum": ["hold", "auto"],
      "default": "hold"
    }
  }
}
```

- [ ] **Step 8: Create sample-config.yaml fixture**

Create `tests/phase-1/fixtures/sample-config.yaml` with:
```yaml
schema_version: "0.1"
project:
  name: example-host-project
  primary_language: python
commands:
  test: pytest -q
  lint: ruff check .
  typecheck: mypy .
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
telegram: null
push_policy: hold
```

- [ ] **Step 9: Run the test, confirm it passes**

Run:
```bash
python3 tests/phase-1/schema_test.py
```

Expected: three `PASS` lines (state, queue, config) and exit code 0.

- [ ] **Step 10: Add a negative test case (bad fixture should fail validation)**

Append to `tests/phase-1/schema_test.py` at the end of `main()` before `sys.exit(...)`, replacing the existing `sys.exit` line with:

```python
    bad_state = {
        "schema_version": "0.1",
        "circuit_breaker": {"state": "nonsense"},
        "current_goal": None,
        "last_updated": "2026-05-20T12:00:00Z",
    }
    schema = load_json(SCHEMA_DIR / "state.schema.json")
    try:
        jsonschema.validate(instance=bad_state, schema=schema)
        print("FAIL negative-state: bad fixture wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS negative-state")
        results.append(True)

    sys.exit(0 if all(results) else 1)
```

- [ ] **Step 11: Re-run; confirm four PASS lines**

Run:
```bash
python3 tests/phase-1/schema_test.py
```

Expected: `PASS state`, `PASS queue`, `PASS config`, `PASS negative-state`. Exit code 0.

- [ ] **Step 12: Commit**

```bash
git add agentic-dev/schemas tests/phase-1/schema_test.py tests/phase-1/fixtures
git commit -m "$(cat <<'EOF'
feat(schemas): add state/queue/config schemas with validation tests

JSON Schemas for the three per-project state files written by
/agentic-dev:init. Python schema_test validates good fixtures and
explicitly rejects a known-bad state.

Phase 1 task 2/6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `/agentic-dev:init` skill

**Files:**
- Create: `agentic-dev/skills/init/SKILL.md`
- Create: `tests/phase-1/init_test.sh`
- Create: `tests/phase-1/fixtures/init-input.yaml` (pre-canned answers for the test)

- [ ] **Step 1: Write the failing init test**

Create `tests/phase-1/init_test.sh` with:
```bash
#!/usr/bin/env bash
# End-to-end test of /agentic-dev:init in a throwaway directory.
# Drives Claude Code via --plugin-dir + headless -p with pre-canned config input.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
FIXTURE_INPUT="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-init-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Invoke the init skill with a pre-canned config path as $ARGUMENTS.
# The skill is expected to read the YAML at that path and use those values
# instead of prompting interactively.
claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null 2>&1 || true

# Assertions
ok=1
require() {
  if [[ ! -e "$1" ]]; then
    echo "FAIL missing: $1" >&2
    ok=0
  else
    echo "PASS exists: $1"
  fi
}

require .claude/agentic/state.json
require .claude/agentic/queue.yaml
require .claude/agentic/config.yaml
require .claude/agentic/checklist.yaml
require .claude/agentic/memory.yaml
require .claude/agentic/decisions.log
require .claude/agentic/intents
require .claude/agentic/specs
require .claude/agentic/manifests
require .claude/agentic/diffs
require .claude/agentic/artifacts
require .claude/agentic/escalations
require .claude/agentic/prompts

# Validate the written config against the schema
python3 - <<PY
import sys, json, yaml
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/config.schema.json").read_text())
data = yaml.safe_load(Path(".claude/agentic/config.yaml").read_text())
jsonschema.validate(instance=data, schema=schema)
print("PASS config.yaml validates against config.schema.json")
PY

# Validate state.json
python3 - <<PY
import sys, json
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/state.schema.json").read_text())
data = json.loads(Path(".claude/agentic/state.json").read_text())
jsonschema.validate(instance=data, schema=schema)
print("PASS state.json validates against state.schema.json")
PY

# Validate queue.yaml
python3 - <<PY
import sys, json, yaml
from pathlib import Path
import jsonschema

schema = json.loads(Path("$PLUGIN_DIR/schemas/queue.schema.json").read_text())
data = yaml.safe_load(Path(".claude/agentic/queue.yaml").read_text())
jsonschema.validate(instance=data, schema=schema)
print("PASS queue.yaml validates against queue.schema.json")
PY

[[ $ok -eq 1 ]] || exit 1
echo "init_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-1/init_test.sh
```

- [ ] **Step 2: Create the pre-canned init input fixture**

Create `tests/phase-1/fixtures/init-input.yaml` with:
```yaml
project:
  name: example-host-project
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
  - "migrations/**"
  - "schema/**"
  - "secrets/**"
  - "payments/**"
  - "infra/**"
telegram: null
push_policy: hold
```

- [ ] **Step 3: Run the test, confirm it fails (init skill not implemented yet)**

Run:
```bash
bash tests/phase-1/init_test.sh; echo "exit: $?"
```

Expected: `FAIL missing: .claude/agentic/state.json` and similar; exit code 1.

- [ ] **Step 4: Implement the init skill**

Create `agentic-dev/skills/init/SKILL.md` with:
````markdown
---
description: Bootstrap a host project with the .claude/agentic/ state tree, project config, and starter state/queue files. Idempotent — safe to re-run.
---

# /agentic-dev:init

You are bootstrapping the current working directory as a host project for the agentic-dev system.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` may be one of:

1. **Empty** — prompt the user interactively for each config value (see "Interactive prompts" below).
2. **A path to a YAML file** — read that file and use its values as the configuration. Do not prompt interactively. The YAML must conform to `agentic-dev/schemas/config.schema.json` (relative to the plugin install root). Use the values directly; do not invent or modify them.

The YAML mode is for testing and scripted onboarding; the interactive mode is for normal human use.

## Idempotence

Before doing anything, check whether `.claude/agentic/` already exists in the current working directory.

- If it does **not** exist: create the full structure as specified below.
- If it **does** exist: do not overwrite any existing files. Print a summary of what is already present and exit. Do not prompt for re-configuration unless the user explicitly asks.

## Required directory structure

Create the following under `.claude/agentic/` in the current working directory:

```
.claude/agentic/
├── state.json
├── queue.yaml
├── config.yaml
├── checklist.yaml
├── memory.yaml
├── decisions.log
├── intents/
├── specs/
├── manifests/
├── diffs/
├── artifacts/
├── escalations/
└── prompts/
```

Use the Bash tool with `mkdir -p` for directories. Use the Write tool for file contents.

For each empty directory listed above, create a `.gitkeep` file inside it so the directory survives git commits.

## File contents

### `state.json`

```json
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "idle",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": null,
  "last_updated": "<CURRENT ISO 8601 UTC TIMESTAMP>"
}
```

Replace `<CURRENT ISO 8601 UTC TIMESTAMP>` with the actual current UTC timestamp in `YYYY-MM-DDTHH:MM:SSZ` format. Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` via the Bash tool to obtain it.

### `queue.yaml`

```yaml
schema_version: "0.1"
goals: []
```

### `config.yaml`

Write the configuration values gathered from either the YAML input file or the interactive prompts. Schema is defined in `agentic-dev/schemas/config.schema.json`.

Required fields and their derivations:

- `schema_version`: `"0.1"` (literal)
- `project.name`: from input or prompt; default to basename of current working directory
- `project.primary_language`: from input or prompt; ask "What is the primary language of this project? (e.g., python, typescript, go, rust)"; may be null
- `commands.test`: from input or prompt; ask "What command runs the test suite? (e.g., `npm test`, `pytest -q`, `go test ./...`)"; required, non-empty
- `commands.lint`: from input or prompt; ask "What command runs the linter? (e.g., `npm run lint`, `ruff check .`, `golangci-lint run`)"; required, non-empty
- `commands.typecheck`: from input or prompt; ask "What command runs the typechecker? (Leave blank if N/A)"; may be null
- `commands.build`: from input or prompt; ask "What command builds the project? (Leave blank if N/A)"; may be null
- `budgets.wall_clock_minutes_per_goal`: default `90` unless overridden in input
- `budgets.diff_lines_per_goal`: default `800` unless overridden in input
- `budgets.files_touched_per_goal`: default `25` unless overridden in input
- `sensitive_paths`: default to `["auth/**", "migrations/**", "schema/**", "secrets/**", "payments/**", "infra/**"]` unless overridden in input
- `telegram`: default `null` unless overridden in input
- `push_policy`: default `"hold"` unless overridden in input

After writing, validate the file is well-formed YAML and contains all required keys before exiting.

### `checklist.yaml`

```yaml
# Reviewer adversarial-pattern hints. Append-only. Each entry is an incident-derived rule.
# Schema: list of { date, incident, rule, caught_by }
entries: []
```

### `memory.yaml`

```yaml
# Orchestrator behavioral memory. Append-only. Each entry is an observation + consequence.
# Schema: list of { date, observation, consequence }
entries: []
```

### `decisions.log`

Create an empty file with a single header line:
```
# Human-reset decisions log. Append-only. Each entry: ISO timestamp | decision | goal_id | notes
```

## Interactive prompts (when `$ARGUMENTS` is empty)

Use the AskUserQuestion tool for each value that does not have a sensible default. Group related questions where possible (e.g., all three commands in one AskUserQuestion call with multiple questions).

For `project.name`, use the current directory basename as the default; only ask if the user wants to override.

For `sensitive_paths`, do not prompt — use the defaults. Tell the user they can edit `.claude/agentic/config.yaml` later to add project-specific sensitive paths.

For `telegram`, do not prompt during init. Inform the user that Telegram setup is done later via a future skill (`/agentic-dev:configure-telegram`, not in v0.1).

## Output

After all files are written, print a structured summary:

```
agentic-dev: init complete
  state file:      .claude/agentic/state.json
  queue file:      .claude/agentic/queue.yaml
  config file:     .claude/agentic/config.yaml
  test command:    <commands.test>
  lint command:    <commands.lint>
  budgets:         <wall_clock>m / <diff_lines>lines / <files_touched>files per goal
  push policy:     <push_policy>
  sensitive paths: <count> patterns

Next steps:
  - Review .claude/agentic/config.yaml and adjust as needed
  - When ready to queue a goal, run /agentic-dev:intent (ships in P2)
  - To inspect state, run /agentic-dev:status
```

## Do NOT

- Do not overwrite existing files. Idempotence is load-bearing.
- Do not invent values that the user didn't provide and that don't have a documented default.
- Do not skip the state.json or queue.yaml schema-required fields.
- Do not modify `.gitignore`, `package.json`, or any other project file.
- Do not commit anything. The user commits.
````

- [ ] **Step 5: Run the test, confirm it passes**

Run:
```bash
bash tests/phase-1/init_test.sh; echo "exit: $?"
```

Expected: all `PASS` lines including the three schema validations; `init_test: OK`; exit code 0.

If it fails because the headless `claude -p` invocation can't pick up `$ARGUMENTS` exactly as written, inspect the failure and adjust either the test invocation or the SKILL.md prompt for handling arguments. Do not relax the assertions.

- [ ] **Step 6: Verify idempotence — re-run init on a project that already has `.claude/agentic/`**

Add to the bottom of `tests/phase-1/init_test.sh` (just before the final `echo "init_test: OK"`):

```bash

# --- Idempotence check ---
# Re-running init must not overwrite or duplicate files.
state_mtime_before=$(stat -f "%m" .claude/agentic/state.json 2>/dev/null || stat -c "%Y" .claude/agentic/state.json)
sleep 1
claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null 2>&1 || true
state_mtime_after=$(stat -f "%m" .claude/agentic/state.json 2>/dev/null || stat -c "%Y" .claude/agentic/state.json)

if [[ "$state_mtime_before" != "$state_mtime_after" ]]; then
  echo "FAIL idempotence: state.json was modified on re-run" >&2
  exit 1
fi
echo "PASS idempotence: state.json untouched on re-run"
```

- [ ] **Step 7: Re-run test; confirm idempotence assertion passes**

Run:
```bash
bash tests/phase-1/init_test.sh; echo "exit: $?"
```

Expected: all PASS lines including `PASS idempotence: state.json untouched on re-run`; exit code 0.

- [ ] **Step 8: Commit**

```bash
git add agentic-dev/skills/init tests/phase-1/init_test.sh tests/phase-1/fixtures/init-input.yaml
git commit -m "$(cat <<'EOF'
feat(skill): add /agentic-dev:init skill

Bootstraps a host project with .claude/agentic/ state tree, schemas-valid
state.json/queue.yaml/config.yaml, plus empty checklist/memory/decisions.
Supports both interactive prompts and YAML-driven config for tests.
Idempotent.

Phase 1 task 3/6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `/agentic-dev:status` skill

**Files:**
- Create: `agentic-dev/skills/status/SKILL.md`
- Create: `tests/phase-1/status_test.sh`

- [ ] **Step 1: Write the failing status test**

Create `tests/phase-1/status_test.sh` with:
```bash
#!/usr/bin/env bash
# End-to-end test of /agentic-dev:status against known state.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"

TMP_PROJECT="$(mktemp -d -t agentic-status-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"

# Set up known state directly (not via init — we want isolated testing of status).
mkdir -p .claude/agentic/intents .claude/agentic/specs
cat > .claude/agentic/state.json <<'JSON'
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "running",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": "2026-05-20-example-goal",
  "last_updated": "2026-05-20T15:30:00Z"
}
JSON

cat > .claude/agentic/queue.yaml <<'YAML'
schema_version: "0.1"
goals:
  - id: 2026-05-20-example-goal
    spec_path: .claude/agentic/specs/2026-05-20-example-goal.md
    intent_path: null
    status: running
    added_at: 2026-05-20T15:25:00Z
  - id: 2026-05-20-second-goal
    spec_path: .claude/agentic/specs/2026-05-20-second-goal.md
    intent_path: null
    status: approved
    added_at: 2026-05-20T15:26:00Z
  - id: 2026-05-20-third-intent
    spec_path: null
    intent_path: .claude/agentic/intents/2026-05-20-third-intent.md
    status: intent_only
    added_at: 2026-05-20T15:27:00Z
YAML

cat > .claude/agentic/config.yaml <<'YAML'
schema_version: "0.1"
project:
  name: example-host-project
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
YAML

# Run status and capture output
output=$(claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:status" 2>&1 || true)
echo "$output" > status_output.txt

ok=1
must_contain() {
  if ! grep -qE "$1" status_output.txt; then
    echo "FAIL missing-pattern: $1" >&2
    ok=0
  else
    echo "PASS contains: $1"
  fi
}

must_contain "circuit.?breaker.*running"
must_contain "current.?goal.*2026-05-20-example-goal"
must_contain "approved.*1"
must_contain "intent_only.*1"
must_contain "running.*1"
must_contain "example-host-project"

[[ $ok -eq 1 ]] || { echo "Captured output was:"; cat status_output.txt; exit 1; }
echo "status_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-1/status_test.sh
```

- [ ] **Step 2: Run the test, confirm it fails (status skill not implemented yet)**

Run:
```bash
bash tests/phase-1/status_test.sh; echo "exit: $?"
```

Expected: multiple `FAIL missing-pattern:` lines; exit code 1.

- [ ] **Step 3: Implement the status skill**

Create `agentic-dev/skills/status/SKILL.md` with:
````markdown
---
description: Report the current state of the agentic-dev system in the host project — circuit breaker, queue counts, current goal, configuration summary.
---

# /agentic-dev:status

You are reporting the state of the agentic-dev system in the current host project. Be terse, structured, factual. No prose narration. No claims beyond what the files say.

## Steps

1. Use the Read tool to read `.claude/agentic/state.json`. If the file does not exist, print a single line: `agentic-dev: not initialized (run /agentic-dev:init)` and exit.

2. Use the Read tool to read `.claude/agentic/queue.yaml`.

3. Use the Read tool to read `.claude/agentic/config.yaml`.

4. Compute queue counts by status. Group goals by their `status` field; for each status that has at least one goal, you will report it.

5. Print a structured status block:

```
agentic-dev: status

  project:           <config.project.name>
  language:          <config.project.primary_language or "unspecified">
  push policy:       <config.push_policy>

  circuit breaker:   <state.circuit_breaker.state>
  current goal:      <state.current_goal or "none">
  last updated:      <state.last_updated>

  queue:
    intent_only:     <count>
    drafted:         <count>
    approved:        <count>
    running:         <count>
    completed:       <count>
    halted:          <count>
    abandoned:       <count>

  test command:      <config.commands.test>
  lint command:      <config.commands.lint>
  typecheck:         <config.commands.typecheck or "n/a">
  build:             <config.commands.build or "n/a">

  budgets per goal:
    wall clock:      <config.budgets.wall_clock_minutes_per_goal>m
    diff lines:      <config.budgets.diff_lines_per_goal>
    files touched:   <config.budgets.files_touched_per_goal>
```

If the circuit breaker state is `halted`, append a halt block after the budgets section:

```

  HALTED:
    reason:          <state.circuit_breaker.halted_reason>
    at:              <state.circuit_breaker.halted_at>
    goal:            <state.circuit_breaker.halted_goal_id>
```

6. Skip any queue-status counts that are zero (only print non-zero ones). If the queue is entirely empty, print `    (queue is empty)` under the `queue:` heading instead of a list.

## Do NOT

- Do not modify any files. This skill is read-only.
- Do not infer state that isn't in the files. If `current_goal` is null, print "none" — don't guess.
- Do not run any commands. Just read files and format output.
- Do not invoke other skills or subagents.
````

- [ ] **Step 4: Run the test, confirm it passes**

Run:
```bash
bash tests/phase-1/status_test.sh; echo "exit: $?"
```

Expected: all `PASS contains:` lines and `status_test: OK`; exit code 0.

- [ ] **Step 5: Add a not-initialized case to the test**

Add to the bottom of `tests/phase-1/status_test.sh` just before `echo "status_test: OK"`:

```bash

# --- Not-initialized case ---
TMP_EMPTY="$(mktemp -d -t agentic-status-empty-XXXXXX)"
cd "$TMP_EMPTY"
empty_output=$(claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:status" 2>&1 || true)
if echo "$empty_output" | grep -q "not initialized"; then
  echo "PASS not-initialized message present"
else
  echo "FAIL not-initialized: expected 'not initialized' message; got:" >&2
  echo "$empty_output" >&2
  rm -rf "$TMP_EMPTY"
  exit 1
fi
rm -rf "$TMP_EMPTY"
```

- [ ] **Step 6: Re-run test; confirm not-initialized case passes**

Run:
```bash
bash tests/phase-1/status_test.sh; echo "exit: $?"
```

Expected: all PASS lines plus `PASS not-initialized message present`; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add agentic-dev/skills/status tests/phase-1/status_test.sh
git commit -m "$(cat <<'EOF'
feat(skill): add /agentic-dev:status skill

Reports circuit breaker, current goal, queue counts by status, and config
summary. Read-only — never modifies state. Handles the not-initialized
case with a single clear message.

Phase 1 task 4/6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: End-to-end smoke test and test runner

**Files:**
- Create: `tests/phase-1/smoke_test.sh`
- Create: `tests/phase-1/run_all.sh`
- Create: `tests/README.md`

- [ ] **Step 1: Create the smoke test (init followed by status, asserting consistency)**

Create `tests/phase-1/smoke_test.sh` with:
```bash
#!/usr/bin/env bash
# Full init → status workflow on a single throwaway project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
FIXTURE_INPUT="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-smoke-XXXXXX)"
trap 'rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Step 1: init
claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:init $FIXTURE_INPUT" >/dev/null 2>&1 || true

if [[ ! -f .claude/agentic/state.json ]]; then
  echo "FAIL smoke: init did not produce state.json" >&2
  exit 1
fi

# Step 2: status
output=$(claude --plugin-dir "$PLUGIN_DIR" -p "/agentic-dev:status" 2>&1 || true)

# Init creates an idle, empty queue. Status must reflect that.
if ! echo "$output" | grep -qE "circuit.?breaker.*idle"; then
  echo "FAIL smoke: status missing 'circuit breaker: idle'. Got:" >&2
  echo "$output" >&2
  exit 1
fi
if ! echo "$output" | grep -qE "queue is empty"; then
  echo "FAIL smoke: status missing 'queue is empty'. Got:" >&2
  echo "$output" >&2
  exit 1
fi
if ! echo "$output" | grep -qE "example-host-project"; then
  echo "FAIL smoke: status missing project name. Got:" >&2
  echo "$output" >&2
  exit 1
fi

echo "smoke_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-1/smoke_test.sh
```

- [ ] **Step 2: Run smoke test, confirm it passes**

Run:
```bash
bash tests/phase-1/smoke_test.sh; echo "exit: $?"
```

Expected: `smoke_test: OK`; exit code 0.

- [ ] **Step 3: Create the run_all aggregator**

Create `tests/phase-1/run_all.sh` with:
```bash
#!/usr/bin/env bash
# Run all Phase 1 tests in order. Exit non-zero on any failure.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== schema_test ==="
python3 "$DIR/schema_test.py"

echo
echo "=== init_test ==="
bash "$DIR/init_test.sh"

echo
echo "=== status_test ==="
bash "$DIR/status_test.sh"

echo
echo "=== smoke_test ==="
bash "$DIR/smoke_test.sh"

echo
echo "All Phase 1 tests passed."
```

Make it executable:
```bash
chmod +x tests/phase-1/run_all.sh
```

- [ ] **Step 4: Run the full suite**

Run:
```bash
bash tests/phase-1/run_all.sh
```

Expected: each section prints PASS lines and ends with "All Phase 1 tests passed."; exit code 0.

- [ ] **Step 5: Create tests/README.md**

Create `tests/README.md` with:
````markdown
# Tests

Phase-scoped tests for the `agentic-dev` plugin. Each phase has its own subdirectory; tests are independent and can be run individually or via the phase's `run_all.sh`.

## Prerequisites

- Python 3.9+ with `pyyaml` and `jsonschema` installed (`pip install pyyaml jsonschema`)
- Claude Code installed and on `$PATH` (`claude --version` works)
- A current Claude subscription that supports `claude -p` (headless) invocation, OR an `ANTHROPIC_API_KEY` set for API-mode testing

## Running Phase 1

```bash
bash tests/phase-1/run_all.sh
```

Individual tests:
```bash
python3 tests/phase-1/schema_test.py
bash tests/phase-1/init_test.sh
bash tests/phase-1/status_test.sh
bash tests/phase-1/smoke_test.sh
```

## What each test covers

| Test | Validates |
|------|-----------|
| `schema_test.py` | Sample fixtures conform to state/queue/config JSON Schemas; a known-bad state is rejected. |
| `init_test.sh` | `/agentic-dev:init` creates the full `.claude/agentic/` tree with schema-valid state/queue/config; idempotent on re-run. |
| `status_test.sh` | `/agentic-dev:status` reads known state files and reports correct counts, current goal, config summary; handles not-initialized projects. |
| `smoke_test.sh` | Init followed by status produces the expected combined state. |

## Notes on billing

The shell tests invoke `claude -p` which counts as programmatic billing per Anthropic's June 15, 2026 policy (separate credit pool from Max interactive use). For local dev this is fine; for CI on large branches, watch the credit pool.

Production use of the plugin remains interactive — see the design spec, §5 and Appendix B.
````

- [ ] **Step 6: Commit**

```bash
git add tests/phase-1/smoke_test.sh tests/phase-1/run_all.sh tests/README.md
git commit -m "$(cat <<'EOF'
test(phase-1): add smoke test, run_all aggregator, and tests README

Smoke test exercises init+status in a single throwaway project. run_all
is the entry point for all Phase 1 tests. README documents prerequisites,
how to run individual tests, and the billing note for headless mode.

Phase 1 task 5/6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Polish — README cross-links and CHANGELOG

**Files:**
- Modify: `agentic-dev/README.md` (add link to source spec and tests)
- Create: `agentic-dev/CHANGELOG.md`
- Modify: `marketplace.json` (update description if needed)

- [ ] **Step 1: Add a "Development" section to the plugin README**

Append to `agentic-dev/README.md`:

````markdown

## Development

Source repository: https://github.com/Pankaj-Bhasin/agenticDev

To run the test suite from the source repo:

```bash
bash tests/phase-1/run_all.sh
```

Design and architecture:
- `docs/superpowers/specs/2026-05-20-three-role-agentic-pattern-design.md` — full design
- `docs/superpowers/plans/2026-05-20-agentic-dev-phase-1-plugin-skeleton.md` — Phase 1 implementation plan

## Changelog

See `agentic-dev/CHANGELOG.md`.
````

- [ ] **Step 2: Create CHANGELOG.md**

Create `agentic-dev/CHANGELOG.md` with:
```markdown
# Changelog

All notable changes to `agentic-dev` are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-05-20

Initial scaffold. Plugin installable and bootstrappable; no agentic loop yet.

### Added
- Plugin manifest and marketplace.json
- JSON Schemas for `state.json`, `queue.yaml`, `config.yaml`
- `/agentic-dev:init` skill — bootstraps `.claude/agentic/` in a host project; supports interactive prompts or YAML-driven config; idempotent
- `/agentic-dev:status` skill — read-only state report
- Phase 1 test suite (`tests/phase-1/`)

### Not yet shipped (see roadmap)
- `/agentic-dev:intent`, `:run`, `:start`, `:resume`, `:review`, `:restart` skills
- spec-drafter, hardened-reviewer, reviewer-adversary, implementer-strict subagents
- Deterministic gates, hook wiring, Telegram notifications
- Overnight queue, circuit breaker, cross-session memory
```

- [ ] **Step 3: Re-run the full Phase 1 suite to confirm nothing regressed**

Run:
```bash
bash tests/phase-1/run_all.sh
```

Expected: "All Phase 1 tests passed."; exit code 0.

- [ ] **Step 4: Verify plugin loads via marketplace path (simulated)**

Run:
```bash
claude --plugin-dir ./agentic-dev --print "Confirm /agentic-dev:status and /agentic-dev:init appear in /help. Reply with the literal string 'BOTH-PRESENT' if both are visible, else 'MISSING' and the names of any not visible." 2>&1 | tail -10
```

Expected: output contains `BOTH-PRESENT` (the model's reply to the prompt). If `MISSING`, investigate the skill discovery — most commonly a typo in the `SKILL.md` frontmatter or the directory name not matching the expected skill name.

- [ ] **Step 5: Final commit closing out Phase 1**

```bash
git add agentic-dev/README.md agentic-dev/CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(plugin): add CHANGELOG and dev section to plugin README

CHANGELOG.md records v0.1.0 scope and what's coming. Plugin README links
back to the source repo for design docs and test instructions.

Phase 1 task 6/6 — Phase 1 complete.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1 Completion Checklist

When Phase 1 is done, all of the following must be true:

- [ ] `bash tests/phase-1/run_all.sh` exits 0 from a fresh clone
- [ ] `claude --plugin-dir ./agentic-dev` lists `/agentic-dev:init` and `/agentic-dev:status` in `/help`
- [ ] Running `/agentic-dev:init` in a fresh project creates the full `.claude/agentic/` tree and the written files validate against the schemas
- [ ] Running `/agentic-dev:status` after init reports `circuit breaker: idle`, `queue is empty`, and the configured project name
- [ ] Running `/agentic-dev:status` in a project without `.claude/agentic/` prints the not-initialized message
- [ ] Re-running `/agentic-dev:init` on an already-initialized project does not modify existing files
- [ ] All six tasks' commits are on the branch; `git log --oneline` shows them in order
- [ ] `agentic-dev/CHANGELOG.md` records v0.1.0

## Out of scope for Phase 1 (deferred to later phases)

- Subagent definitions (P2 onward)
- Hooks and gate scripts (P4)
- Telegram MCP and notifications (P5)
- Skills beyond init/status (P2 onward)
- `marketplace.json` published on GitHub for `/plugin marketplace add` from a remote (P8)
- CI workflow (P8 — local-only test runner for now)
- Plugin smoke test against an actual `/plugin install` from a remote source (P8)
