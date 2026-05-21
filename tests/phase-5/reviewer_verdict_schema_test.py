"""Validate reviewer-verdict fixtures against reviewer-verdict.schema.json."""
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
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "reviewer-verdict.schema.json"
FIX = REPO_ROOT / "tests" / "phase-5" / "fixtures"


def main():
    results = []

    if not SCHEMA.exists():
        print(f"FAIL reviewer-verdict-positive: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())
    good = json.loads((FIX / "sample-reviewer-verdict-clean.json").read_text())

    # Positive: valid sample-reviewer-verdict-clean.json
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS reviewer-verdict-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL reviewer-verdict-positive: {e.message}")
        results.append(False)

    # Negative: bad verdict enum
    bad_verdict = json.loads(json.dumps(good))
    bad_verdict["verdict"] = "uncertain"
    try:
        jsonschema.validate(bad_verdict, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL reviewer-verdict-bad-verdict: bad verdict enum wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS reviewer-verdict-bad-verdict")
        results.append(True)

    # Negative: missing required field (reviewer_role)
    missing = {k: v for k, v in good.items() if k != "reviewer_role"}
    try:
        jsonschema.validate(missing, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL reviewer-verdict-missing-reviewer-role: wrongly validated without reviewer_role")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS reviewer-verdict-missing-reviewer-role")
        results.append(True)

    # Negative: bad date-time format for reviewed_at
    bad_datetime = json.loads(json.dumps(good))
    bad_datetime["reviewed_at"] = "2026-05-21 14:30:00"  # missing T and Z — not ISO 8601 date-time
    try:
        jsonschema.validate(bad_datetime, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL reviewer-verdict-bad-datetime: bad reviewed_at format wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS reviewer-verdict-bad-datetime")
        results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
