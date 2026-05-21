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
