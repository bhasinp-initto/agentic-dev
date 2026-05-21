"""Verify _run-gates/SKILL.md has required structure and references."""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-gates" / "SKILL.md"


def main():
    failures = []

    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)

    text = SKILL.read_text()

    # Frontmatter: must begin with ---
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener (---)")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter block unparseable (no closing ---)")
    else:
        fm_body = fm_match.group(1)
        if not re.search(r"^description:", fm_body, re.MULTILINE):
            failures.append("frontmatter missing 'description:' field")

    # Required phrases the skill body must reference
    required_phrases = [
        "$ARGUMENTS",       # how goal-id is passed in
        "run-gates.sh",     # the underlying script called
        "manifest",         # manifest existence pre-check
        "verdict",          # the output artifact
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Must document the refuse-if-empty case
    if "empty" not in text.lower() and "refuse" not in text.lower() and "required" not in text.lower():
        failures.append("no documentation for refusing empty $ARGUMENTS")

    # Must mention the manifest path pre-check
    if "manifest" not in text.lower():
        failures.append("no mention of manifest pre-check")

    # Must describe internal / underscore lifecycle pattern
    if "_run-gates" not in text:
        failures.append("skill does not self-reference its own name (_run-gates)")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS _run-gates/SKILL.md has required structure and references")
    sys.exit(0)


if __name__ == "__main__":
    main()
