"""Verify agentic-dev/skills/resume/SKILL.md has required structure.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the skill file has the right shape and
key phrases that encode the /agentic-dev:resume after-halt decision discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "resume" / "SKILL.md"


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
            ("halt", ["halt"]),
            ("decisions.log", ["decisions.log", "decision"]),
            ("circuit breaker", ["circuit_breaker", "circuit-breaker", "circuit breaker"]),
        ]
        for label, variants in required_desc_phrases:
            if not any(v.lower() in fm_body.lower() for v in variants):
                failures.append(f"frontmatter description missing reference to: {label!r}")

    # --- $ARGUMENTS: must document decision token ---
    if "$ARGUMENTS" not in text:
        failures.append("missing $ARGUMENTS reference")

    # --- All 5 decision values must be present ---
    required_decisions = ["resume", "skip", "address", "replan", "abort"]
    for decision in required_decisions:
        # Match whole word or as a decision label
        if not re.search(r'\b' + re.escape(decision) + r'\b', text, re.IGNORECASE):
            failures.append(f"missing decision value: {decision!r}")

    # --- decisions.log reference ---
    if "decisions.log" not in text:
        failures.append("missing decisions.log reference")

    # --- Log format: ISO timestamp | decision | goal_id | notes ---
    log_format_variants = [
        "iso",
        "timestamp",
        "decisions.log",
        "<iso",
        "UTC",
    ]
    if not any(v.lower() in text.lower() for v in log_format_variants):
        failures.append(
            "missing decisions.log entry format (ISO timestamp | decision | goal_id | notes)"
        )

    # --- queue-set-status.sh reference ---
    if "queue-set-status" not in text.lower():
        failures.append("missing queue-set-status reference")

    # --- circuit-breaker reference ---
    cb_variants = ["circuit-breaker", "circuit_breaker"]
    if not any(v.lower() in text.lower() for v in cb_variants):
        failures.append("missing circuit-breaker reference")

    # --- Pre-check: must be halted ---
    precheck_variants = [
        "halted",
        "circuit_breaker.state",
        "circuit breaker",
        "state == halted",
        "state=halted",
    ]
    if not any(v.lower() in text.lower() for v in precheck_variants):
        failures.append("missing pre-check: circuit_breaker.state == halted")

    # --- halted_goal_id field referenced ---
    if "halted_goal_id" not in text:
        failures.append("missing halted_goal_id field reference")

    # --- Per-decision outcomes ---

    # resume → approved
    resume_approved_variants = [
        "approved",
        "queue-set-status",
    ]
    if not any(v.lower() in text.lower() for v in resume_approved_variants):
        failures.append(
            "missing resume→approved outcome (queue-set-status to approved)"
        )

    # skip → abandoned
    if "abandoned" not in text.lower():
        failures.append("missing skip→abandoned outcome")

    # replan → drafted
    if "drafted" not in text.lower():
        failures.append("missing replan→drafted outcome")

    # abort → completed/stopped
    abort_variants = [
        "abort",
        "completed",
        "stop",
    ]
    if not any(v.lower() in text.lower() for v in abort_variants):
        failures.append("missing abort outcome (circuit-breaker completed / abort)")

    # --- circuit-breaker idle reset (resume/skip/address/replan paths) ---
    cb_idle_variants = [
        "circuit-breaker.sh idle",
        "circuit-breaker idle",
        "circuit_breaker idle",
        "idle",
    ]
    if not any(v.lower() in text.lower() for v in cb_idle_variants):
        failures.append(
            "missing circuit-breaker → idle reset on resume/skip/address/replan"
        )

    # --- /agentic-dev:start hint after resume/skip ---
    start_hint_variants = [
        "/agentic-dev:start",
        "agentic-dev:start",
    ]
    if not any(v.lower() in text.lower() for v in start_hint_variants):
        failures.append(
            "missing /agentic-dev:start hint after resume/skip/address/replan"
        )

    # --- Exit codes documented ---
    exit_variants = ["exit 0", "exit 1", "exit code"]
    if not any(v.lower() in text.lower() for v in exit_variants):
        failures.append("missing exit-code documentation (exit 0 / exit 1)")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS resume/SKILL.md has required structure: frontmatter, $ARGUMENTS, "
        "decisions (resume|skip|address|replan|abort), decisions.log, "
        "queue-set-status, circuit-breaker, halted pre-check, halted_goal_id, "
        "per-decision outcomes (approved/abandoned/drafted/completed), "
        "circuit-breaker idle reset, /agentic-dev:start hint, exit codes"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
