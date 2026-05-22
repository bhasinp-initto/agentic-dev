"""Verify agents/hardened-reviewer.md has required structure and content.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the agent file has the right shape and
key phrases that encode adversarial reviewer discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agentic-dev" / "agents" / "hardened-reviewer.md"


def main():
    failures = []

    if not AGENT.exists():
        print(f"FAIL setup: {AGENT} does not exist")
        sys.exit(1)
    text = AGENT.read_text()

    # --- Frontmatter present and parseable ---
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter not parseable")
    else:
        fm = fm_match.group(1)
        for field in ["name:", "description:", "tools:"]:
            if not re.search(rf"^{field}", fm, re.MULTILINE):
                failures.append(f"frontmatter missing field: {field}")

        # Tools must include Read, Glob, Grep (and may include Bash)
        tools_line = re.search(r"^tools:\s*(.+)$", fm, re.MULTILINE)
        if tools_line:
            tools = tools_line.group(1)
            for required in ["Read", "Glob", "Grep"]:
                if required not in tools:
                    failures.append(f"tools missing required: {required}")
            # Must NOT include mutation tools
            for forbidden in ["Write", "Edit", "NotebookEdit"]:
                if forbidden in tools:
                    failures.append(f"tools must NOT include: {forbidden}")
        else:
            failures.append("tools line not found in frontmatter")

    # --- Required adversarial / structural phrases (case-insensitive) ---
    required_phrases = [
        "assume",           # adversarial framing "Assume this diff is broken"
        "broken",           # adversarial framing
        "concern",          # verdict enum value
        "json",             # output is JSON
        "clean",            # verdict enum value "clean"
        "mechanical",       # concern category
        "judgment",         # concern category
        "uncategorized",    # concern category
        "checks_run",       # output field
        "reviewer_role",    # output field
        "do not invent",    # "never invent concerns" instruction
        "checklist.yaml",   # P7: checklist informs reviewer dispatch
        "Relevant past incidents",  # 1.5.0: pre-filtered section heading injected by dispatcher
        "incident_ref",     # P7: checklist entry field
        "adversarial-pattern hints",  # P7: how checklist is applied
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # At least one of the "no preamble / no code fences" formulations
    no_preamble_variants = ["no preamble", "no code fences", "code fences"]
    if not any(v.lower() in text.lower() for v in no_preamble_variants):
        failures.append("missing required phrase about no preamble or no code fences")

    # --- Required concept coverage ---
    concepts = {
        "spec compliance":   ["spec", "files in scope", "completion criteria", "architectural"],
        "security smells":   ["security", "secret", "hard-coded", "hardcoded"],
        "scope creep":       ["scope creep", "out-of-spec", "scope drift", "beyond what the spec"],
        "test coverage":     ["test coverage", "test strategy", "coverage gap"],
    }
    for concept, variants in concepts.items():
        if not any(v.lower() in text.lower() for v in variants):
            failures.append(f"missing concept coverage: {concept!r} (checked: {variants})")

    # --- Output / behavior constraints ---
    # Must mention reviewer_role: "primary"
    if '"primary"' not in text and "primary" not in text.lower():
        failures.append('missing reviewer_role value: "primary"')

    # Must mention verdict values
    for verdict in ["blocking", "concern", "clean"]:
        if verdict not in text.lower():
            failures.append(f"missing verdict value: {verdict!r}")

    # --- Do-NOT list must be present ---
    for forbidden_action in ["write", "edit"]:
        # Look for the forbidden action in a "do not / never" context
        pattern = rf"(never|do not|must not|NEVER|DO NOT)\b.*\b{forbidden_action}\b"
        if not re.search(pattern, text, re.IGNORECASE):
            failures.append(f"missing 'do not / never' prohibition on: {forbidden_action!r}")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS hardened-reviewer.md has frontmatter, read-only tools, adversarial framing, "
        "required phrases, concept coverage, do-not list, output contract"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
