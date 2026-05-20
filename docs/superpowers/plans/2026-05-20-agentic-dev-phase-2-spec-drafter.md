# Phase 2 — agentic-dev Spec Drafter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.2 of `agentic-dev`: a structured spec-drafting workflow where `/agentic-dev:intent <text>` produces a markdown spec with explicit `QUESTION-N` blocks at every architectural decision, a two-stage validator (deterministic-on-save + AI-on-approval) gates approval, and the drafter is forbidden from improvising outside a calibrated section-by-section table.

**Architecture:** Two skills (`/agentic-dev:intent` for the user, `/agentic-dev:_check-approval` invoked explicitly after deterministic validation passes), two subagents (`spec-drafter`, `spec-validator-ai`), one shell validator (`bin/validate-spec.sh`), one hook (PostToolUse on `Write|Edit`), one new JSON Schema (`spec.schema.json`). The drafter outputs the full spec markdown directly; the skill writes that markdown verbatim. AI validator concerns become new `QUESTION-N` blocks back in the spec — never silent rejections.

**Tech Stack:** Markdown (skills, agent prompts), JSON (manifest, schemas), YAML (spec frontmatter, config), Bash (validator + hook script + tests), Python stdlib + `jsonschema[format-nongpl]` + `pyyaml` (schema/spec parsing in tests; already in `tests/requirements.txt`), Claude Code skills/agents/hooks/MCP, `claude -p` (headless mode) for end-to-end tests.

**Reference spec:** `docs/superpowers/specs/2026-05-20-agentic-dev-phase-2-spec-drafter-design.md` — especially §4 (architecture), §5 (drafter calibration table), §6 (lifecycle), §7 (templates), §8 (validator details), §10 (testing strategy), §11 (load-bearing properties), §12 (scope).

**Note on the design's §6 Path D "signals":** Path D step 11 says the deterministic validator "signals the `_check-approval` skill." This plan makes that concrete as: the deterministic validator script, on detecting an approval flip with clean deterministic checks, prints an actionable instruction (`"Run /agentic-dev:_check-approval <spec-path>"`) and exits 0. The user runs the AI validator skill explicitly. Auto-firing the AI validator from the hook (`claude -p` nested inside a hook) is deferred — it's a one-line hooks.json change if v0.2 feedback says it's needed.

---

## File Structure

Files created or modified in Phase 2:

**Plugin source (new under `agentic-dev/`):**
- `agentic-dev/schemas/spec.schema.json` — JSON Schema for spec frontmatter (T1)
- `agentic-dev/bin/validate-spec.sh` — deterministic validator script (T1)
- `agentic-dev/skills/intent/SKILL.md` — `/agentic-dev:intent` user entry point (T2)
- `agentic-dev/agents/spec-drafter.md` — drafter subagent (T2)
- `agentic-dev/hooks/hooks.json` — PostToolUse hook wiring (T3)
- `agentic-dev/skills/_check-approval/SKILL.md` — AI validator orchestrator (T5)
- `agentic-dev/agents/spec-validator-ai.md` — AI validator subagent (T5)

**Plugin source (modified):**
- `agentic-dev/README.md` — usage docs for new skills (T6)
- `agentic-dev/CHANGELOG.md` — v0.2.0 entry (T6)

**Repo-level:**
- `DEFERRED.md` — closing notes if any new items surface during P2 (T6)

**Tests (new under `tests/phase-2/`):**
- `tests/phase-2/spec_schema_test.py` — schema fixture validation (T1)
- `tests/phase-2/validate_spec_test.py` — deterministic validator unit tests (T1)
- `tests/phase-2/intent_fresh_test.sh` — end-to-end test of `/agentic-dev:intent "<text>"` (T2)
- `tests/phase-2/hook_test.sh` — verify hook fires on spec save (T3)
- `tests/phase-2/intent_refine_test.sh` — `--refine` flag test (T4)
- `tests/phase-2/approval_gate_test.sh` — full approval lifecycle including AI validator (T5)
- `tests/phase-2/run_all.sh` — phase 2 aggregator (T6)
- `tests/phase-2/fixtures/sample-spec-frontmatter.yaml` — schema test fixture (T1)
- `tests/phase-2/fixtures/spec-clean.md` — known-clean spec for AI validator (T5)
- `tests/phase-2/fixtures/spec-unmeasurable-criteria.md` — unmeasurable criterion (T5)
- `tests/phase-2/fixtures/spec-scope-incoherent.md` — scope contradiction (T5)

---

## Notes on testing strategy

Same approach as P1 (see `tests/README.md`):

- **Deterministic tests** run in pure Python/bash — no `claude -p` needed.
- **End-to-end tests** invoke `claude -p` and need `~/.claude/agentic-dev-test.env` sourced for the API key. They use `--add-dir` to give Claude access to fixture files outside the throwaway project, and `--dangerously-skip-permissions` to allow writes under `.claude/`. All shell tests honor `KEEP_TMP=1` for debugging-friendly preservation of the tmp project on failure.
- Each test that calls Claude captures its output to a file inside `$TMP_PROJECT` so failure diagnostics include Claude's stdout/stderr, not just the assertion failure (the P1 lesson from `init_test.sh`).
- Budget: ~10 `claude -p` invocations per full P2 `run_all.sh`; ~$2–3 per run.

---

## Task 1: Spec frontmatter schema + deterministic validator + tests

**Files:**
- Create: `agentic-dev/schemas/spec.schema.json`
- Create: `agentic-dev/bin/validate-spec.sh`
- Create: `tests/phase-2/fixtures/sample-spec-frontmatter.yaml`
- Create: `tests/phase-2/spec_schema_test.py`
- Create: `tests/phase-2/validate_spec_test.py`

- [ ] **Step 1: Create the test directory and a sample frontmatter fixture**

Run:
```bash
mkdir -p agentic-dev/schemas agentic-dev/bin tests/phase-2/fixtures
```

Create `tests/phase-2/fixtures/sample-spec-frontmatter.yaml` with:
```yaml
id: 2026-05-20-add-rate-limiting-per-tenant
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-add-rate-limiting-per-tenant.md
approved: false
created_at: "2026-05-20T15:30:00Z"
```

- [ ] **Step 2: Write the failing schema test**

Create `tests/phase-2/spec_schema_test.py` with:
```python
"""Validate sample spec frontmatter fixtures against spec.schema.json."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(
        f"ERROR: missing dependency ({e.name}). Install with: "
        "pip install -r tests/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "agentic-dev" / "schemas" / "spec.schema.json"
FIXTURE_DIR = REPO_ROOT / "tests" / "phase-2" / "fixtures"


def main():
    results = []

    # Positive case: well-formed frontmatter validates cleanly
    if not SCHEMA_PATH.exists():
        print(f"FAIL spec-schema-positive: schema not found at {SCHEMA_PATH}")
        results.append(False)
    else:
        schema = json.loads(SCHEMA_PATH.read_text())
        good = yaml.safe_load((FIXTURE_DIR / "sample-spec-frontmatter.yaml").read_text())
        try:
            jsonschema.validate(
                instance=good,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("PASS spec-schema-positive")
            results.append(True)
        except jsonschema.ValidationError as e:
            print(f"FAIL spec-schema-positive: {e.message}")
            results.append(False)

        # Negative case: bad schema_version is rejected
        bad_version = dict(good)
        bad_version["schema_version"] = "9.9"
        try:
            jsonschema.validate(
                instance=bad_version,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-version: bad schema_version wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-version")
            results.append(True)

        # Negative case: missing required field
        missing_id = {k: v for k, v in good.items() if k != "id"}
        try:
            jsonschema.validate(
                instance=missing_id,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-missing-id: missing id wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-missing-id")
            results.append(True)

        # Negative case: malformed created_at
        bad_date = dict(good)
        bad_date["created_at"] = "not-a-date"
        try:
            jsonschema.validate(
                instance=bad_date,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-date: malformed date wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-date")
            results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the test, confirm it fails**

Run:
```bash
python3 tests/phase-2/spec_schema_test.py
```

Expected: `FAIL spec-schema-positive: schema not found at ...`; exit code 1.

- [ ] **Step 4: Create `spec.schema.json`**

Create `agentic-dev/schemas/spec.schema.json` with:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Agentic Spec Frontmatter",
  "description": "Frontmatter required at the top of every .claude/agentic/specs/*.md file.",
  "type": "object",
  "required": ["id", "schema_version", "intent_path", "approved", "created_at"],
  "additionalProperties": false,
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$",
      "description": "YYYY-MM-DD-<topic-slug>"
    },
    "schema_version": {
      "type": "string",
      "const": "0.1"
    },
    "intent_path": {
      "type": "string",
      "minLength": 1,
      "description": "Path to the intent file that produced this spec, relative to project root"
    },
    "approved": {
      "type": "boolean"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    }
  }
}
```

- [ ] **Step 5: Re-run schema test, confirm all four PASS**

Run:
```bash
python3 tests/phase-2/spec_schema_test.py
```

Expected: `PASS spec-schema-positive`, `PASS spec-schema-negative-version`, `PASS spec-schema-negative-missing-id`, `PASS spec-schema-negative-date`; exit code 0.

- [ ] **Step 6: Write the failing deterministic validator test**

Create `tests/phase-2/validate_spec_test.py` with:
```python
"""Unit tests for agentic-dev/bin/validate-spec.sh.

Each test creates a temporary spec file, runs the validator, asserts the exit
code and that specific substrings appear in stderr.
"""
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "agentic-dev" / "bin" / "validate-spec.sh"


def run_validator(spec_text: str):
    """Write spec_text to a tmp file, run validator, return (exit_code, stderr)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        intent_dir = Path(tmpdir) / ".claude" / "agentic" / "intents"
        spec_dir = Path(tmpdir) / ".claude" / "agentic" / "specs"
        intent_dir.mkdir(parents=True)
        spec_dir.mkdir(parents=True)

        # The validator checks intent_path resolves; create the referenced file
        intent_file = intent_dir / "2026-05-20-x.md"
        intent_file.write_text("intent body")

        spec_file = spec_dir / "2026-05-20-x.md"
        spec_file.write_text(spec_text)

        result = subprocess.run(
            [str(VALIDATOR), str(spec_file)],
            capture_output=True,
            text=True,
            cwd=tmpdir,
        )
        return result.returncode, result.stdout + result.stderr


# Test fixtures
GOOD_SPEC_NOT_APPROVED = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: false
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test spec body.

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

GOOD_SPEC_APPROVED_NO_QUESTIONS = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test spec body.

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

APPROVED_WITH_QUESTION = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    <!-- QUESTION-1 (architectural-decision) -->
    **Q:** Unanswered?
    **Your answer:** [REPLACE THIS LINE]

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

BAD_FRONTMATTER = "not yaml frontmatter at all, just plain text"

APPROVED_BAD_BUDGET = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    # Diff budget
    - Wall clock: zero minutes
    - Diff lines: 800
    - Files touched: 25
""")


def main():
    results = []

    def check(name, predicate):
        outcome = predicate()
        if outcome:
            print(f"PASS {name}")
            results.append(True)
        else:
            print(f"FAIL {name}")
            results.append(False)

    if not VALIDATOR.exists():
        print(f"FAIL setup: validator not found at {VALIDATOR}")
        sys.exit(1)

    code, out = run_validator(GOOD_SPEC_NOT_APPROVED)
    check("good-not-approved exits 0", lambda: code == 0)

    code, out = run_validator(GOOD_SPEC_APPROVED_NO_QUESTIONS)
    check("good-approved exits 0", lambda: code == 0)
    check("good-approved mentions check-approval", lambda: "_check-approval" in out)

    code, out = run_validator(APPROVED_WITH_QUESTION)
    check("approved-with-question exits 1", lambda: code == 1)
    check("approved-with-question names QUESTION-1", lambda: "QUESTION-1" in out)

    code, out = run_validator(BAD_FRONTMATTER)
    check("bad-frontmatter exits 1", lambda: code == 1)
    check("bad-frontmatter mentions frontmatter", lambda: "frontmatter" in out.lower())

    code, out = run_validator(APPROVED_BAD_BUDGET)
    check("bad-budget exits 1", lambda: code == 1)
    check("bad-budget mentions budget", lambda: "budget" in out.lower())

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 7: Run the test, confirm it fails**

Run:
```bash
python3 tests/phase-2/validate_spec_test.py
```

Expected: `FAIL setup: validator not found at .../validate-spec.sh`; exit code 1.

- [ ] **Step 8: Implement `validate-spec.sh`**

Create `agentic-dev/bin/validate-spec.sh` with:
```bash
#!/usr/bin/env bash
# Deterministic validator for .claude/agentic/specs/*.md files.
#
# Two invocation modes:
#  - Direct: `validate-spec.sh <spec-file>` — validates the given file.
#  - Hook: PostToolUse for Write|Edit. Hook input is JSON on stdin; the
#    script extracts tool_input.file_path. If the path doesn't match
#    .claude/agentic/specs/*.md, exits 0 silently.
#
# Exit codes:
#  0 — validation passed (or path doesn't match in hook mode)
#  1 — validation failed
#  2 — usage error
set -euo pipefail

# Determine spec file path
SPEC_FILE=""
if [[ $# -eq 1 ]]; then
  SPEC_FILE="$1"
elif [[ -p /dev/stdin ]]; then
  # Hook mode: read JSON from stdin, extract file_path
  INPUT="$(cat)"
  SPEC_FILE="$(printf '%s' "$INPUT" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))')"
  if [[ -z "$SPEC_FILE" ]]; then
    exit 0
  fi
else
  echo "Usage: validate-spec.sh <spec-file>" >&2
  exit 2
fi

# Only validate spec files
if [[ ! "$SPEC_FILE" =~ \.claude/agentic/specs/.*\.md$ ]]; then
  exit 0
fi

if [[ ! -f "$SPEC_FILE" ]]; then
  # Edit may have been a delete; nothing to validate
  exit 0
fi

# Helpers
fail() {
  echo "agentic-dev: spec validation failed" >&2
  echo "  file: $SPEC_FILE" >&2
  echo "  ERROR: $*" >&2
  exit 1
}

# Extract frontmatter (lines between first '---' and second '---')
FRONTMATTER="$(python3 - <<PY
import sys
text = open("$SPEC_FILE").read()
if not text.startswith("---"):
    print("__NO_FRONTMATTER__")
    sys.exit(0)
parts = text.split("---", 2)
if len(parts) < 3:
    print("__NO_FRONTMATTER__")
    sys.exit(0)
print(parts[1].strip())
PY
)"

if [[ "$FRONTMATTER" == "__NO_FRONTMATTER__" ]]; then
  fail "missing YAML frontmatter (must start with '---' and contain a closing '---')"
fi

# Parse frontmatter; validate required fields, types, formats
PARSE_OUTPUT="$(python3 - <<PY
import sys, yaml
from datetime import datetime
fm_text = """$FRONTMATTER"""
try:
    fm = yaml.safe_load(fm_text)
except yaml.YAMLError as e:
    print(f"PARSE_ERROR: {e}")
    sys.exit(0)

if not isinstance(fm, dict):
    print("PARSE_ERROR: frontmatter is not a YAML mapping")
    sys.exit(0)

required = ["id", "schema_version", "intent_path", "approved", "created_at"]
missing = [k for k in required if k not in fm]
if missing:
    print(f"PARSE_ERROR: missing required frontmatter field(s): {', '.join(missing)}")
    sys.exit(0)

if fm["schema_version"] != "0.1":
    print(f"PARSE_ERROR: schema_version must be \\"0.1\\", got {fm['schema_version']!r}")
    sys.exit(0)

if not isinstance(fm["approved"], bool):
    print(f"PARSE_ERROR: approved must be a boolean, got {type(fm['approved']).__name__}")
    sys.exit(0)

import re
if not re.match(r"^\\d{4}-\\d{2}-\\d{2}-[a-z0-9-]+$", str(fm["id"])):
    print(f"PARSE_ERROR: id must match YYYY-MM-DD-<slug>, got {fm['id']!r}")
    sys.exit(0)

try:
    datetime.fromisoformat(str(fm["created_at"]).replace("Z", "+00:00"))
except ValueError:
    print(f"PARSE_ERROR: created_at not a valid date-time, got {fm['created_at']!r}")
    sys.exit(0)

# Resolve intent_path relative to current working directory
import os
intent_path = fm["intent_path"]
if not os.path.exists(intent_path):
    print(f"PARSE_ERROR: intent_path does not resolve to a file: {intent_path}")
    sys.exit(0)

print(f"OK approved={fm['approved']}")
PY
)"

if [[ "$PARSE_OUTPUT" == PARSE_ERROR* ]]; then
  fail "${PARSE_OUTPUT#PARSE_ERROR: }"
fi

APPROVED="$(printf '%s' "$PARSE_OUTPUT" | sed -n 's/^OK approved=//p')"

# Check Diff budget section parses
BUDGET_OUTPUT="$(python3 - <<PY
import re
text = open("$SPEC_FILE").read()
m = re.search(r"^# Diff budget\\s*$(.*?)(?=^# |\\Z)", text, re.MULTILINE | re.DOTALL)
if not m:
    print("BUDGET_ERROR: missing '# Diff budget' section")
    raise SystemExit
section = m.group(1)
def grab(label):
    mm = re.search(rf"- {label}:\\s*(\\S+)", section)
    return mm.group(1) if mm else None
wc = grab("Wall clock")
dl = grab("Diff lines")
ft = grab("Files touched")
if not wc or not dl or not ft:
    print("BUDGET_ERROR: budget section must have 'Wall clock', 'Diff lines', and 'Files touched' lines")
    raise SystemExit
try:
    # Wall clock can be "90 minutes" — extract leading int
    import re as _re
    wc_int = int(_re.match(r"(\\d+)", wc).group(1))
    dl_int = int(dl)
    ft_int = int(ft)
except (AttributeError, ValueError, TypeError):
    print("BUDGET_ERROR: budget values must be positive integers")
    raise SystemExit
if wc_int < 1 or dl_int < 1 or ft_int < 1:
    print("BUDGET_ERROR: budget values must be >= 1")
    raise SystemExit
print("BUDGET_OK")
PY
)"

if [[ "$BUDGET_OUTPUT" == BUDGET_ERROR* ]]; then
  fail "${BUDGET_OUTPUT#BUDGET_ERROR: }"
fi

# Check for unresolved QUESTION-N blocks if approved=true
if [[ "$APPROVED" == "True" ]]; then
  if grep -qE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE"; then
    QUESTIONS="$(grep -nE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" | sed -E 's/^([0-9]+):.*<!-- (QUESTION-[0-9]+) \\(([^)]+)\\).*/  - \\2 (\\3) at line \\1/')"
    echo "agentic-dev: spec validation failed" >&2
    echo "  file: $SPEC_FILE" >&2
    echo "  ERROR: approved=true but unresolved QUESTION blocks remain:" >&2
    echo "$QUESTIONS" >&2
    echo "  Either answer those questions or set approved=false." >&2
    exit 1
  fi
  if grep -qF "[REPLACE THIS LINE" "$SPEC_FILE"; then
    fail "approved=true but '[REPLACE THIS LINE' placeholder(s) still present in the spec body"
  fi
  echo "agentic-dev: spec validation passed"
  echo "  file: $SPEC_FILE"
  echo "  state: approved"
  echo "  Next: run /agentic-dev:_check-approval $SPEC_FILE to dispatch the AI validator."
else
  REMAINING="$(grep -cE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" || true)"
  echo "agentic-dev: spec validation passed"
  echo "  file: $SPEC_FILE"
  echo "  state: draft ($REMAINING questions remaining)"
fi
```

Make it executable:
```bash
chmod +x agentic-dev/bin/validate-spec.sh
```

- [ ] **Step 9: Run the deterministic validator test, confirm all checks pass**

Run:
```bash
python3 tests/phase-2/validate_spec_test.py
```

Expected: 9 PASS lines (good-not-approved, good-approved, mentions check-approval, approved-with-question x2, bad-frontmatter x2, bad-budget x2); exit code 0.

- [ ] **Step 10: Run both phase-2 tests so far in a quick sequence**

Run:
```bash
python3 tests/phase-2/spec_schema_test.py && python3 tests/phase-2/validate_spec_test.py
```

Expected: both exit 0; combined PASS lines printed.

- [ ] **Step 11: Commit**

Run:
```bash
git add agentic-dev/schemas/spec.schema.json agentic-dev/bin/validate-spec.sh tests/phase-2/spec_schema_test.py tests/phase-2/validate_spec_test.py tests/phase-2/fixtures/sample-spec-frontmatter.yaml
git commit -m "feat(phase-2): spec frontmatter schema + deterministic validator

Adds:
- agentic-dev/schemas/spec.schema.json — required frontmatter fields
  with date-time format-checking, id pattern, schema_version const \"0.1\".
- agentic-dev/bin/validate-spec.sh — deterministic checks on every
  spec save: frontmatter parses, required fields present, schema_version
  matches, approved is bool, id pattern matches, created_at is valid
  date-time, intent_path resolves, Diff budget section parses with
  positive-integer values, no unresolved QUESTION-N blocks when
  approved=true, no leftover [REPLACE THIS LINE markers when approved.
- tests/phase-2/spec_schema_test.py — positive + 3 negative cases.
- tests/phase-2/validate_spec_test.py — 9 assertions across 5 fixture
  shapes (good-not-approved, good-approved, approved-with-question,
  bad-frontmatter, bad-budget).

The validator supports both direct invocation (CLI argument) and hook
invocation (reads tool_input.file_path from stdin JSON), exiting 0
silently when invoked on non-spec files.

Phase 2 task 1/6."
```

---

## Task 2: `spec-drafter` subagent + `/agentic-dev:intent` (fresh path only)

**Files:**
- Create: `agentic-dev/agents/spec-drafter.md`
- Create: `agentic-dev/skills/intent/SKILL.md`
- Create: `tests/phase-2/intent_fresh_test.sh`

Scope: the happy path of fresh-intent → drafted spec. `--refine` is T4. AI validator is T5.

- [ ] **Step 1: Write the failing end-to-end test for the fresh path**

Create `tests/phase-2/intent_fresh_test.sh` with:
```bash
#!/usr/bin/env bash
# End-to-end test: /agentic-dev:intent "<text>" produces an intent file and
# a draft spec file with QUESTION-N blocks and approved=false.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-intent-fresh-XXXXXX)"
# Set KEEP_TMP=1 to preserve the tmp project on exit for debugging.
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
echo "console.log('hello')" > index.js
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial"

# Init the project first (uses P1's init skill + fixture)
init_out="$TMP_PROJECT/_init_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >"$init_out" 2>&1 || true

if [[ ! -f .claude/agentic/state.json ]]; then
  echo "FAIL setup: init did not produce state.json" >&2
  cat "$init_out" >&2
  exit 1
fi

# Now run the intent skill
intent_out="$TMP_PROJECT/_intent_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent Add rate limiting per-tenant to the API" >"$intent_out" 2>&1 || true

ok=1
must_exist() {
  if [[ ! -e "$1" ]]; then
    echo "FAIL missing: $1" >&2
    ok=0
  else
    echo "PASS exists: $1"
  fi
}

# An intent file should have been created under .claude/agentic/intents/
intent_files=(.claude/agentic/intents/*.md)
if [[ "${intent_files[0]}" == ".claude/agentic/intents/*.md" ]]; then
  echo "FAIL missing: .claude/agentic/intents/*.md" >&2
  ok=0
else
  echo "PASS exists: ${intent_files[0]}"
fi

# A spec file should have been created under .claude/agentic/specs/
spec_files=(.claude/agentic/specs/*.md)
if [[ "${spec_files[0]}" == ".claude/agentic/specs/*.md" ]]; then
  echo "FAIL missing: .claude/agentic/specs/*.md" >&2
  ok=0
else
  echo "PASS exists: ${spec_files[0]}"
fi

if [[ $ok -ne 1 ]]; then
  echo "--- Intent claude output was: ---" >&2
  cat "$intent_out" >&2
  exit 1
fi

SPEC_FILE="${spec_files[0]}"
INTENT_FILE="${intent_files[0]}"

# Frontmatter checks via the deterministic validator
"$PLUGIN_DIR/bin/validate-spec.sh" "$SPEC_FILE"

# Approved should be false
if ! grep -qE '^approved:\s*false' "$SPEC_FILE"; then
  echo "FAIL: spec frontmatter does not have approved: false" >&2
  cat "$SPEC_FILE" >&2
  exit 1
fi
echo "PASS spec has approved: false"

# At least one QUESTION-N block should be present
question_count=$(grep -cE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" || echo "0")
if [[ "$question_count" -lt 1 ]]; then
  echo "FAIL: spec has 0 QUESTION-N blocks (expected at least 1)" >&2
  cat "$SPEC_FILE" >&2
  exit 1
fi
echo "PASS spec has $question_count QUESTION-N block(s)"

# The required sections should all be present
for section in "# Intent" "# Scope — In" "# Scope — Out" "# Files in scope" "# Architectural decisions" "# ADR candidates" "# Test strategy" "# Completion criteria" "# Diff budget"; do
  if ! grep -qF "$section" "$SPEC_FILE"; then
    echo "FAIL: spec missing section: $section" >&2
    cat "$SPEC_FILE" >&2
    exit 1
  fi
done
echo "PASS spec has all 9 required sections"

# Intent file should contain the human's text verbatim
if ! grep -qF "Add rate limiting per-tenant to the API" "$INTENT_FILE"; then
  echo "FAIL: intent file does not contain the original text" >&2
  cat "$INTENT_FILE" >&2
  exit 1
fi
echo "PASS intent file contains original text"

echo "intent_fresh_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-2/intent_fresh_test.sh
```

- [ ] **Step 2: Run the test, confirm it fails**

Run:
```bash
bash tests/phase-2/intent_fresh_test.sh; echo "exit: $?"
```

Expected: `FAIL missing: .claude/agentic/intents/*.md` and similar — the intent skill doesn't exist yet so `claude -p` returns an `Unknown command` message; exit code 1.

- [ ] **Step 3: Implement the `spec-drafter` subagent**

Create `agentic-dev/agents/spec-drafter.md` with:
````markdown
---
name: spec-drafter
description: Drafts a structured spec from an intent text. Emits the full spec markdown directly. Anti-eagerness: forbidden from guessing on architectural decisions — must flag every non-trivial choice as a QUESTION-N block with 2–4 concrete options.
tools: Read, Glob, Grep
---

You are the agentic-dev spec drafter. You take a free-form intent text and produce a structured spec markdown document. You are read-only — you must NOT use Write, Edit, NotebookEdit, or any mutating Bash command. Your output IS the spec body; the invoking skill writes your text to disk.

## Calibration table

For each spec section, your behavior is fixed by this table:

| Section / field | Behavior |
|---|---|
| Frontmatter `id`, `created_at` | Set confidently from the inputs you were given. |
| Frontmatter `approved` | Always `false`. |
| Frontmatter `schema_version` | Always `"0.1"` (literal). |
| Frontmatter `intent_path` | Set confidently to the intent file path you were given. |
| `# Intent` body | Echo the human's words verbatim. No paraphrase. |
| `# Scope — In` | Emit a QUESTION-N block with 2–4 concrete options derived from the intent. Never confidently set. |
| `# Scope — Out (deferrals)` | Emit a QUESTION-N block. Forces explicit boundary thinking. |
| `# Files in scope` | Emit a QUESTION-N block with suggestions. You may use Read/Glob on the host project to propose realistic paths. |
| `# Architectural decisions` | Emit a separate QUESTION-N block per non-trivial decision. This is load-bearing — when in doubt, flag. |
| `# ADR candidates` | Emit a QUESTION-N block with proposed candidates. An empty list is a valid answer. |
| `# Test strategy` | Confident default for small changes: "Add tests for new behaviors; existing tests must continue to pass." Emit a QUESTION-N block instead if the intent suggests integration tests, end-to-end flows, or performance benchmarks. |
| `# Completion criteria` | Emit a QUESTION-N block. Include the explicit reminder that each criterion must be measurable (observable outcome). |
| `# Diff budget` | Use the defaults you were given (90 min / 800 lines / 25 files). Emit a QUESTION-N block instead if the intent uses words like "rewrite", "refactor across", or "migrate" suggesting larger work. |
| `# Sensitive paths` | Note `(inherits from config.yaml)`. Emit a QUESTION-N block only if the intent suggests touching a path the user might want to add. |

If a section is not in this table, default to flagging (emit a QUESTION-N).

## QUESTION-N block format

Use this exact format for every flagged ambiguity. The HTML comment delimiter `<!-- QUESTION-N (category) -->` is machine-parseable; the validator looks for it.

```markdown
<!-- QUESTION-N (category) -->
**Q:** <one-sentence question>

**Why this matters:** <one or two sentences explaining the consequence of the choice>

**Options:**
- A. <option text>
- B. <option text>
- C. <option text>

**Your answer:** [REPLACE THIS LINE with A, B, C, or your own text]
```

Number QUESTION blocks sequentially across the whole document, starting at 1. Use these categories: `scope-in`, `scope-out`, `files-in-scope`, `architectural-decision`, `adr-candidates`, `test-strategy`, `completion-criteria`, `diff-budget`, `sensitive-paths`, `slug`.

## Output contract

Your response is ONLY the spec markdown content, beginning with `---\n` (the frontmatter opener). Do not include any preamble, commentary, or explanation outside the spec body. Do not wrap the output in code fences. The invoking skill will write your output verbatim to the spec file.

## Multi-intent guard

If the intent text contains multiple distinct goals (joined by "and", "plus", "also", or appearing as separate sentences with different verbs), refuse with this exact response (no spec body):

```
ERROR: Multiple intents detected in input. Run /agentic-dev:intent once per goal so each gets its own spec.
```

This is the anti-eagerness boundary — do not silently pick one and run with it.

## Inputs you will receive

The invoking skill will provide:
- `intent_id` — the YYYY-MM-DD-slug to use in frontmatter
- `intent_text` — the human's verbatim words
- `intent_path` — the path to the intent file
- `created_at` — ISO 8601 timestamp
- `config_defaults` — JSON with diff budget defaults, sensitive paths defaults
- `repo_overview` — a short summary of the host project structure

Use these directly. Do not invent values for required frontmatter fields. If a required input is missing, refuse with a clear error.

## Example output structure

```markdown
---
id: 2026-05-20-add-rate-limiting-per-tenant
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-add-rate-limiting-per-tenant.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Add rate limiting per-tenant to the API

# Scope — In

<!-- QUESTION-1 (scope-in) -->
**Q:** Which surfaces of the API should rate limiting cover?
...

# Scope — Out (deferrals)

<!-- QUESTION-2 (scope-out) -->
...

# Files in scope

<!-- QUESTION-3 (files-in-scope) -->
...

# Architectural decisions

<!-- QUESTION-4 (architectural-decision) -->
...

# ADR candidates

<!-- QUESTION-5 (adr-candidates) -->
...

# Test strategy

Add tests for new behaviors; existing tests must continue to pass.

# Completion criteria

<!-- QUESTION-6 (completion-criteria) -->
...

# Diff budget

- Wall clock: 90 minutes
- Diff lines: 800
- Files touched: 25

# Sensitive paths

(inherits from config.yaml)
```
````

- [ ] **Step 4: Implement the `/agentic-dev:intent` skill (fresh path only)**

Create `agentic-dev/skills/intent/SKILL.md` with:
````markdown
---
description: User entry point for drafting a new spec. Records the raw intent text, dispatches the spec-drafter subagent to produce a structured draft, writes the draft to disk. v0.2 supports only the fresh path; --refine ships in v0.2.x.
---

# /agentic-dev:intent

You are the user entry point for drafting a new agentic-dev spec.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the free-form intent text describing what work the user wants to specify. It should be a single coherent goal in 1–3 sentences. If it's empty, refuse with: `agentic-dev: /agentic-dev:intent requires a free-form goal description. Example: /agentic-dev:intent "Add rate limiting per-tenant"`.

## Pre-checks

Before doing anything else:

1. Verify the current working directory contains `.claude/agentic/state.json`. If it does not, print: `agentic-dev: not initialized in this project (run /agentic-dev:init first)` and exit.

2. Read `.claude/agentic/config.yaml` to extract the diff-budget defaults and sensitive_paths defaults. You'll pass these to the drafter.

## Generate the intent id

1. Derive a kebab-case slug from the first 5–8 meaningful words of `$ARGUMENTS`. Strip stop words ("the", "a", "an", "to", "for", "of", "in", "on", "and", "or", "but"). Lowercase. Replace non-alphanumerics with hyphens. Collapse repeated hyphens. Trim leading/trailing hyphens.
2. Get today's date in UTC: use `date -u +"%Y-%m-%d"` via the Bash tool.
3. Construct `intent_id` = `<YYYY-MM-DD>-<slug>`.
4. Construct `created_at` = current UTC timestamp in `YYYY-MM-DDTHH:MM:SSZ` format: `date -u +"%Y-%m-%dT%H:%M:%SZ"`.

## Idempotency check

Check if `.claude/agentic/intents/<intent_id>.md` already exists. If it does:
- Print: `agentic-dev: intent already exists at .claude/agentic/intents/<intent_id>.md`
- Print: `  Spec file: .claude/agentic/specs/<intent_id>.md`
- Print: `  To re-draft, use /agentic-dev:intent --refine .claude/agentic/specs/<intent_id>.md (ships in v0.2.x)`
- Exit without writing anything.

## Write the intent file

Use the Write tool to create `.claude/agentic/intents/<intent_id>.md` with:
```markdown
---
id: <intent_id>
created_at: <created_at>
---

<$ARGUMENTS verbatim>
```

## Dispatch the spec-drafter subagent

Use the Agent tool (subagent_type: spec-drafter) with a prompt that includes:
```
You are drafting a spec for this intent.

intent_id: <intent_id>
intent_path: .claude/agentic/intents/<intent_id>.md
created_at: <created_at>

intent_text:
<$ARGUMENTS verbatim>

config_defaults (from .claude/agentic/config.yaml):
- wall_clock_minutes_per_goal: <value>
- diff_lines_per_goal: <value>
- files_touched_per_goal: <value>
- sensitive_paths: <list>

repo_overview:
<a brief summary of the host project: directory layout from `ls` or `find . -maxdepth 2 -type d`, primary language from .claude/agentic/config.yaml>

Output the complete spec markdown per your calibration table and output contract. Begin with the frontmatter opener `---`.
```

## Capture the drafter's output

The Agent tool returns the drafter's response. The response should begin with `---` (the frontmatter opener). If it doesn't, or if the response starts with `ERROR:`, do NOT write a spec file. Instead:
- Print the drafter's response to the user.
- Print: `agentic-dev: drafter did not return a valid spec. Intent file preserved at .claude/agentic/intents/<intent_id>.md.`
- Exit.

## Write the spec file

If the drafter returned a valid spec body (starts with `---`):
- Use the Write tool to create `.claude/agentic/specs/<intent_id>.md` with the drafter's response verbatim.
- Count the number of `<!-- QUESTION-` markers in the body.
- Print:
  ```
  agentic-dev: intent drafted

    intent: .claude/agentic/intents/<intent_id>.md
    spec:   .claude/agentic/specs/<intent_id>.md
    questions to resolve: <count>

  Next:
    - Open the spec file and answer each QUESTION-N block by replacing the "Your answer:" line.
    - When all questions are resolved, set `approved: true` in the spec frontmatter.
    - After approval, run /agentic-dev:_check-approval <spec-path> to dispatch the AI validator.
  ```

## Do NOT

- Do not modify any project files outside `.claude/agentic/`.
- Do not commit anything.
- Do not invoke /agentic-dev:_check-approval automatically — that's an explicit user action.
- Do not modify the drafter's output before writing it. If it's malformed, refuse rather than fix it.
````

- [ ] **Step 5: Run the fresh-intent test, confirm all assertions pass**

Run:
```bash
bash tests/phase-2/intent_fresh_test.sh; echo "exit: $?"
```

Expected: all PASS lines including section presence, question count >= 1, intent text echoed, deterministic validator passes; `intent_fresh_test: OK`; exit 0.

If it fails because the skill's slug generation or section emission doesn't match what the test asserts, iterate on the SKILL.md or the drafter prompt — but do NOT relax the test assertions. Document iterations honestly.

- [ ] **Step 6: Commit**

Run:
```bash
git add agentic-dev/agents/spec-drafter.md agentic-dev/skills/intent tests/phase-2/intent_fresh_test.sh
git commit -m "feat(phase-2): spec-drafter subagent + /agentic-dev:intent skill

- agents/spec-drafter.md — drafter subagent with the calibration table
  (anti-eagerness: every architectural decision flagged as QUESTION-N).
  Read-only (Read, Glob, Grep tools only); outputs the full spec body
  as its response. Multi-intent guard refuses inputs with multiple
  distinct goals.
- skills/intent/SKILL.md — user entry point. Derives intent_id from
  the input text, writes intent file, dispatches spec-drafter, writes
  the returned body to specs/, prints next-steps including the
  /agentic-dev:_check-approval hand-off. Idempotent on duplicate
  invocation (existing intent → no re-draft, prints existing path).
- tests/phase-2/intent_fresh_test.sh — end-to-end test: init the
  project, run /agentic-dev:intent, assert intent + spec files exist,
  spec passes deterministic validator, approved: false, >= 1
  QUESTION-N block, all 9 required sections present, intent text
  echoed verbatim.

Phase 2 task 2/6."
```

---

## Task 3: Hook wiring for `validate-spec.sh`

**Files:**
- Create: `agentic-dev/hooks/hooks.json`
- Create: `tests/phase-2/hook_test.sh`

- [ ] **Step 1: Write the failing hook test**

Create `tests/phase-2/hook_test.sh` with:
```bash
#!/usr/bin/env bash
# Verify the validate-spec.sh hook fires on Write|Edit of a spec file and
# emits the expected messages.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-hook-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

# Init the project
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

# Hand-write a valid draft spec (skipping the drafter for hook isolation)
mkdir -p .claude/agentic/intents .claude/agentic/specs
cat > .claude/agentic/intents/2026-05-20-test.md <<'INTENT'
---
id: 2026-05-20-test
created_at: "2026-05-20T15:30:00Z"
---

Test intent
INTENT

SPEC=.claude/agentic/specs/2026-05-20-test.md
cat > "$SPEC" <<'SPEC_DRAFT'
---
id: 2026-05-20-test
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-test.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent
Test.

<!-- QUESTION-1 (architectural-decision) -->
**Q:** Test?
**Your answer:** [REPLACE THIS LINE]

# Diff budget
- Wall clock: 90 minutes
- Diff lines: 800
- Files touched: 25
SPEC_DRAFT

# Ask claude -p to Edit the spec file. This should fire PostToolUse on Edit.
hook_out="$TMP_PROJECT/_hook_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "Use the Edit tool to change the approved field in $SPEC from false to true. Then exit." \
  >"$hook_out" 2>&1 || true

# After the edit, the hook should have fired and emitted a validation failure
# because the spec has approved=true but a QUESTION-1 block remains.
if ! grep -qE 'spec validation failed' "$hook_out"; then
  echo "FAIL: hook did not produce 'spec validation failed' message" >&2
  echo "--- claude output was: ---" >&2
  cat "$hook_out" >&2
  exit 1
fi
echo "PASS hook fired validation failure on approved=true with unresolved QUESTION"

# Now answer the question and re-edit. Validator should pass and emit
# the _check-approval next-step message.
sed -i.bak 's/\[REPLACE THIS LINE\]/A/' "$SPEC"
rm -f "$SPEC.bak"

hook_out2="$TMP_PROJECT/_hook_output2.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "Use the Edit tool to make any trivial whitespace-only edit to $SPEC (such as adding a trailing newline). Then exit." \
  >"$hook_out2" 2>&1 || true

if ! grep -qE 'state: approved' "$hook_out2"; then
  echo "FAIL: hook did not emit 'state: approved' on clean approved spec" >&2
  cat "$hook_out2" >&2
  exit 1
fi
if ! grep -qE '_check-approval' "$hook_out2"; then
  echo "FAIL: hook did not mention /agentic-dev:_check-approval next step" >&2
  cat "$hook_out2" >&2
  exit 1
fi
echo "PASS hook emits _check-approval next-step on clean approved spec"

echo "hook_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-2/hook_test.sh
```

- [ ] **Step 2: Run the test, confirm it fails**

Run:
```bash
bash tests/phase-2/hook_test.sh; echo "exit: $?"
```

Expected: `FAIL: hook did not produce 'spec validation failed' message`; exit 1.

- [ ] **Step 3: Create the hook configuration**

Create `agentic-dev/hooks/hooks.json` with:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/bin/validate-spec.sh"
          }
        ]
      }
    ]
  }
}
```

The `${CLAUDE_PLUGIN_ROOT}` environment variable is set by Claude Code to the plugin's installation root. The validator script handles the JSON-on-stdin extraction and the "not a spec file → exit 0" filtering itself, so this matcher can be broad without causing noise on other Write/Edit calls.

- [ ] **Step 4: Run the hook test, confirm both assertions pass**

Run:
```bash
bash tests/phase-2/hook_test.sh; echo "exit: $?"
```

Expected: `PASS hook fired validation failure...`, `PASS hook emits _check-approval next-step...`, `hook_test: OK`; exit 0.

If the hook doesn't appear to fire (no validation messages at all in Claude's output), check that the `command` field in hooks.json resolves to an executable path (`ls -l $CLAUDE_PLUGIN_ROOT/bin/validate-spec.sh` should show `-rwxr-xr-x`) and that hooks.json is valid JSON.

- [ ] **Step 5: Commit**

Run:
```bash
git add agentic-dev/hooks/hooks.json tests/phase-2/hook_test.sh
git commit -m "feat(phase-2): wire validate-spec.sh as PostToolUse hook

- hooks/hooks.json — registers validate-spec.sh as a PostToolUse hook
  on Write|Edit. The matcher is intentionally broad (Write|Edit on any
  file); the validator script filters internally to .claude/agentic/
  specs/*.md, exiting 0 silently for non-spec files.
- tests/phase-2/hook_test.sh — verifies the hook fires on spec edits.
  Two assertions: approved=true with unresolved QUESTION → 'spec
  validation failed'; clean approved spec → 'state: approved' plus the
  /agentic-dev:_check-approval next-step instruction.

\${CLAUDE_PLUGIN_ROOT} resolves to the plugin's install root at hook
invocation time, so the hook works regardless of how the plugin was
installed (--plugin-dir vs marketplace install).

Phase 2 task 3/6."
```

---

## Task 4: `--refine` mode for `/agentic-dev:intent`

**Files:**
- Modify: `agentic-dev/skills/intent/SKILL.md`
- Modify: `agentic-dev/agents/spec-drafter.md`
- Create: `tests/phase-2/intent_refine_test.sh`

- [ ] **Step 1: Write the failing refine test**

Create `tests/phase-2/intent_refine_test.sh` with:
```bash
#!/usr/bin/env bash
# Verify /agentic-dev:intent --refine <spec-path> re-runs the drafter on a
# partial spec, preserving the human's existing answers and emitting zero
# or more new QUESTION-N blocks if answers exposed new ambiguities.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-refine-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

# Init + first intent
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent Add rate limiting per-tenant to the API" >/dev/null 2>&1 || true

spec_files=(.claude/agentic/specs/*.md)
SPEC="${spec_files[0]}"

# Answer the first QUESTION-N block; leave the rest unanswered
python3 - <<PY
import re
text = open("$SPEC").read()
# Find the first QUESTION block and replace its "Your answer:" line with "A"
def replace_first_answer(match):
    block = match.group(0)
    return re.sub(r"\\*\\*Your answer:\\*\\*.*", "**Your answer:** A", block, count=1)
new_text = re.sub(
    r"<!-- QUESTION-1 [^>]+-->.*?\\*\\*Your answer:\\*\\*[^\\n]*",
    replace_first_answer,
    text,
    count=1,
    flags=re.DOTALL,
)
open("$SPEC", "w").write(new_text)
PY

# Snapshot the spec before refining
cp "$SPEC" "$SPEC.before-refine"

# Run refine
refine_out="$TMP_PROJECT/_refine_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent --refine $SPEC" >"$refine_out" 2>&1 || true

if [[ ! -f "$SPEC" ]]; then
  echo "FAIL: spec file disappeared after refine" >&2
  cat "$refine_out" >&2
  exit 1
fi

# The answer to QUESTION-1 must still be "A"
if ! grep -qE '\*\*Your answer:\*\* A' "$SPEC"; then
  echo "FAIL: --refine overwrote the human's answer to QUESTION-1" >&2
  diff "$SPEC.before-refine" "$SPEC" >&2 || true
  exit 1
fi
echo "PASS --refine preserved the human's answer to QUESTION-1"

# The frontmatter id must be unchanged
id_before=$(awk '/^id:/{print $2; exit}' "$SPEC.before-refine")
id_after=$(awk '/^id:/{print $2; exit}' "$SPEC")
if [[ "$id_before" != "$id_after" ]]; then
  echo "FAIL: --refine changed frontmatter id ($id_before -> $id_after)" >&2
  exit 1
fi
echo "PASS --refine preserved frontmatter id"

# The deterministic validator must still pass (approved is still false)
"$PLUGIN_DIR/bin/validate-spec.sh" "$SPEC"
echo "PASS --refine output still passes deterministic validation"

echo "intent_refine_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-2/intent_refine_test.sh
```

- [ ] **Step 2: Run the test, confirm it fails**

Run:
```bash
bash tests/phase-2/intent_refine_test.sh; echo "exit: $?"
```

Expected: failure because the skill doesn't yet understand `--refine`; exit 1.

- [ ] **Step 3: Extend the `/agentic-dev:intent` skill to handle `--refine`**

Edit `agentic-dev/skills/intent/SKILL.md` and add this section between the existing "How to interpret `$ARGUMENTS`" section and "Pre-checks":

```markdown
## --refine mode

If `$ARGUMENTS` begins with `--refine ` (a literal `--refine` followed by a space), this is refine mode.

Parse the remaining text as a spec file path. If the path:
- Does not exist → print `agentic-dev: --refine target does not exist: <path>` and exit.
- Does not match `.claude/agentic/specs/*.md` → print `agentic-dev: --refine target must be a spec file under .claude/agentic/specs/` and exit.
- Has `approved: true` in its frontmatter → print `agentic-dev: cannot --refine an approved spec; set approved: false first if you want to re-open it` and exit.

Otherwise:

1. Read the current spec file in full.
2. Parse it: extract the existing frontmatter, the sections, and the existing QUESTION-N blocks (both answered and unanswered).
3. Dispatch the spec-drafter subagent with refine inputs (described in the drafter agent definition). The drafter receives the CURRENT spec body and must produce an UPDATED spec body that:
   - Preserves every "Your answer:" line that has been modified by the human (anything that's not `[REPLACE THIS LINE...]`).
   - May add new QUESTION-N blocks if the human's answers exposed new ambiguities.
   - Never deletes or modifies existing answered QUESTIONs.
4. Write the drafter's response verbatim to the spec file (overwrites the previous content).
5. Print the same next-steps as the fresh path, but with `(refined)` annotating the spec path.

Skip the id generation, the idempotency check, the intent-file write step, and the config-defaults lookup in refine mode — they only apply to fresh intents.
```

- [ ] **Step 4: Extend the drafter to handle the refine input shape**

Edit `agentic-dev/agents/spec-drafter.md` and add this section before "Inputs you will receive":

```markdown
## Refine mode

If your invoking prompt includes `mode: refine` and provides `existing_spec_body`, your job is different:

1. Parse the existing spec body.
2. Identify which QUESTION-N blocks have been answered (a "Your answer:" line that is NOT `[REPLACE THIS LINE...]` or empty).
3. Output an UPDATED spec body that:
   - PRESERVES the frontmatter exactly (do NOT change id, created_at, schema_version, intent_path; do NOT flip approved).
   - PRESERVES every answered QUESTION-N block verbatim — text, options, and the human's answer.
   - May ADD new QUESTION-N blocks below answered ones if the human's answers expose new ambiguities. Number new blocks sequentially after the highest existing N.
   - Never deletes a QUESTION-N block.
   - Never modifies the body of an answered QUESTION-N block.

The output contract is the same as fresh mode: respond ONLY with the spec markdown beginning with `---`. No commentary. No code fences.
```

Also extend the "Inputs you will receive" list:
```markdown
For refine mode:
- `mode`: "refine"
- `spec_path`: the path to the spec being refined
- `existing_spec_body`: the current contents of the spec file verbatim
```

- [ ] **Step 5: Run the refine test, confirm it passes**

Run:
```bash
bash tests/phase-2/intent_refine_test.sh; echo "exit: $?"
```

Expected: `PASS --refine preserved the human's answer to QUESTION-1`, `PASS --refine preserved frontmatter id`, `PASS --refine output still passes deterministic validation`; `intent_refine_test: OK`; exit 0.

- [ ] **Step 6: Commit**

Run:
```bash
git add agentic-dev/skills/intent/SKILL.md agentic-dev/agents/spec-drafter.md tests/phase-2/intent_refine_test.sh
git commit -m "feat(phase-2): /agentic-dev:intent --refine mode

- skills/intent/SKILL.md — adds --refine <spec-path> handling. Parses
  argument prefix, validates path, refuses on missing file, non-spec
  path, or already-approved spec. Reads current body, dispatches the
  drafter with mode: refine + existing_spec_body, writes back verbatim.
- agents/spec-drafter.md — adds the refine-mode section. Drafter MUST
  preserve all answered QUESTION-N blocks and the frontmatter exactly,
  may add new QUESTION-N blocks below if answers exposed new
  ambiguities, never modifies or deletes existing answers.
- tests/phase-2/intent_refine_test.sh — answers QUESTION-1, snapshots
  the spec, runs --refine, asserts the answer survived, the id is
  unchanged, the deterministic validator still passes.

Phase 2 task 4/6."
```

---

## Task 5: AI validator + `_check-approval` skill + concern-loop

**Files:**
- Create: `agentic-dev/agents/spec-validator-ai.md`
- Create: `agentic-dev/skills/_check-approval/SKILL.md`
- Create: `tests/phase-2/fixtures/spec-clean.md`
- Create: `tests/phase-2/fixtures/spec-unmeasurable-criteria.md`
- Create: `tests/phase-2/fixtures/spec-scope-incoherent.md`
- Create: `tests/phase-2/approval_gate_test.sh`

- [ ] **Step 1: Create the three test fixture specs**

Create `tests/phase-2/fixtures/spec-clean.md` with:
```markdown
---
id: 2026-05-20-clean-fixture
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-clean-fixture.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Add a /health endpoint to the API that returns 200 OK with build version.

# Scope — In

- Add a new HTTP endpoint at GET /health that returns 200 OK.

# Scope — Out (deferrals)

- Deep health checks (database connectivity, external service pings) are out of scope.

# Files in scope

- src/routes/health.ts
- tests/routes/health.test.ts

# Architectural decisions

- Response body shape: `{ "status": "ok", "version": "<build-sha>" }`.

# ADR candidates

None.

# Test strategy

Add tests for new behaviors (200 OK response, correct body shape). Existing tests must continue to pass.

# Completion criteria

- Tests in tests/routes/health.test.ts pass
- GET /health returns HTTP 200 with body matching the agreed shape
- Existing test suite passes without modification

# Diff budget

- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 3

# Sensitive paths

(inherits from config.yaml)
```

Create `tests/phase-2/fixtures/spec-unmeasurable-criteria.md` with:
```markdown
---
id: 2026-05-20-unmeasurable-fixture
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-unmeasurable-fixture.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Make the API faster.

# Scope — In

- Optimize the request-handling middleware.

# Scope — Out (deferrals)

- Database query optimization is out of scope.

# Files in scope

- src/middleware/**

# Architectural decisions

- Profile first, then optimize hot paths.

# ADR candidates

None.

# Test strategy

Add tests for new behaviors. Existing tests must continue to pass.

# Completion criteria

- The API feels responsive.
- Code is clean.
- Performance is good.

# Diff budget

- Wall clock: 60 minutes
- Diff lines: 400
- Files touched: 10

# Sensitive paths

(inherits from config.yaml)
```

Create `tests/phase-2/fixtures/spec-scope-incoherent.md` with:
```markdown
---
id: 2026-05-20-incoherent-fixture
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-incoherent-fixture.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Add rate limiting per-tenant to the API.

# Scope — In

- Update the documentation site footer to add a new link.

# Scope — Out (deferrals)

- Rate limiting is out of scope.

# Files in scope

- docs/site/footer.html

# Architectural decisions

- None.

# ADR candidates

None.

# Test strategy

Add tests for new behaviors. Existing tests must continue to pass.

# Completion criteria

- The footer renders with the new link

# Diff budget

- Wall clock: 15 minutes
- Diff lines: 20
- Files touched: 1

# Sensitive paths

(inherits from config.yaml)
```

- [ ] **Step 2: Write the failing approval-gate test**

Create `tests/phase-2/approval_gate_test.sh` with:
```bash
#!/usr/bin/env bash
# End-to-end test of the approval gate: /agentic-dev:_check-approval on each
# of the three fixtures (clean, unmeasurable, incoherent). Asserts the AI
# validator's verdict and post-conditions on the spec file.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"
FIXTURE_DIR="$REPO_ROOT/tests/phase-2/fixtures"

run_one() {
  local fixture_name="$1"
  local expected_verdict="$2"  # "clean" or "concerns"
  local expected_category="$3" # only meaningful when verdict=concerns

  TMP_PROJECT="$(mktemp -d -t agentic-approval-XXXXXX)"
  trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' RETURN

  cd "$TMP_PROJECT"
  git init -q
  git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

  claude --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --add-dir "$(dirname "$INIT_FIXTURE")" \
    -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

  mkdir -p .claude/agentic/intents .claude/agentic/specs

  # Copy the fixture into the throwaway project. The fixture references an
  # intent file path; we create a stub intent file at that path so the
  # deterministic validator's intent_path check passes.
  cp "$FIXTURE_DIR/$fixture_name" ".claude/agentic/specs/$fixture_name"
  spec_id=$(awk '/^id:/{print $2; exit}' ".claude/agentic/specs/$fixture_name")
  echo "stub" > ".claude/agentic/intents/${spec_id}.md"

  # Set approved=true in the fixture (the gate fires on the flip)
  sed -i.bak 's/^approved: false$/approved: true/' ".claude/agentic/specs/$fixture_name"
  rm -f ".claude/agentic/specs/$fixture_name.bak"

  # Run the check-approval skill
  approval_out="$TMP_PROJECT/_approval_output.txt"
  claude --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    -p "/agentic-dev:_check-approval .claude/agentic/specs/$fixture_name" >"$approval_out" 2>&1 || true

  case "$expected_verdict" in
    clean)
      if ! grep -qE 'verdict: clean' "$approval_out"; then
        echo "FAIL $fixture_name: expected verdict=clean; got:" >&2
        cat "$approval_out" >&2
        return 1
      fi
      # approved should still be true
      if ! grep -qE '^approved:\s*true' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: approved was reverted on a clean verdict" >&2
        return 1
      fi
      echo "PASS $fixture_name: verdict=clean, approved preserved"
      ;;
    concerns)
      if ! grep -qE 'verdict: concerns' "$approval_out"; then
        echo "FAIL $fixture_name: expected verdict=concerns; got:" >&2
        cat "$approval_out" >&2
        return 1
      fi
      if ! grep -qE "category: $expected_category" "$approval_out"; then
        echo "FAIL $fixture_name: expected category=$expected_category in concerns" >&2
        cat "$approval_out" >&2
        return 1
      fi
      # approved should have been reverted to false
      if ! grep -qE '^approved:\s*false' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: approved was NOT reverted on a concerns verdict" >&2
        return 1
      fi
      # New QUESTION-N block(s) should have been written
      if ! grep -qE '<!-- QUESTION-[0-9]+ ' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: no new QUESTION-N block was added on a concerns verdict" >&2
        return 1
      fi
      echo "PASS $fixture_name: verdict=concerns, approved reverted, new QUESTION added"
      ;;
  esac
}

run_one spec-clean.md clean ""
run_one spec-unmeasurable-criteria.md concerns completion-criterion
run_one spec-scope-incoherent.md concerns scope-coherence

echo "approval_gate_test: OK"
```

Make it executable:
```bash
chmod +x tests/phase-2/approval_gate_test.sh
```

- [ ] **Step 3: Run the test, confirm it fails**

Run:
```bash
bash tests/phase-2/approval_gate_test.sh; echo "exit: $?"
```

Expected: failures because neither `_check-approval` nor the AI validator exists yet; exit 1.

- [ ] **Step 4: Implement the AI validator subagent**

Create `agentic-dev/agents/spec-validator-ai.md` with:
````markdown
---
name: spec-validator-ai
description: Read-only judgment validator for approved specs. Checks measurability of completion criteria and scope coherence. Returns a structured verdict; never edits files.
tools: Read, Glob, Grep
---

You are the agentic-dev AI spec validator. You read a spec file and judge two things:

1. **Measurability** — each completion criterion must describe an observable outcome that an automated check could verify without human judgment. "Tests in `tests/foo/` pass" is measurable. "The system feels responsive" is not. "Code is clean" is not. "API returns 429 when limit exceeded" is measurable.

2. **Scope coherence** — does the in-scope list describe work that fits the intent? Does the out-of-scope list contradict the intent (e.g., intent says "rate limiting", out-of-scope says "rate limiting")?

You are read-only — you must NOT use Write, Edit, or any mutating Bash command. Your output is a single JSON object as plain text (no code fences).

## Output contract

Respond with EXACTLY this JSON shape, nothing else:

```
{
  "verdict": "clean" | "concerns",
  "concerns": [
    {
      "category": "completion-criterion" | "scope-coherence",
      "section": "<the section heading where the concern lives>",
      "criterion_index": <integer | null>,
      "explanation": "<one or two sentences>",
      "suggested_question": "<the full QUESTION-N body the invoking skill should insert>"
    }
  ]
}
```

`concerns` is an empty array if `verdict` is `clean`. Otherwise it contains one or more concern objects.

`suggested_question` is the full text of a `QUESTION-N` block — but DO NOT include the `<!-- QUESTION-N` marker; the invoking skill assigns the number. Use this format inside `suggested_question`:

```
(<category>)
**Q:** <question>

**Why this matters:** <one or two sentences>

**Options:**
- A. <option>
- B. <option>
- C. <option>

**Your answer:** [REPLACE THIS LINE with A, B, C, or your own text]
```

`section` is the markdown heading text under which the new QUESTION should be inserted (e.g., "Completion criteria", "Scope — In", "Scope — Out").

`criterion_index` is the 1-based index of the offending criterion when `category` is `completion-criterion`, or null otherwise.

## Examples

A spec with completion criterion "the system feels responsive" should produce:

```json
{
  "verdict": "concerns",
  "concerns": [
    {
      "category": "completion-criterion",
      "section": "Completion criteria",
      "criterion_index": 1,
      "explanation": "Criterion 1 'the system feels responsive' has no observable predicate — there is no automated check that can verify 'feels responsive'.",
      "suggested_question": "(completion-criteria)\n**Q:** What specific latency target defines 'responsive' for this work?\n\n**Why this matters:** Without a measurable target, the implementer cannot know when the work is done.\n\n**Options:**\n- A. p50 < 100ms on the existing benchmark suite\n- B. p95 < 200ms on the existing benchmark suite\n- C. Other (specify)\n\n**Your answer:** [REPLACE THIS LINE with A, B, C, or your own text]"
    }
  ]
}
```

A clean spec produces:

```json
{
  "verdict": "clean",
  "concerns": []
}
```

## Do NOT

- Do not include any preamble, commentary, or explanation outside the JSON.
- Do not wrap the JSON in code fences.
- Do not edit any file. You are pure judgment.
- Do not invent concerns where none exist. A spec with measurable criteria and coherent scope is `clean`; say so.
````

- [ ] **Step 5: Implement the `_check-approval` skill**

Create `agentic-dev/skills/_check-approval/SKILL.md` with:
````markdown
---
description: Internal skill triggered after deterministic validation passes on an approved spec. Dispatches the spec-validator-ai subagent. On concerns, writes new QUESTION-N blocks back into the spec and reverts approved to false. v0.2 requires the user to invoke this explicitly after deterministic validation passes; future versions may auto-fire from the hook.
---

# /agentic-dev:_check-approval

You are the orchestrator for the AI half of the spec validator. You should be invoked explicitly after the deterministic validator (run via the PostToolUse hook on save) reports `state: approved`. The validator script prints a "Next: run /agentic-dev:_check-approval <spec-path>" instruction; this skill is the response to that instruction.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the path to the spec file to validate. If empty, print `agentic-dev: /agentic-dev:_check-approval requires a spec file path. Example: /agentic-dev:_check-approval .claude/agentic/specs/2026-05-20-x.md` and exit.

## Pre-checks

1. The spec file exists and matches `.claude/agentic/specs/*.md`. If not, print an error and exit.
2. Read the frontmatter to confirm `approved: true`. If `approved: false`, print `agentic-dev: spec is not approved (approved: false); nothing to validate` and exit.
3. Run the deterministic validator to ensure mechanical correctness: `bash agentic-dev/bin/validate-spec.sh <spec-path>`. If it exits non-zero, print the validator's output and exit — the AI validator only runs after deterministic checks pass.

## Dispatch the AI validator

Read the spec file contents. Use the Agent tool (subagent_type: spec-validator-ai) with this prompt:

```
Validate the following spec for measurability of completion criteria and scope coherence. Output the JSON verdict per your output contract.

spec_path: <path>

spec_body:
<full file contents>
```

## Parse the verdict

The AI validator returns a JSON object. Parse it. If parsing fails (the output is not valid JSON or doesn't match the expected shape), print:
- `agentic-dev: AI validator returned malformed output; logging to .claude/agentic/validation-log.txt`
- Append the malformed output and a timestamp to `.claude/agentic/validation-log.txt` using Write (or append with Bash if the file already exists).
- Leave `approved: true` (do not revert). Exit.

## On verdict: clean

Print:
```
agentic-dev: AI validator verdict: clean
  spec: <path>
  status: approved (no concerns)
```

Append a single line to `.claude/agentic/validation-log.txt`:
```
<ISO-8601 UTC timestamp> | <spec-id> | clean
```

Do NOT modify the spec file.

## On verdict: concerns

For each concern in the `concerns` array:

1. Determine the highest existing QUESTION-N number in the spec. Find it with a grep for `<!-- QUESTION-N` markers and parse out the integer.
2. Compute the new N = highest + 1 (or 1 if there are no existing QUESTIONs).
3. Build the new QUESTION block text:
   ```
   <!-- QUESTION-<N> <category-from-suggested_question> -->
   **Q:** <from suggested_question>
   ... rest of the suggested_question content as-is ...
   ```
4. Locate the section heading named in `concern.section` in the spec. Insert the new QUESTION block immediately below that heading and any existing content under it (i.e., at the end of that section's body, before the next `# ` heading).
5. Add a comment marker above the new block on first concern of this round:
   ```
   <!-- spec-validator-ai found new ambiguities; resolve before re-approval -->
   ```

After processing all concerns:
- Set `approved: false` in the frontmatter using the Edit tool.
- Append to `.claude/agentic/validation-log.txt`:
  ```
  <ISO-8601 UTC timestamp> | <spec-id> | concerns | <count> | <categories joined by ;>
  ```
- Print:
  ```
  agentic-dev: AI validator verdict: concerns
    spec: <path>
    concerns: <count>
    categories: <comma-separated>
    action: approved reverted to false; new QUESTION-N blocks added
  Resolve the new questions and re-approve.
  ```

## Do NOT

- Do not modify the spec body outside what's specified above (no rewording, no auto-answering, no removing prior content).
- Do not invoke the drafter — only the AI validator subagent.
- Do not commit anything.
````

- [ ] **Step 6: Run the approval-gate test, confirm all three fixtures behave correctly**

Run:
```bash
bash tests/phase-2/approval_gate_test.sh; echo "exit: $?"
```

Expected: `PASS spec-clean.md: verdict=clean, approved preserved`, `PASS spec-unmeasurable-criteria.md: verdict=concerns, approved reverted, new QUESTION added`, `PASS spec-scope-incoherent.md: verdict=concerns, approved reverted, new QUESTION added`; `approval_gate_test: OK`; exit 0.

If the AI validator returns concerns for spec-clean.md (false positive), tighten the validator's "do not invent concerns" instruction and the examples. If it returns clean for a fixture that should have concerns (false negative), strengthen the relevant judgment criterion in the prompt.

- [ ] **Step 7: Commit**

Run:
```bash
git add agentic-dev/agents/spec-validator-ai.md agentic-dev/skills/_check-approval tests/phase-2/fixtures tests/phase-2/approval_gate_test.sh
git commit -m "feat(phase-2): AI validator + _check-approval skill + concern-loop

- agents/spec-validator-ai.md — read-only AI validator subagent. Two
  judgment checks: measurability of completion criteria, and scope
  coherence between intent and the in/out-of-scope lists. Returns a
  structured JSON verdict with concerns including suggested_question
  text the orchestrating skill can drop in as new QUESTION-N blocks.
- skills/_check-approval/SKILL.md — orchestrator. Validates the
  spec-path argument, runs the deterministic validator first, then
  dispatches spec-validator-ai. On clean verdict: leave the spec
  alone, log to validation-log.txt. On concerns: insert new QUESTION-N
  blocks at the right section headings, revert approved: true ->
  false, log with categories.
- tests/phase-2/fixtures/spec-clean.md — a spec with measurable
  completion criteria and coherent scope. Expected verdict: clean.
- tests/phase-2/fixtures/spec-unmeasurable-criteria.md — completion
  criteria like 'system feels responsive' and 'code is clean'.
  Expected verdict: concerns with category completion-criterion.
- tests/phase-2/fixtures/spec-scope-incoherent.md — intent says
  'rate limiting' but in-scope and out-of-scope both contradict it.
  Expected verdict: concerns with category scope-coherence.
- tests/phase-2/approval_gate_test.sh — end-to-end across all three
  fixtures, asserting verdict, approved-flag state post-validation,
  and presence of new QUESTION-N blocks on concern verdicts.

Phase 2 task 5/6."
```

---

## Task 6: Aggregator + README + CHANGELOG + completion checklist

**Files:**
- Create: `tests/phase-2/run_all.sh`
- Modify: `agentic-dev/README.md`
- Modify: `agentic-dev/CHANGELOG.md`

- [ ] **Step 1: Create the phase-2 test aggregator**

Create `tests/phase-2/run_all.sh` with:
```bash
#!/usr/bin/env bash
# Run all Phase 2 tests in order. Exit non-zero on any failure.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== spec_schema_test ==="
python3 "$DIR/spec_schema_test.py"

echo
echo "=== validate_spec_test ==="
python3 "$DIR/validate_spec_test.py"

echo
echo "=== intent_fresh_test ==="
bash "$DIR/intent_fresh_test.sh"

echo
echo "=== hook_test ==="
bash "$DIR/hook_test.sh"

echo
echo "=== intent_refine_test ==="
bash "$DIR/intent_refine_test.sh"

echo
echo "=== approval_gate_test ==="
bash "$DIR/approval_gate_test.sh"

echo
echo "All Phase 2 tests passed."
```

Make it executable:
```bash
chmod +x tests/phase-2/run_all.sh
```

- [ ] **Step 2: Update the plugin README**

Replace the `## Skills shipped in v0.1` section in `agentic-dev/README.md` with:

```markdown
## Skills shipped

### v0.1
- `/agentic-dev:init` — bootstrap `.claude/agentic/` in the current project
- `/agentic-dev:status` — show current state

### v0.2
- `/agentic-dev:intent <free-form goal>` — draft a structured spec for a new goal. Produces an intent file and a spec file with explicit QUESTION-N blocks at every architectural decision.
- `/agentic-dev:intent --refine <spec-path>` — re-run the drafter on a partially-answered spec. Preserves existing answers; may add new questions if answers exposed ambiguities.
- `/agentic-dev:_check-approval <spec-path>` — run the AI validator on an approved spec. Two checks: measurability of completion criteria, scope coherence with the intent. Concerns are written back into the spec as new QUESTION-N blocks (no silent rejection); `approved` reverts to `false`.
```

Replace the `## What's coming next` section with:

```markdown
## What's coming next

See repo issues / phase plans for P3 onward: implementer subagent with worktree isolation (P3), deterministic gates and hook wiring for scope/budget/sensitive-paths (P4), hardened reviewer + Telegram notifications (P5), overnight queue + circuit breaker (P6), cross-session memory (P7), marketplace polish + community submission (P8).
```

- [ ] **Step 3: Update the CHANGELOG**

Insert a new entry at the top of `agentic-dev/CHANGELOG.md` (immediately after the title block, before the `## [0.1.0]` entry):

```markdown
## [0.2.0] — 2026-05-20

Spec drafting layer ships. Implementation is still not automated — the implementer subagent lands in P3.

### Added
- `/agentic-dev:intent <text>` — drafts a structured spec for a new goal. Produces a verbatim intent file plus a spec markdown with explicit QUESTION-N blocks for every architectural decision.
- `/agentic-dev:intent --refine <spec-path>` — re-runs the drafter on a partial spec; preserves existing answers; may add new questions.
- `/agentic-dev:_check-approval <spec-path>` — runs the AI validator on approved specs. Concerns become new QUESTION-N blocks; `approved` reverts to false. Clean verdicts leave the spec untouched.
- `agents/spec-drafter.md` — drafter subagent with a fixed calibration table (anti-eagerness: forbidden from improvising; defaults to flag).
- `agents/spec-validator-ai.md` — read-only AI validator subagent. Judges measurability and scope coherence.
- `bin/validate-spec.sh` — deterministic validator. Fires via PostToolUse hook on every spec save. Mechanical checks only: frontmatter complete, schema_version matches, intent_path resolves, no unresolved QUESTION blocks when approved=true, budget values are positive integers.
- `hooks/hooks.json` — PostToolUse hook wiring for the deterministic validator.
- `schemas/spec.schema.json` — spec frontmatter schema with id pattern, date-time format, and required fields.
- `tests/phase-2/` — six tests covering schema validation, deterministic validator unit cases, fresh-intent end-to-end, hook firing, --refine preservation, and the full approval gate across three adversarial fixtures (clean, unmeasurable criteria, incoherent scope).

### Notes
- Approval flow is explicit in v0.2: the user must run `/agentic-dev:_check-approval` after the deterministic validator emits its next-step instruction. Auto-firing from the hook is deferred (one-line hooks.json change when chosen).
- P1-DEF-001 (queue goal schema extension strategy) remains deferred. P2 still does not touch queue.yaml.
```

- [ ] **Step 4: Run the full Phase 2 suite**

Source the env file then run:
```bash
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"
bash tests/phase-2/run_all.sh
```

Expected: each section's PASS lines followed by `All Phase 2 tests passed.`; exit 0.

- [ ] **Step 5: Run both phase suites to confirm no regression**

Run:
```bash
bash tests/phase-1/run_all.sh
echo "---"
bash tests/phase-2/run_all.sh
```

Expected: both exit 0; P1 still 36 PASS lines + "All Phase 1 tests passed."; P2 prints "All Phase 2 tests passed."

- [ ] **Step 6: Final commit closing out Phase 2**

Run:
```bash
git add tests/phase-2/run_all.sh agentic-dev/README.md agentic-dev/CHANGELOG.md
git commit -m "docs(phase-2): aggregator + README + CHANGELOG for v0.2.0

- tests/phase-2/run_all.sh — runs all six Phase 2 tests in order
  (schema → deterministic validator unit → fresh intent E2E → hook →
  refine → approval gate). Prints 'All Phase 2 tests passed.' on
  success.
- agentic-dev/README.md — adds v0.2 skills section documenting
  /agentic-dev:intent, --refine mode, and _check-approval. Updates
  the 'What's coming next' section with the P3–P8 outline.
- agentic-dev/CHANGELOG.md — v0.2.0 entry. Records what's shipped
  (drafter + AI validator + concern-loop) and the explicit notes
  (approval requires explicit _check-approval invocation in v0.2;
  P1-DEF-001 still deferred).

Phase 2 task 6/6 — Phase 2 complete."
```

---

## Phase 2 Completion Checklist

When P2 is done, all of the following must hold:

- [ ] `bash tests/phase-2/run_all.sh` exits 0 from a fresh clone
- [ ] `bash tests/phase-1/run_all.sh` still exits 0 (no P1 regression)
- [ ] Running `/agentic-dev:intent "<text>"` in a fresh init'd project creates `.claude/agentic/intents/<id>.md` and `.claude/agentic/specs/<id>.md` with QUESTION-N blocks and `approved: false`
- [ ] The deterministic validator runs automatically on spec edits (PostToolUse hook) and emits clear messages
- [ ] `/agentic-dev:intent --refine <spec-path>` preserves the human's existing answers and never overwrites them
- [ ] Setting `approved: true` while QUESTION-N blocks remain triggers a `spec validation failed` message from the deterministic validator
- [ ] `/agentic-dev:_check-approval` on a clean approved spec returns `verdict: clean` and leaves `approved: true`
- [ ] `/agentic-dev:_check-approval` on a spec with unmeasurable criteria returns `verdict: concerns`, reverts `approved: false`, and adds new QUESTION-N blocks
- [ ] All six Phase 2 tasks' commits are on the branch; `git log --oneline` shows them in order
- [ ] `agentic-dev/CHANGELOG.md` records v0.2.0

## Out of scope for Phase 2 (deferred to later phases)

- Implementer subagent (P3)
- Worktree-per-session isolation in tests (P3)
- Queue goal schema extension (P1-DEF-001 — still deferred, becomes urgent in P3 or P6 when goal items first get new fields)
- Deterministic gates beyond spec validation (P4 — scope, budget, sensitive-path enforcement on diffs)
- Hardened reviewer subagent (P5)
- Telegram notifications on approval flips or AI validator concerns (P5)
- Auto-firing the AI validator from the deterministic hook (one-line hooks.json change; deferred until v0.2 feedback says it's needed)
- Custom prompt overrides via `prompts/` directory (deferred until per-project prompt tuning has a real use case, likely P5)
