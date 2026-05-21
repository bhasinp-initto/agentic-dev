"""Validate escalation-packet fixtures against escalation-packet.schema.json."""
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
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "escalation-packet.schema.json"
FIX = REPO_ROOT / "tests" / "phase-5" / "fixtures"


def main():
    results = []

    if not SCHEMA.exists():
        print(f"FAIL escalation-packet-positive: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())
    good = json.loads((FIX / "sample-escalation-packet.json").read_text())

    # Positive: valid sample-escalation-packet.json
    try:
        jsonschema.validate(good, schema, format_checker=jsonschema.FormatChecker())
        print("PASS escalation-packet-positive")
        results.append(True)
    except jsonschema.ValidationError as e:
        print(f"FAIL escalation-packet-positive: {e.message}")
        results.append(False)

    # Negative: bad trigger enum
    bad_trigger = json.loads(json.dumps(good))
    bad_trigger["trigger"] = "unknown_trigger"
    try:
        jsonschema.validate(bad_trigger, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL escalation-packet-bad-trigger: bad trigger enum wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS escalation-packet-bad-trigger")
        results.append(True)

    # Negative: missing required field (summary)
    missing = {k: v for k, v in good.items() if k != "summary"}
    try:
        jsonschema.validate(missing, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL escalation-packet-missing-summary: wrongly validated without summary")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS escalation-packet-missing-summary")
        results.append(True)

    # Negative: bad date-time format for generated_at
    bad_datetime = json.loads(json.dumps(good))
    bad_datetime["generated_at"] = "2026-05-21 14:46:00"  # missing T and Z — not ISO 8601 date-time
    try:
        jsonschema.validate(bad_datetime, schema, format_checker=jsonschema.FormatChecker())
        print("FAIL escalation-packet-bad-datetime: bad generated_at format wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS escalation-packet-bad-datetime")
        results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
