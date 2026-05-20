"""Unit tests for agentic-dev/bin/validate-spec.sh.

Each test creates a temporary spec file, runs the validator, asserts the exit
code and that specific substrings appear in stderr.
"""
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "agentic-dev" / "bin" / "validate-spec.sh"


def run_validator(spec_text: str):
    """Write spec_text to a tmp file, run validator, return (exit_code, stderr)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        intent_dir = Path(tmpdir) / ".claude" / "agentic" / "intents"
        spec_dir = Path(tmpdir) / ".claude" / "agentic" / "specs"
        intent_dir.mkdir(parents=True)
        spec_dir.mkdir(parents=True)

        # The validator checks intent_path resolves; create the referenced file
        intent_file = intent_dir / "2026-05-20-x.md"
        intent_file.write_text("intent body")

        spec_file = spec_dir / "2026-05-20-x.md"
        spec_file.write_text(spec_text)

        result = subprocess.run(
            [str(VALIDATOR), str(spec_file)],
            capture_output=True,
            text=True,
            cwd=tmpdir,
        )
        return result.returncode, result.stdout + result.stderr


# Test fixtures
GOOD_SPEC_NOT_APPROVED = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: false
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test spec body.

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

GOOD_SPEC_APPROVED_NO_QUESTIONS = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test spec body.

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

APPROVED_WITH_QUESTION = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    <!-- QUESTION-1 (architectural-decision) -->
    **Q:** Unanswered?
    **Your answer:** [REPLACE THIS LINE]

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

BAD_FRONTMATTER = "not yaml frontmatter at all, just plain text"

APPROVED_BAD_BUDGET = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    # Diff budget
    - Wall clock: zero minutes
    - Diff lines: 800
    - Files touched: 25
""")

SPEC_BAD_INTENT_PATH = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: nonexistent/path-that-does-not-resolve.md
    approved: false
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")

APPROVED_WITH_REPLACE_ONLY = textwrap.dedent("""\
    ---
    id: 2026-05-20-x
    schema_version: "0.1"
    intent_path: .claude/agentic/intents/2026-05-20-x.md
    approved: true
    created_at: "2026-05-20T15:30:00Z"
    ---

    # Intent
    Test.

    # Files in scope
    The list of files is [REPLACE THIS LINE with paths].

    # Diff budget
    - Wall clock: 90 minutes
    - Diff lines: 800
    - Files touched: 25
""")


def main():
    results = []

    def check(name, predicate):
        outcome = predicate()
        if outcome:
            print(f"PASS {name}")
            results.append(True)
        else:
            print(f"FAIL {name}")
            results.append(False)

    if not VALIDATOR.exists():
        print(f"FAIL setup: validator not found at {VALIDATOR}")
        sys.exit(1)

    code, out = run_validator(GOOD_SPEC_NOT_APPROVED)
    check("good-not-approved exits 0", lambda: code == 0)

    code, out = run_validator(GOOD_SPEC_APPROVED_NO_QUESTIONS)
    check("good-approved exits 0", lambda: code == 0)
    check("good-approved mentions check-approval", lambda: "_check-approval" in out)

    code, out = run_validator(APPROVED_WITH_QUESTION)
    check("approved-with-question exits 1", lambda: code == 1)
    check("approved-with-question names QUESTION-1", lambda: "QUESTION-1" in out)

    code, out = run_validator(BAD_FRONTMATTER)
    check("bad-frontmatter exits 1", lambda: code == 1)
    check("bad-frontmatter mentions frontmatter", lambda: "frontmatter" in out.lower())

    code, out = run_validator(APPROVED_BAD_BUDGET)
    check("bad-budget exits 1", lambda: code == 1)
    check("bad-budget mentions budget", lambda: "budget" in out.lower())

    code, out = run_validator(SPEC_BAD_INTENT_PATH)
    check("bad-intent-path exits 1", lambda: code == 1)
    check("bad-intent-path mentions intent_path", lambda: "intent_path" in out)

    code, out = run_validator(APPROVED_WITH_REPLACE_ONLY)
    check("approved-with-replace-only exits 1", lambda: code == 1)
    check("approved-with-replace-only mentions placeholder", lambda: "REPLACE THIS LINE" in out or "placeholder" in out.lower())

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
