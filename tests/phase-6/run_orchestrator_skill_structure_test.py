"""Verify agentic-dev/skills/_run-orchestrator/SKILL.md has required structure.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the skill file has the right shape and
key phrases that encode the _run-orchestrator queue-loop discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-orchestrator" / "SKILL.md"


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
            ("circuit breaker", ["circuit_breaker", "circuit-breaker", "circuit breaker"]),
            ("_advance-goal", ["_advance-goal"]),
            ("ScheduleWakeup", ["schedulewakeup"]),
            ("halted", ["halted", "halt"]),
            ("approved", ["approved"]),
            ("queue idle", ["queue idle", "queue loop", "queue"]),
        ]
        for label, variants in required_desc_phrases:
            if not any(v.lower() in fm_body.lower() for v in variants):
                failures.append(f"frontmatter description missing reference to: {label!r}")

    # --- $ARGUMENTS or "no arguments" ---
    has_args_ref = (
        "$ARGUMENTS" in text
        or "no arguments" in text.lower()
        or "takes no argument" in text.lower()
        or "accepts no argument" in text.lower()
    )
    if not has_args_ref:
        failures.append("missing $ARGUMENTS reference (or explicit 'no arguments' note)")

    # --- Required phrases (case-insensitive) ---
    required_phrases = [
        ("circuit-breaker",    ["circuit-breaker", "circuit_breaker"]),
        ("queue.yaml",         ["queue.yaml"]),
        ("_advance-goal",      ["_advance-goal"]),
        ("ScheduleWakeup",     ["ScheduleWakeup", "schedulewakeup"]),
        ("halted",             ["halted"]),
        ("approved",           ["approved"]),
        ("queue idle",         ["queue idle", "queue is idle", "queue empty", "queue_idle"]),
    ]
    for label, variants in required_phrases:
        if not any(v.lower() in text.lower() for v in variants):
            failures.append(f"missing required phrase: {label!r}")

    # --- Wake-up cadence: must specify 30 seconds ---
    wakeup_30_variants = [
        "30s",
        "30 seconds",
        "delayseconds=30",
        "delay=30",
        "delayseconds: 30",
    ]
    if not any(v.lower() in text.lower() for v in wakeup_30_variants):
        failures.append(
            "missing wake-up cadence of 30s; expected one of "
            + str(wakeup_30_variants)
        )

    # --- Pre-check: circuit breaker state check ---
    precheck_variants = [
        "idle",
        "running",
        "circuit_breaker.state",
        "circuit breaker state",
    ]
    if not any(v.lower() in text.lower() for v in precheck_variants):
        failures.append("missing pre-check for circuit_breaker.state in {idle, running}")

    # --- Refuse on halted / completed ---
    refuse_halted_variants = [
        "halted",
        "refuse",
        "reject",
        "exit 1",
    ]
    if not any(v.lower() in text.lower() for v in refuse_halted_variants):
        failures.append("missing refuse/exit on halted or completed circuit-breaker state")

    # --- /agentic-dev:resume reference when halted ---
    resume_ref_variants = [
        "/agentic-dev:resume",
        "agentic-dev:resume",
        "resume",
    ]
    if not any(v.lower() in text.lower() for v in resume_ref_variants):
        failures.append("missing reference to /agentic-dev:resume for the halted path")

    # --- Exit code semantics documented ---
    exit_variants = ["exit 0", "exit 1", "exit code"]
    if not any(v.lower() in text.lower() for v in exit_variants):
        failures.append("missing exit-code documentation (exit 0 / exit 1)")

    # --- ScheduleWakeup must include prompt reference to _run-orchestrator ---
    schedule_prompt_variants = [
        "/agentic-dev:_run-orchestrator",
        "agentic-dev:_run-orchestrator",
        "_run-orchestrator",
    ]
    if not any(v.lower() in text.lower() for v in schedule_prompt_variants):
        failures.append(
            "missing ScheduleWakeup prompt reference to /agentic-dev:_run-orchestrator"
        )

    # --- Queue exhaustion handling ---
    exhaustion_variants = [
        "queue idle",
        "queue is idle",
        "queue empty",
        "no approved",
        "none found",
        "0 approved",
    ]
    if not any(v.lower() in text.lower() for v in exhaustion_variants):
        failures.append(
            "missing queue-exhaustion handling (no approved goals → 'queue idle')"
        )

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS _run-orchestrator/SKILL.md has required structure: frontmatter, "
        "$ARGUMENTS, circuit-breaker, queue.yaml, _advance-goal, ScheduleWakeup, "
        "halted, approved, queue idle, 30s wake-up cadence, exit codes"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
