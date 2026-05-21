#!/usr/bin/env python3
"""
run_implementer_skill_modified_test.py
Verifies that worktree-init.sh writes a kickoff JSON that includes
`baseline.test_counts` (field existence; value may be null if parse failed).
No claude -p invocations.
"""
import json
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORKTREE_INIT = os.path.join(REPO_ROOT, "agentic-dev", "bin", "worktree-init.sh")

PASS = 0
FAIL = 0


def passed(name):
    global PASS
    print(f"PASS {name}")
    PASS += 1


def failed(name, reason):
    global FAIL
    print(f"FAIL {name}: {reason}")
    FAIL += 1


def setup_tmp_project(tmpdir):
    """Create a minimal agentic-dev project in tmpdir."""
    # Init git repo
    subprocess.run(["git", "init", "-q", tmpdir], check=True)
    subprocess.run(
        ["git", "-C", tmpdir, "config", "user.email", "test@test.com"], check=True
    )
    subprocess.run(
        ["git", "-C", tmpdir, "config", "user.name", "Test"], check=True
    )
    # Initial commit
    index_js = os.path.join(tmpdir, "index.js")
    with open(index_js, "w") as f:
        f.write("console.log('hello')\n")
    subprocess.run(["git", "-C", tmpdir, "add", "index.js"], check=True)
    subprocess.run(
        ["git", "-C", tmpdir, "commit", "-q", "-m", "initial"],
        check=True,
        env={**os.environ, "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@test.com",
             "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@test.com"},
    )

    # Create required project state
    state_dir = os.path.join(tmpdir, ".claude", "agentic")
    os.makedirs(os.path.join(state_dir, "intents"), exist_ok=True)
    os.makedirs(os.path.join(state_dir, "specs"), exist_ok=True)

    state_json = {
        "schema_version": "0.1",
        "circuit_breaker": {
            "state": "idle",
            "halted_reason": None,
            "halted_at": None,
            "halted_goal_id": None,
        },
        "current_goal": None,
        "last_updated": "2026-05-21T10:00:00Z",
    }
    with open(os.path.join(state_dir, "state.json"), "w") as f:
        json.dump(state_json, f)

    # Create spec
    spec_content = """\
---
id: 2026-05-21-test-goal
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-21-test-goal.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test goal.

# Files in scope
- src/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
"""
    spec_path = os.path.join(state_dir, "specs", "2026-05-21-test-goal.md")
    with open(spec_path, "w") as f:
        f.write(spec_content)

    # Create intent stub
    with open(os.path.join(state_dir, "intents", "2026-05-21-test-goal.md"), "w") as f:
        f.write("stub\n")

    # Create config.yaml — use a simple echo-based test command so we don't need
    # an actual test runner in the tmp project
    config_content = """\
schema_version: "0.1"
project:
  name: test-project
  primary_language: javascript
commands:
  test: "echo '3 passed, 0 failed'"
  lint: "echo lint-clean"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 90
  diff_lines_per_goal: 800
  files_touched_per_goal: 25
sensitive_paths:
  - "auth/**"
telegram: null
push_policy: hold
"""
    with open(os.path.join(state_dir, "config.yaml"), "w") as f:
        f.write(config_content)


def test_kickoff_has_baseline_test_counts():
    """Invoke worktree-init.sh and assert kickoff JSON has `baseline.test_counts` field."""
    with tempfile.TemporaryDirectory(prefix="agentic-worktree-init-p4t2-") as tmpdir:
        setup_tmp_project(tmpdir)

        result = subprocess.run(
            [WORKTREE_INIT, "2026-05-21-test-goal"],
            capture_output=True,
            text=True,
            cwd=tmpdir,
        )

        if result.returncode != 0:
            failed(
                "worktree-init-returns-zero",
                f"exit code {result.returncode}\nstdout: {result.stdout}\nstderr: {result.stderr}",
            )
            return

        passed("worktree-init-returns-zero")

        worktree_path = result.stdout.strip()
        kickoff_path = os.path.join(worktree_path, ".agentic-kickoff.json")

        if not os.path.isfile(kickoff_path):
            failed("kickoff-file-exists", f"not found: {kickoff_path}")
            return
        passed("kickoff-file-exists")

        with open(kickoff_path) as f:
            kickoff = json.load(f)

        # The key assertion: `baseline` key must exist in kickoff
        if "baseline" not in kickoff:
            failed(
                "kickoff-has-baseline-key",
                f"'baseline' key missing from kickoff. Keys present: {list(kickoff.keys())}",
            )
            return
        passed("kickoff-has-baseline-key")

        # `baseline.test_counts` must exist (value may be null if parse failed)
        baseline = kickoff["baseline"]
        if not isinstance(baseline, dict) or "test_counts" not in baseline:
            failed(
                "kickoff-baseline-has-test-counts",
                f"baseline.test_counts missing. baseline value: {baseline!r}",
            )
            return
        passed("kickoff-baseline-has-test-counts")

        # test_counts should be either null or a dict with passed/failed/skipped
        tc = baseline["test_counts"]
        if tc is not None:
            required_keys = {"passed", "failed", "skipped"}
            missing = required_keys - set(tc.keys())
            if missing:
                failed(
                    "kickoff-test-counts-shape",
                    f"test_counts missing keys {missing}; got {tc}",
                )
                return
            passed("kickoff-test-counts-shape-valid")
        else:
            # null is acceptable (parse failure / no test command)
            passed("kickoff-test-counts-is-null-acceptable")


def main():
    if not os.path.isfile(WORKTREE_INIT):
        print(f"FAIL setup: worktree-init.sh not found at {WORKTREE_INIT}")
        sys.exit(1)

    test_kickoff_has_baseline_test_counts()

    print()
    print(f"Results: {PASS} passed, {FAIL} failed")
    sys.exit(0 if FAIL == 0 else 1)


if __name__ == "__main__":
    main()
