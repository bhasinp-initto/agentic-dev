"""Unit tests for codex_adapter.adapt() — severity/verdict/field mapping."""
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import codex_adapter as ca  # noqa: E402

import jsonschema  # noqa: E402

VERDICT_SCHEMA = json.loads(
    (REPO_ROOT / "agentic-dev" / "schemas" / "reviewer-verdict.schema.json").read_text()
)

GID = "2026-07-26-demo-goal"
TS = "2026-07-26T12:00:00Z"


def finding(sev, **kw):
    base = dict(severity=sev, title="T", body="B", file="src/a.py",
               line_start=10, line_end=12, confidence=0.8, recommendation="do X")
    base.update(kw)
    return base


def results():
    out = []

    # approve => clean, empty concerns
    v = ca.adapt({"verdict": "approve", "summary": "ok", "findings": [], "next_steps": []}, GID, TS)
    out.append(("approve->clean", v["verdict"] == "clean" and v["concerns"] == []))

    # needs-attention + critical => blocking
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("critical")], "next_steps": []}, GID, TS)
    out.append(("critical->blocking-verdict", v["verdict"] == "blocking"))
    out.append(("critical->blocking-severity", v["concerns"][0]["severity"] == "blocking"))

    # high => blocking
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("high")], "next_steps": []}, GID, TS)
    out.append(("high->blocking", v["verdict"] == "blocking"))

    # medium => concern
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("medium")], "next_steps": []}, GID, TS)
    out.append(("medium->concern-verdict", v["verdict"] == "concern"))
    out.append(("medium->concern-severity", v["concerns"][0]["severity"] == "concern"))

    # low => concern
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("low")], "next_steps": []}, GID, TS)
    out.append(("low->concern", v["concerns"][0]["severity"] == "concern"))

    # field mapping + prefix + category
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("high", file="src/z.py", line_start=42,
                                       title="Race", body="TOCTOU", recommendation="lock")],
                  "next_steps": []}, GID, TS)
    c = v["concerns"][0]
    out.append(("map-file", c["file"] == "src/z.py"))
    out.append(("map-line", c["line"] == 42))
    out.append(("category-uncategorized", c["category"] == "uncategorized"))
    out.append(("desc-prefix", c["description"].startswith("[codex-adversary] Race")))
    out.append(("desc-has-fix", "fix: lock" in c["description"]))

    # role + schema validity
    out.append(("role-adversary", v["reviewer_role"] == "adversary"))
    try:
        jsonschema.validate(v, VERDICT_SCHEMA, format_checker=jsonschema.FormatChecker())
        out.append(("schema-valid", True))
    except jsonschema.ValidationError as e:
        out.append((f"schema-valid ({e.message})", False))

    return out


def main():
    ok = True
    for name, passed in results():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
