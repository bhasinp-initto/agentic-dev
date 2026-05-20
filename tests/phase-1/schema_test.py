"""Validate sample fixtures against the plugin's JSON Schemas."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
    # Required for format_checker to actually enforce date-time:
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(
        f"ERROR: missing dependency ({e.name}). Install with: "
        "pip install -r tests/requirements.txt",
        file=sys.stderr,
    )
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
        jsonschema.validate(
            instance=data,
            schema=schema,
            format_checker=jsonschema.FormatChecker(),
        )
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

    bad_state = {
        "schema_version": "0.1",
        "circuit_breaker": {"state": "nonsense"},
        "current_goal": None,
        "last_updated": "2026-05-20T12:00:00Z",
    }
    schema = load_json(SCHEMA_DIR / "state.schema.json")
    try:
        jsonschema.validate(
            instance=bad_state,
            schema=schema,
            format_checker=jsonschema.FormatChecker(),
        )
        print("FAIL negative-state: bad fixture wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS negative-state")
        results.append(True)

    halted_missing_fields = {
        "schema_version": "0.1",
        "circuit_breaker": {
            "state": "halted",
            "halted_reason": None,
            "halted_at": None,
            "halted_goal_id": None,
        },
        "current_goal": None,
        "last_updated": "2026-05-20T12:00:00Z",
    }
    try:
        jsonschema.validate(
            instance=halted_missing_fields,
            schema=schema,
            format_checker=jsonschema.FormatChecker(),
        )
        print("FAIL negative-halted: halted state with null fields wrongly validated")
        results.append(False)
    except jsonschema.ValidationError:
        print("PASS negative-halted")
        results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
