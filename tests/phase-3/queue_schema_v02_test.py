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
