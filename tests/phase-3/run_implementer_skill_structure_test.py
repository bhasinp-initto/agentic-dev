"""Verify _run-implementer/SKILL.md has required structure."""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-implementer" / "SKILL.md"


def main():
    failures = []
    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)
    text = SKILL.read_text()

    # Frontmatter
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener")
    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter unparseable")
    else:
        if not re.search(r"^description:", fm_match.group(1), re.MULTILINE):
            failures.append("frontmatter missing description")

    # Required steps / concepts
    required_phrases = [
        "$ARGUMENTS",
        "spec path",
        "approved",
        "worktree-init",
        "kickoff",
        "implementer-strict",
        "Agent tool",
        "manifest",
        "manifest.schema.json",
        "diff-envelope",
        "validate",
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Pre-checks for unapproved spec
    if "approved: false" not in text.lower() and "not approved" not in text.lower():
        failures.append("no pre-check for unapproved spec")

    # Error path documented
    if "malformed" not in text.lower() and "invalid manifest" not in text.lower():
        failures.append("no error path for invalid manifest")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS _run-implementer/SKILL.md has required structure and references")
    sys.exit(0)


if __name__ == "__main__":
    main()
