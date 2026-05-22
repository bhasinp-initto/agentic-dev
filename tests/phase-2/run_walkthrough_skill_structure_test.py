"""Verify skills/_run-walkthrough/SKILL.md has required structure."""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-walkthrough" / "SKILL.md"


def main():
    failures = []

    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)
    text = SKILL.read_text()

    if not text.startswith("---\n"):
        failures.append("missing frontmatter opener")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter unparseable")
    else:
        if not re.search(r"^description:", fm_match.group(1), re.MULTILINE):
            failures.append("frontmatter missing description")

    required = [
        "$ARGUMENTS",
        "walkthrough-runner",
        "Agent tool",
        "reviewer-verdicts",
        "walkthrough-verdict.schema.json",
        "walkthrough-verdicts",
        "kickoff",
        "skipped",
        "screenshots",
        "manifest",
        "Do NOT",
        "validate",
    ]
    for phrase in required:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Must require reviewer-clean before walkthrough
    if "verdict ==" not in text and "clean" not in text:
        failures.append("missing pre-check requiring reviewer verdict clean")

    # Must handle malformed subagent response
    if "PARSE_ERROR" not in text and "malformed" not in text.lower():
        failures.append("missing malformed-output handling")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS _run-walkthrough/SKILL.md has frontmatter, $ARGUMENTS, pre-checks, walkthrough-runner dispatch, validation, Do NOT section")
    sys.exit(0)


if __name__ == "__main__":
    main()
