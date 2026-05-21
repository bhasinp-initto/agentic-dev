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
