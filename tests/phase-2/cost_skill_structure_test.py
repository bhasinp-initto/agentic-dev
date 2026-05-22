"""Verify agentic-dev/skills/cost/SKILL.md has required structure.

Lives in tests/phase-2/ because the test cost policy treats P2 as the home
for skill structural tests in v1.x — cost/SKILL.md is a v1.2.0 addition;
moving it to a new phase-9 directory only matters if we ship a full phase
later. Deterministic; zero claude -p.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "cost" / "SKILL.md"


def main():
    failures = []

    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)
    text = SKILL.read_text()

    # Frontmatter present
    if not text.startswith("---\n"):
        failures.append("missing frontmatter opener")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter unparseable")
    else:
        if not re.search(r"^description:", fm_match.group(1), re.MULTILINE):
            failures.append("frontmatter missing description")

    # Required phrases
    required = [
        "$ARGUMENTS",
        "--since",
        "--goal",
        "console.anthropic.com",  # honesty pointer to actual billing
        "manifests",
        "verdicts",
        "reviewer-verdicts",
        "duration",
        "diff_stats",
        "subagent dispatches",
        "read-only",
        "exit code",
    ]
    for phrase in required:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Honesty disclaimer should be present
    if "CANNOT see" not in text and "cannot see" not in text:
        failures.append("missing honesty disclaimer about what the report cannot see")

    # Must declare read-only / no-subagent-dispatch
    if "No subagent dispatch" not in text and "no subagent dispatch" not in text.lower():
        failures.append("missing 'no subagent dispatch' declaration")

    # Do NOT section must exist
    if not re.search(r"#+\s*Do\s+NOT", text):
        failures.append("missing 'Do NOT' section")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS cost/SKILL.md has required structure: frontmatter, $ARGUMENTS, "
          "filters, artifact references, honesty disclaimer, read-only, Do NOT section")
    sys.exit(0)


if __name__ == "__main__":
    main()
