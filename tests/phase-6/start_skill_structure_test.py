"""Verify agentic-dev/skills/start/SKILL.md has required structure.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the skill file has the right shape and
key phrases that encode the /agentic-dev:start entry-point discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "start" / "SKILL.md"


def main():
    failures = []

    if not SKILL.exists():
        print(f"FAIL setup: {SKILL} does not exist")
        sys.exit(1)

    text = SKILL.read_text()

    # --- Frontmatter: must begin with --- ---
    if not text.startswith("---\n"):
        failures.append("frontmatter missing opener (---)")

    fm_match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        failures.append("frontmatter block unparseable (no closing ---)")
    else:
        fm_body = fm_match.group(1)
        if not re.search(r"^description:", fm_body, re.MULTILINE):
            failures.append("frontmatter missing 'description:' field")

        # Frontmatter description must reference key concepts
        desc_lower = fm_body.lower()
        required_desc_phrases = [
            ("--until", ["--until", "until"]),
            ("queue run", ["queue run", "entry point", "begin", "start"]),
        ]
        for label, variants in required_desc_phrases:
            if not any(v.lower() in fm_body.lower() for v in variants):
                failures.append(f"frontmatter description missing reference to: {label!r}")

    # --- $ARGUMENTS: must document optional --until ---
    if "$ARGUMENTS" not in text:
        failures.append("missing $ARGUMENTS reference")

    # --- --until option ---
    until_variants = [
        "--until",
        "until",
    ]
    if not any(v.lower() in text.lower() for v in until_variants):
        failures.append("missing --until option documentation")

    # --until must describe supported formats
    until_format_variants = [
        "HH:MM",
        "<N>m",
        "<N>h",
        "Nm",
        "Nh",
        "duration",
        "minutes",
        "hours",
    ]
    if not any(v.lower() in text.lower() for v in until_format_variants):
        failures.append(
            "missing --until format examples (HH:MM | <N>m | <N>h or duration)"
        )

    # --- Required phrases (case-insensitive) ---
    required_phrases = [
        ("circuit-breaker",    ["circuit-breaker", "circuit_breaker"]),
        ("_run-orchestrator",  ["_run-orchestrator"]),
        ("halted",             ["halted"]),
        ("/agentic-dev:resume", ["/agentic-dev:resume", "agentic-dev:resume"]),
    ]
    for label, variants in required_phrases:
        if not any(v.lower() in text.lower() for v in variants):
            failures.append(f"missing required phrase: {label!r}")

    # --- Pre-check: refuse if circuit_breaker is halted ---
    refuse_halted_variants = [
        "not halted",
        "halted",
        "refuse",
        "circuit_breaker.state",
        "circuit breaker",
    ]
    # At least the word "halted" AND a refusal must be documented
    if "halted" not in text.lower():
        failures.append("missing halted state pre-check")
    if not any(v.lower() in text.lower() for v in ["refuse", "exit 1", "suggest"]):
        failures.append("missing refusal documentation for halted state")

    # --- target_cutoff_at / decisions.log mention for --until ---
    cutoff_variants = [
        "target_cutoff_at",
        "cutoff",
        "decisions.log",
    ]
    if not any(v.lower() in text.lower() for v in cutoff_variants):
        failures.append(
            "missing target_cutoff_at or decisions.log reference for --until handling"
        )

    # --- circuit-breaker.sh running call ---
    cb_running_variants = [
        "circuit-breaker.sh running",
        "circuit-breaker running",
        "circuit_breaker running",
        "circuit-breaker.sh",
    ]
    if not any(v.lower() in text.lower() for v in cb_running_variants):
        failures.append("missing circuit-breaker.sh running call")

    # --- _run-orchestrator invocation ---
    invoke_variants = [
        "/agentic-dev:_run-orchestrator",
        "agentic-dev:_run-orchestrator",
    ]
    if not any(v.lower() in text.lower() for v in invoke_variants):
        failures.append("missing /agentic-dev:_run-orchestrator invocation")

    # --- Final summary on return ---
    summary_variants = [
        "summary",
        "print",
        "report",
        "final",
    ]
    if not any(v.lower() in text.lower() for v in summary_variants):
        failures.append("missing final summary documentation after orchestrator returns")

    # --- Exit codes documented ---
    exit_variants = ["exit 0", "exit 1", "exit code"]
    if not any(v.lower() in text.lower() for v in exit_variants):
        failures.append("missing exit-code documentation (exit 0 / exit 1)")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS start/SKILL.md has required structure: frontmatter, $ARGUMENTS, "
        "--until, circuit-breaker, _run-orchestrator, halted pre-check, "
        "target_cutoff_at/decisions.log, final summary, exit codes"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
