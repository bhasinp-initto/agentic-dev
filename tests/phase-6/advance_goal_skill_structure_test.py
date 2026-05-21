"""Verify agentic-dev/skills/_advance-goal/SKILL.md has required structure.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the skill file has the right shape and
key phrases that encode the _advance-goal lifecycle discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_advance-goal" / "SKILL.md"


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

    # --- $ARGUMENTS handling ---
    if "$ARGUMENTS" not in text:
        failures.append("missing $ARGUMENTS reference")

    # Must document refuse-if-empty for $ARGUMENTS
    if not any(v in text.lower() for v in ["refuse", "empty", "required", "requires a goal"]):
        failures.append("no documentation for refusing empty $ARGUMENTS")

    # --- Required phrases (case-insensitive) ---
    required_phrases = [
        "queue-set-status",       # state transition helper
        "circuit-breaker",        # circuit breaker helper
        "_run-implementer",       # implementer dispatch
        "_run-gates",             # gates dispatch
        "_run-reviewer",          # reviewer dispatch
        "auto-fix",               # auto-fix loop
        "rounds",                 # round tracking
        "cap",                    # hard cap reference
        "clean path",             # clean outcome path
        "halt path",              # halt outcome path
        "cleanup-completed-goal", # worktree cleanup on success
        "telegram-notify",        # notification on success
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # --- Round cap must specify 2 rounds ---
    cap_2_variants = [
        "2 rounds",
        "max 2",
        "cap 2",
        "round 2",
        "rounds < 2",
        "rounds == 2",
        "cap of 2",
    ]
    if not any(v.lower() in text.lower() for v in cap_2_variants):
        failures.append(
            f"missing auto-fix cap of 2 rounds; expected one of {cap_2_variants}"
        )

    # --- Specific field names that must be mentioned ---
    required_fields = [
        "auto_fix_exhausted",  # escalation reason when rounds exhausted
        "baseline_ref",        # git SHA captured at start
        "completed_at",        # timestamp on clean completion
        "halted_at",           # timestamp on halt
    ]
    for field in required_fields:
        if field not in text:
            failures.append(f"missing required field reference: {field!r}")

    # --- Do-NOT section ---
    do_not_variants = [
        "do not",
        "do NOT",
        "must not",
        "never",
        "NEVER",
    ]
    if not any(v in text for v in do_not_variants):
        failures.append("missing Do-NOT section")

    # --- Pre-check: queue must verify approved status ---
    precheck_variants = [
        "status=approved",
        "status == approved",
        "approved",
    ]
    if not any(v.lower() in text.lower() for v in precheck_variants):
        failures.append("missing pre-check for goal status=approved")

    # --- baseline_ref via git rev-parse ---
    git_rev_variants = [
        "git rev-parse",
        "baseline_ref",
        "rev-parse HEAD",
    ]
    if not any(v.lower() in text.lower() for v in git_rev_variants):
        failures.append("missing baseline_ref capture (git rev-parse HEAD)")

    # --- Auto-fix loop: must reference the auto-fix-queue file ---
    auto_fix_queue_variants = [
        "auto-fix-queue",
        "auto_fix_queue",
        "auto-fix queue",
    ]
    if not any(v.lower() in text.lower() for v in auto_fix_queue_variants):
        failures.append("missing auto-fix-queue file reference")

    # --- Halt path must include circuit-breaker halted call ---
    halt_cb_variants = [
        "circuit-breaker.sh halted",
        "circuit-breaker halted",
        "circuit_breaker halted",
    ]
    if not any(v.lower() in text.lower() for v in halt_cb_variants):
        failures.append("missing circuit-breaker halted call on halt path")

    # --- Clean path must include both completed status and cleanup ---
    if "completed" not in text.lower():
        failures.append("missing 'completed' status on clean path")

    # --- Exit codes documented ---
    exit_variants = ["exit 0", "exit 1", "exit code"]
    if not any(v.lower() in text.lower() for v in exit_variants):
        failures.append("missing exit-code documentation (exit 0 / exit 1)")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS _advance-goal/SKILL.md has required structure: frontmatter, $ARGUMENTS, "
        "queue-set-status, circuit-breaker, _run-implementer, _run-gates, _run-reviewer, "
        "auto-fix loop (cap 2 rounds), clean path, halt path, cleanup-completed-goal, "
        "telegram-notify, auto_fix_exhausted, baseline_ref, completed_at, halted_at, "
        "Do-NOT section"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
