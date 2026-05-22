"""Verify agents/walkthrough-runner.md has required structure."""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agentic-dev" / "agents" / "walkthrough-runner.md"


def main():
    failures = []

    if not AGENT.exists():
        print(f"FAIL setup: {AGENT} does not exist")
        sys.exit(1)
    text = AGENT.read_text()

    if not text.startswith("---\n"):
        failures.append("missing frontmatter opener")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter unparseable")
    else:
        fm = fm_match.group(1)
        for field in ["name:", "description:", "tools:"]:
            if not re.search(rf"^{field}", fm, re.MULTILINE):
                failures.append(f"frontmatter missing field: {field}")
        # Must declare Playwright MCP tools in the tools list
        if "mcp__playwright__" not in fm:
            failures.append("tools list missing mcp__playwright__* declarations")
        # Must NOT have Write or Edit (read-only)
        tools_line = re.search(r"^tools:\s*(.+)$", fm, re.MULTILINE)
        if tools_line:
            tools = tools_line.group(1)
            for forbidden in ["Write", "Edit", "NotebookEdit"]:
                # As a word boundary, not as a substring of "rewrite" etc.
                if re.search(rf"\b{forbidden}\b", tools):
                    failures.append(f"tools list contains forbidden mutating tool: {forbidden}")

    required_phrases = [
        "acceptance_url",
        "acceptance_criteria",
        "dev_server_command",
        "verdict",
        "skipped",
        "screenshot",
        "console error",
        "walkthrough-verdict.schema.json",
        "Playwright",
        "tear down",
        "do not",
        "do NOT install",
        "READ-ONLY",
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # Required behavior coverage
    must_describe = [
        ("skip-on-no-walkthrough", "verdict: \"skipped\""),
        ("skip-on-no-playwright", "Playwright"),
        ("dev-server-probe", "probe"),
        ("dev-server-timeout", "30s"),
        ("output-contract-no-fences", "code fences"),
    ]
    for label, phrase in must_describe:
        if phrase.lower() not in text.lower():
            failures.append(f"missing concept: {label!r} (expected mention of {phrase!r})")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print("PASS walkthrough-runner.md has frontmatter, read-only tools, Playwright MCP declarations, skip conditions, dev-server flow, output contract")
    sys.exit(0)


if __name__ == "__main__":
    main()
