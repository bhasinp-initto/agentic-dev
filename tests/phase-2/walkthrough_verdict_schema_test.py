"""Validate walkthrough-verdict.schema.json against hand-authored fixtures.

Deterministic; zero claude -p.
"""
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
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "walkthrough-verdict.schema.json"


def fixture_clean():
    return {
        "schema_version": "0.1",
        "goal_id": "2026-05-22-add-watchlist-page",
        "walked_at": "2026-05-22T11:14:00Z",
        "verdict": "clean",
        "dev_server": {
            "command": "npm run dev",
            "started_by_walkthrough": True,
            "url_reachable": True,
        },
        "criteria_results": [
            {"criterion": "Open / and verify header text 'TradingView'",
             "outcome": "pass",
             "evidence": "Header element with text 'TradingView' found at top of page",
             "screenshot_path": ".claude/agentic/walkthrough-screenshots/2026-05-22-add-watchlist-page/00-initial.png"},
            {"criterion": "Click 'Watchlist' in sidebar; verify URL is /watchlist",
             "outcome": "pass",
             "evidence": "URL after click: http://localhost:5173/watchlist",
             "screenshot_path": ".claude/agentic/walkthrough-screenshots/2026-05-22-add-watchlist-page/01-click-watchlist.png"},
        ],
        "console_errors_count": 0,
        "console_errors_sample": [],
        "artifacts": [
            {"kind": "screenshot",
             "path": ".claude/agentic/walkthrough-screenshots/2026-05-22-add-watchlist-page/00-initial.png"},
        ],
        "duration_ms": 12340,
    }


def fixture_skipped():
    return {
        "schema_version": "0.1",
        "goal_id": "2026-05-22-add-rate-limiter",
        "walked_at": "2026-05-22T11:14:00Z",
        "verdict": "skipped",
        "skip_reason": "no walkthrough section in spec",
        "dev_server": None,
        "criteria_results": [],
        "console_errors_count": 0,
        "artifacts": [],
    }


def fixture_concern():
    return {
        "schema_version": "0.1",
        "goal_id": "2026-05-22-add-watchlist-page",
        "walked_at": "2026-05-22T11:14:00Z",
        "verdict": "concern",
        "dev_server": {
            "command": "npm run dev",
            "started_by_walkthrough": True,
            "url_reachable": True,
        },
        "criteria_results": [
            {"criterion": "Click 'Watchlist' in sidebar; verify URL is /watchlist",
             "outcome": "fail",
             "evidence": "URL after click: http://localhost:5173/ (did not navigate)",
             "screenshot_path": None},
        ],
        "console_errors_count": 3,
        "console_errors_sample": [
            "TypeError: Cannot read property 'map' of undefined",
            "Failed to fetch /api/watchlist: 500",
            "Warning: Each child in a list should have a unique key prop.",
        ],
        "artifacts": [],
        "duration_ms": 8221,
    }


def main():
    if not SCHEMA.exists():
        print(f"FAIL setup: schema not found at {SCHEMA}")
        sys.exit(1)

    schema = json.loads(SCHEMA.read_text())
    results = []

    def check(name, obj, should_validate):
        try:
            jsonschema.validate(obj, schema, format_checker=jsonschema.FormatChecker())
            ok = True
        except jsonschema.ValidationError as e:
            ok = False
            err = str(e.message)
        if ok == should_validate:
            print(f"PASS {name}")
            results.append(True)
        else:
            if not ok:
                print(f"FAIL {name}: validation error: {err}")
            else:
                print(f"FAIL {name}: expected schema rejection, got success")
            results.append(False)

    # Positive cases
    check("verdict-clean-positive", fixture_clean(), True)
    check("verdict-skipped-positive", fixture_skipped(), True)
    check("verdict-concern-positive", fixture_concern(), True)

    # Negative: bad verdict enum
    bad = fixture_clean()
    bad["verdict"] = "kindasorta"
    check("rejects-bad-verdict-enum", bad, False)

    # Negative: bad criteria outcome enum
    bad = fixture_concern()
    bad["criteria_results"][0]["outcome"] = "maybe"
    check("rejects-bad-criterion-outcome", bad, False)

    # Negative: missing required top-level field (artifacts)
    bad = fixture_clean()
    del bad["artifacts"]
    check("rejects-missing-artifacts", bad, False)

    # Negative: bad date-time format
    bad = fixture_clean()
    bad["walked_at"] = "not-a-date"
    check("rejects-bad-datetime", bad, False)

    # Negative: console_errors_count negative
    bad = fixture_clean()
    bad["console_errors_count"] = -1
    check("rejects-negative-console-errors", bad, False)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
