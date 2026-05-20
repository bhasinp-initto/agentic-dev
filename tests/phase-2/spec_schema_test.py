"""Validate sample spec frontmatter fixtures against spec.schema.json."""
import json
import sys
from pathlib import Path

try:
    import yaml
    import jsonschema
    import rfc3339_validator  # noqa: F401
except ImportError as e:
    print(
        f"ERROR: missing dependency ({e.name}). Install with: "
        "pip install -r tests/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(2)

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "agentic-dev" / "schemas" / "spec.schema.json"
FIXTURE_DIR = REPO_ROOT / "tests" / "phase-2" / "fixtures"


def main():
    results = []

    # Positive case: well-formed frontmatter validates cleanly
    if not SCHEMA_PATH.exists():
        print(f"FAIL spec-schema-positive: schema not found at {SCHEMA_PATH}")
        results.append(False)
    else:
        schema = json.loads(SCHEMA_PATH.read_text())
        good = yaml.safe_load((FIXTURE_DIR / "sample-spec-frontmatter.yaml").read_text())
        try:
            jsonschema.validate(
                instance=good,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("PASS spec-schema-positive")
            results.append(True)
        except jsonschema.ValidationError as e:
            print(f"FAIL spec-schema-positive: {e.message}")
            results.append(False)

        # Negative case: bad schema_version is rejected
        bad_version = dict(good)
        bad_version["schema_version"] = "9.9"
        try:
            jsonschema.validate(
                instance=bad_version,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-version: bad schema_version wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-version")
            results.append(True)

        # Negative case: missing required field
        missing_id = {k: v for k, v in good.items() if k != "id"}
        try:
            jsonschema.validate(
                instance=missing_id,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-missing-id: missing id wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-missing-id")
            results.append(True)

        # Negative case: malformed created_at
        bad_date = dict(good)
        bad_date["created_at"] = "not-a-date"
        try:
            jsonschema.validate(
                instance=bad_date,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-date: malformed date wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-date")
            results.append(True)

        # Negative case: approved as string instead of boolean
        bad_approved_type = dict(good)
        bad_approved_type["approved"] = "true"
        try:
            jsonschema.validate(
                instance=bad_approved_type,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-approved-type: string approved wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-approved-type")
            results.append(True)

        # Negative case: additionalProperties violation
        with_extra = dict(good)
        with_extra["unexpected_field"] = "value"
        try:
            jsonschema.validate(
                instance=with_extra,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-extra-field: extra field wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-extra-field")
            results.append(True)

        # Negative case: created_at without timezone
        no_tz = dict(good)
        no_tz["created_at"] = "2026-05-20T15:30:00"
        try:
            jsonschema.validate(
                instance=no_tz,
                schema=schema,
                format_checker=jsonschema.FormatChecker(),
            )
            print("FAIL spec-schema-negative-no-tz: naive datetime wrongly validated")
            results.append(False)
        except jsonschema.ValidationError:
            print("PASS spec-schema-negative-no-tz")
            results.append(True)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
