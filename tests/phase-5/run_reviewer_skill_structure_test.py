"""Verify skills/_run-reviewer/SKILL.md has required structure and references.

Per docs/superpowers/test-cost-policy.md, this is a deterministic test —
no Claude invocation. We assert the skill file has the right shape and
key phrases that encode the _run-reviewer lifecycle discipline.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-reviewer" / "SKILL.md"


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

    # --- Required phrases in skill body ---
    required_phrases = [
        "$ARGUMENTS",       # how goal-id is passed in
        "hardened-reviewer",  # primary subagent name
        "reviewer-adversary", # second-pass subagent name
        "Agent tool",         # dispatch mechanism
        "generate-escalation", # escalation script call
        "telegram-notify",    # notification script call
        "clean",              # verdict enum: clean
        "concern",            # verdict enum: concern
        "blocking",           # verdict enum: blocking
        "mechanical",         # concern category
        "judgment",           # concern category
        "uncategorized",      # concern category
        "gate_failure",       # escalation trigger for gate short-circuit
        "auto-fix",           # auto-fix routing
    ]
    for phrase in required_phrases:
        if phrase.lower() not in text.lower():
            failures.append(f"missing required phrase: {phrase!r}")

    # --- Must document the refuse-if-empty case for $ARGUMENTS ---
    if not any(
        v in text.lower()
        for v in ["refuse", "empty", "required", "requires a goal"]
    ):
        failures.append("no documentation for refusing empty $ARGUMENTS")

    # --- Gate-failure short-circuit handling ---
    gate_short_circuit_variants = [
        "gate_failure",
        "overall == \"fail\"",
        "blocking_failures",
        "gate verdict",
        "skip reviewer",
    ]
    if not any(v.lower() in text.lower() for v in gate_short_circuit_variants):
        failures.append(
            f"missing gate-failure short-circuit handling; "
            f"expected one of {gate_short_circuit_variants}"
        )

    # --- Malformed-output handling ---
    malformed_variants = [
        "malformed",
        "raw.txt",
        "stub verdict",
        "invalid json",
        "parse",
    ]
    if not any(v.lower() in text.lower() for v in malformed_variants):
        failures.append(
            f"missing malformed-output handling; "
            f"expected one of {malformed_variants}"
        )

    # --- Pre-checks: manifest, gate verdict, diff envelope ---
    prechecks = {
        "manifest":     ["manifest"],
        "gate verdict": ["gate verdict", "verdicts/", "verdict exists", "p4 must"],
        "diff envelope": ["diff envelope", "diffs/", "diff-envelope"],
    }
    for check_name, variants in prechecks.items():
        if not any(v.lower() in text.lower() for v in variants):
            failures.append(f"missing pre-check mention: {check_name!r}")

    # --- Dispatch pattern: subagent_type or hardened-reviewer must be mentioned ---
    if "subagent_type" not in text and "hardened-reviewer" not in text:
        failures.append("missing subagent dispatch (subagent_type or hardened-reviewer reference)")

    # --- Adversary dispatch on clean verdict ---
    adversary_dispatch_variants = [
        "reviewer-adversary",
        "second pass",
        "second-pass",
        "adversary",
    ]
    if not any(v.lower() in text.lower() for v in adversary_dispatch_variants):
        failures.append("missing reviewer-adversary dispatch on clean verdict")

    # --- Escalation for blocking / judgment concerns ---
    escalation_variants = [
        "generate-escalation",
        "escalation packet",
        "generate_escalation",
    ]
    if not any(v.lower() in text.lower() for v in escalation_variants):
        failures.append("missing escalation call (generate-escalation)")

    # --- Telegram notification wiring ---
    telegram_variants = [
        "telegram-notify",
        "telegram_notify",
        "telegram notify",
    ]
    if not any(v.lower() in text.lower() for v in telegram_variants):
        failures.append("missing telegram-notify call")

    # --- Must mention writing the reviewer verdict to disk ---
    verdict_write_variants = [
        "reviewer-verdicts",
        "reviewer-verdicts/<goal-id>",
        "write.*verdict",
        "verdict.*json",
    ]
    if not any(v.lower() in text.lower() for v in verdict_write_variants):
        failures.append("missing mention of writing reviewer-verdict file to disk")

    # --- reviewer-verdict.schema.json must be referenced ---
    if "reviewer-verdict.schema.json" not in text:
        failures.append("missing reference to reviewer-verdict.schema.json (validation)")

    # --- Do-NOT list ---
    do_not_variants = [
        "do not modify",
        "do not clean",
        "do not update",
        "do not invoke another skill",
        "do not call another skill",
        "does not",
        "do NOT",
    ]
    if not any(v.lower() in text.lower() for v in do_not_variants):
        failures.append("missing Do-NOT list")

    # --- auto_fix_candidates or auto-fix-queue must be mentioned ---
    auto_fix_variants = [
        "auto_fix_candidates",
        "auto-fix-queue",
        "auto-fix queue",
        "auto_fix",
    ]
    if not any(v.lower() in text.lower() for v in auto_fix_variants):
        failures.append(
            "missing auto-fix candidates file / queue reference "
            "(mechanical concerns should be routed to P6)"
        )

    # --- Exit code handling: exit 0 for clean, exit 1 for escalation ---
    exit_variants = ["exit 0", "exit 1", "exit code"]
    if not any(v.lower() in text.lower() for v in exit_variants):
        failures.append("missing exit-code documentation (exit 0 / exit 1)")

    if failures:
        for f in failures:
            print(f"FAIL {f}")
        sys.exit(1)

    print(
        "PASS _run-reviewer/SKILL.md has required structure: frontmatter, $ARGUMENTS, "
        "hardened-reviewer dispatch, reviewer-adversary dispatch, gate-failure short-circuit, "
        "malformed-output handling, concern routing (mechanical/judgment/uncategorized), "
        "escalation + telegram wiring, auto-fix candidates, do-NOT list"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
