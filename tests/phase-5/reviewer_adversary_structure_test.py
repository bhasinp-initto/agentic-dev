"""Verify agents/reviewer-adversary.md has required structure and content.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the agent file has the right shape and
key phrases that encode second-pass adversarial discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT = REPO_ROOT / "agentic-dev" / "agents" / "reviewer-adversary.md"


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

    # --- Second-pass framing: at least one of these phrases must appear ---
    second_pass_variants = [
        "second-pass",
        "first reviewer marked this clean",
        "first reviewer",
        "second pass",
    ]
    if not any(v.lower() in text.lower() for v in second_pass_variants):
        failures.append(
            f"missing second-pass framing; expected one of {second_pass_variants}"
        )

    # --- reviewer_role: "adversary" must be mentioned ---
    if "adversary" not in text.lower():
        failures.append('missing reviewer_role value: "adversary"')

    # --- Don't-invent / valid-verdict instruction ---
    dont_invent_variants = [
        "don't invent",
        "do not invent",
        "never invent",
        "valid verdict",
        "clean is a valid",
        "clean with",
    ]
    if not any(v.lower() in text.lower() for v in dont_invent_variants):
        failures.append(
            f"missing 'don't invent concerns' / 'valid verdict' instruction; "
            f"expected one of {dont_invent_variants}"
        )

    # --- Core required phrases (shared with primary reviewer) ---
    required_phrases = [
        "json",          # output is JSON
        "clean",         # verdict value
        "concern",       # verdict value
        "checks_run",    # output field
        "reviewer_role", # output field
        "checklist.yaml",   # P7: checklist read at dispatch
        "Read the checklist",  # P7: section heading
        "incident_ref",     # P7: checklist entry field
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # At least one of the "no preamble / no code fences" formulations
    no_preamble_variants = ["no preamble", "no code fences", "code fences"]
    if not any(v.lower() in text.lower() for v in no_preamble_variants):
        failures.append("missing required phrase about no preamble or no code fences")

    # --- Tools must NOT include mutation tools (double-check via full body scan) ---
    for forbidden_tool in ["Write", "Edit", "NotebookEdit"]:
        # Allow mentions in prohibition text but not as tool capabilities
        body_after_fm = re.sub(r"^---\n.*?\n---\n", "", text, flags=re.DOTALL)
        # If the tool name appears in the context of a "do not use" / "never use" clause, that's fine
        # But if it appears as a standalone capability word (e.g., "use Write to ..."), that's a problem.
        # Simple heuristic: forbidden tool must not appear without a negation nearby
        forbidden_used_positively = re.search(
            rf"(?<!never use )(?<!do not use )(?<!not use )(?<!never )\b{forbidden_tool}\b(?! to fix| is forbidden| is not| are not)",
            body_after_fm,
        )
        # More conservative: only flag if the word appears and is NOT in a "never/do not" sentence
        sentences_with_tool = [
            s for s in re.split(r"[.\n]", body_after_fm)
            if forbidden_tool.lower() in s.lower()
        ]
        for sentence in sentences_with_tool:
            if not re.search(r"\b(never|do not|must not|NEVER|DO NOT|not use|no)\b", sentence, re.IGNORECASE):
                failures.append(
                    f"body appears to allow forbidden tool {forbidden_tool!r} "
                    f"without prohibition (in: {sentence.strip()!r})"
                )

    # --- Focus areas that humans most often miss ---
    focus_areas = {
        "error path coverage": ["error path", "error handling", "boundary", "edge case"],
        "race conditions":     ["race condition", "race", "concurrency", "concurrent"],
        "security at boundaries": ["security", "boundary", "secret", "injection"],
        "naming inconsistencies": ["naming", "inconsisten", "future reader", "confuse"],
    }
    for area, variants in focus_areas.items():
        if not any(v.lower() in text.lower() for v in variants):
            failures.append(f"missing focus area: {area!r} (checked: {variants})")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS reviewer-adversary.md has frontmatter, read-only tools, second-pass framing, "
        "adversary role, don't-invent instruction, required phrases, focus areas"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
