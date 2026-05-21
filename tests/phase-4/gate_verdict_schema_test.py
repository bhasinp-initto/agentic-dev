"""Validate gate-verdict fixtures against gate-verdict.schema.json."""
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
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "gate-verdict.schema.json"
FIX = REPO_ROOT / "tests" / "phase-4" / "fixtures"


def main():
    results = []

    if not SCHEMA.exists():
        print(f"FAIL gate-verdict-positive: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())
    good = json.loads((FIX / "sample-verdict.json").read_text())

    # Positive: valid sample-verdict.json
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS gate-verdict-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL gate-verdict-positive: {e.message}")
        results.append(False)

    # Negative: bad overall enum
    bad_overall = json.loads(json.dumps(good))
    bad_overall["overall"] = "unknown"
    try:
        jsonschema.validate(bad_overall, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL gate-verdict-bad-overall: bad overall enum wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS gate-verdict-bad-overall")
        results.append(True)

    # Negative: bad gates[].result enum
    bad_gate_result = json.loads(json.dumps(good))
    bad_gate_result["gates"][0]["result"] = "maybe"
    try:
        jsonschema.validate(bad_gate_result, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL gate-verdict-bad-gate-result: bad gate result enum wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS gate-verdict-bad-gate-result")
        results.append(True)

    # Negative: missing required field (goal_id)
    missing = {k: v for k, v in good.items() if k != "goal_id"}
    try:
        jsonschema.validate(missing, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL gate-verdict-missing-goal-id: wrongly validated without goal_id")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS gate-verdict-missing-goal-id")
        results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
