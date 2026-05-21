"""Validate checklist.schema.json against positive and negative fixtures."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
except ImportError as e:
    print(
        f"ERROR: missing dependency ({e.name}). Install with: "
        "pip install -r tests/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "agentic-dev" / "schemas" / "checklist.schema.json"
FIXTURE_PATH = REPO_ROOT / "tests" / "phase-7" / "fixtures" / "sample-checklist.yaml"

PASS = 0
FAIL = 0


def load_schema():
    with SCHEMA_PATH.open() as f:
        return json.load(f)


def check(name: str, data: dict, schema: dict, expect_valid: bool) -> None:
    global PASS, FAIL
    try:
        jsonschema.validate(instance=data, schema=schema,
                            format_checker=jsonschema.FormatChecker())
        valid = True
    except jsonschema.ValidationError:
        valid = False

    if valid == expect_valid:
        print(f"PASS {name}")
        PASS += 1
    else:
        verdict = "valid" if valid else "invalid"
        expected = "valid" if expect_valid else "invalid"
        print(f"FAIL {name}: got {verdict}, expected {expected}")
        FAIL += 1


def main():
    if not SCHEMA_PATH.exists():
        print(f"FAIL setup: schema not found at {SCHEMA_PATH}", file=sys.stderr)
        sys.exit(1)
    if not FIXTURE_PATH.exists():
        print(f"FAIL setup: fixture not found at {FIXTURE_PATH}", file=sys.stderr)
        sys.exit(1)

    schema = load_schema()

    # ── Positive: fixture must validate ──────────────────────────────────────────
    with FIXTURE_PATH.open() as f:
        good = yaml.safe_load(f)
    check("positive-fixture", good, schema, expect_valid=True)

    # ── Positive: empty entries array is valid ────────────────────────────────────
    check(
        "positive-empty-entries",
        {"schema_version": "0.1", "entries": []},
        schema,
        expect_valid=True,
    )

    # ── Negative 1: missing required field (caught_by absent) ────────────────────
    check(
        "negative-missing-caught-by",
        {
            "schema_version": "0.1",
            "entries": [
                {
                    "date": "2026-05-21",
                    "incident_ref": "ESC-001",
                    "rule": "Always check tenant scope on every raw DB query",
                }
            ],
        },
        schema,
        expect_valid=False,
    )

    # ── Negative 2: bad enum value for caught_by ─────────────────────────────────
    check(
        "negative-bad-caught-by-enum",
        {
            "schema_version": "0.1",
            "entries": [
                {
                    "date": "2026-05-21",
                    "incident_ref": "ESC-002",
                    "rule": "Always check tenant scope on every raw DB query",
                    "caught_by": "robot",
                }
            ],
        },
        schema,
        expect_valid=False,
    )

    # ── Negative 3: additionalProperties violation ────────────────────────────────
    check(
        "negative-additional-property",
        {
            "schema_version": "0.1",
            "entries": [
                {
                    "date": "2026-05-21",
                    "incident_ref": "ESC-003",
                    "rule": "Always check tenant scope on every raw DB query",
                    "caught_by": "human",
                    "extra_field": "not allowed",
                }
            ],
        },
        schema,
        expect_valid=False,
    )

    print()
    print(f"Results: {PASS} passed, {FAIL} failed")
    sys.exit(0 if FAIL == 0 else 1)


if __name__ == "__main__":
    main()
