"""Config schema accepts optional review.codex_adversary; rejects bad values."""
import json
import sys
from pathlib import Path

import jsonschema
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "config.schema.json"


def base_config():
    return {
        "schema_version": "0.1",
        "project": {"name": "demo", "primary_language": "python"},
        "commands": {"test": "pytest", "lint": "ruff check ."},
        "budgets": {
            "wall_clock_minutes_per_goal": 30,
            "diff_lines_per_goal": 400,
            "files_touched_per_goal": 20,
        },
        "sensitive_paths": [],
        "push_policy": "hold",
    }


def check(name, cfg, should_pass):
    schema = json.loads(SCHEMA.read_text())
    try:
        jsonschema.validate(cfg, schema)
        ok = True
    except jsonschema.ValidationError:
        ok = False
    passed = ok == should_pass
    print(f"{'PASS' if passed else 'FAIL'} {name}")
    return passed


def main():
    results = []

    cfg = base_config()  # no review block at all
    results.append(check("no-review-block-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "auto"}
    results.append(check("review-auto-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "off"}
    results.append(check("review-off-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "sometimes"}
    results.append(check("review-bad-enum-rejected", cfg, False))

    cfg = base_config()
    cfg["review"] = {"unknown_key": True}
    results.append(check("review-unknown-key-rejected", cfg, False))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
