"""Verify implementer-strict.md has required structure and content.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the agent file has the right shape and
key phrases that encode anti-eagerness discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agentic-dev" / "agents" / "implementer-strict.md"


def main():
    failures = []

    if not AGENT.exists():
        print(f"FAIL setup: {AGENT} does not exist")
        sys.exit(1)
    text = AGENT.read_text()

    # Frontmatter present
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener")

    # Required frontmatter fields
    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter not parseable")
    else:
        fm = fm_match.group(1)
        for field in ["name:", "description:", "tools:"]:
            if not re.search(rf"^{field}", fm, re.MULTILINE):
                failures.append(f"frontmatter missing field: {field}")

        # Tools list: must include Read, Edit, Write, Bash, Glob, Grep
        tools_line = re.search(r"^tools:\s*(.+)$", fm, re.MULTILINE)
        if tools_line:
            tools = tools_line.group(1)
            for required in ["Read", "Edit", "Write", "Bash"]:
                if required not in tools:
                    failures.append(f"tools missing: {required}")

    # Anti-eagerness key phrases — these are load-bearing
    required_phrases = [
        "Files in scope",
        "halt with",
        "clarifying_question",
        "test-driven",
        "TDD",
        "never commit to main",
        "never push",
        "manifest",
        "out_of_spec_files",
        "do not guess",
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Calibration table must have specific rows (situations)
    situations = [
        "Files in scope",
        "outside",  # "outside Files in scope" or "outside scope"
        "spec doesn't say",
        "dependency",
        "budget",
        "test fails",
        "pre-existing",
        "wall-clock",
        "in-scope work",
    ]
    for s in situations:
        if s.lower() not in text.lower():
            failures.append(f"calibration row missing concept: {s!r}")

    # Output contract: must produce manifest as JSON object
    if "manifest" not in text.lower() or "json" not in text.lower():
        failures.append("output contract doesn't describe manifest as JSON")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS implementer-strict.md has frontmatter, tools, anti-eagerness phrases, calibration table, output contract")
    sys.exit(0)


if __name__ == "__main__":
    main()
