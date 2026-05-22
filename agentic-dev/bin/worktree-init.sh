#!/usr/bin/env bash
# Create a fresh git worktree for an agentic-dev goal and write the kickoff
# package the implementer subagent reads.
#
# Usage: worktree-init.sh <goal-id>
# Output (stdout): absolute path to the created worktree
# Exits 1 on error.
set -euo pipefail

GOAL_ID="${1:-}"
if [[ -z "$GOAL_ID" ]]; then
  echo "Usage: worktree-init.sh <goal-id>" >&2
  exit 1
fi

# Validate goal-id format
if [[ ! "$GOAL_ID" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$ ]]; then
  echo "ERROR: goal-id must match YYYY-MM-DD-<slug>; got: $GOAL_ID" >&2
  exit 1
fi

# Must run from inside an initialized project
if [[ ! -f .claude/agentic/state.json ]]; then
  echo "ERROR: not an agentic-dev project (no .claude/agentic/state.json)" >&2
  exit 1
fi

SPEC_PATH=".claude/agentic/specs/${GOAL_ID}.md"
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "ERROR: spec file not found: $SPEC_PATH" >&2
  exit 1
fi

# Spec must be approved
APPROVED="$(python3 -c "
import sys
text = open('$SPEC_PATH').read()
if not text.startswith('---'):
    print('false')
    sys.exit(0)
parts = text.split('---', 2)
if len(parts) < 3:
    print('false')
    sys.exit(0)
import yaml
fm = yaml.safe_load(parts[1])
print('true' if fm.get('approved') else 'false')
")"

if [[ "$APPROVED" != "true" ]]; then
  echo "ERROR: spec is not approved (approved: false)" >&2
  exit 1
fi

WORKTREE_PATH=".worktrees/goal-${GOAL_ID}"
ABS_WORKTREE_PATH="$(pwd)/${WORKTREE_PATH}"

if [[ -d "$WORKTREE_PATH" ]]; then
  echo "ERROR: worktree already exists at $WORKTREE_PATH" >&2
  echo "  Run worktree-cleanup.sh ${GOAL_ID} first if you want to start fresh." >&2
  exit 1
fi

# Create worktree from current HEAD
mkdir -p .worktrees
BASELINE_REF="$(git rev-parse HEAD)"
git worktree add "$WORKTREE_PATH" HEAD --quiet

# Read project commands from config.yaml
CONFIG_PATH=".claude/agentic/config.yaml"

# Build kickoff JSON
python3 - "$GOAL_ID" "$SPEC_PATH" "$ABS_WORKTREE_PATH" "$BASELINE_REF" "$CONFIG_PATH" <<'PY'
import sys, json, yaml, os
goal_id, spec_path, worktree_abs, baseline_ref, config_path = sys.argv[1:6]
cfg = yaml.safe_load(open(config_path))

# Override budgets if the spec carries a Diff budget section with non-default values
# (P3 simplification: read budgets from config.yaml; per-goal overrides come in v0.3.x)
budget = {
    "wall_clock_minutes_per_goal": cfg["budgets"]["wall_clock_minutes_per_goal"],
    "diff_lines_per_goal": cfg["budgets"]["diff_lines_per_goal"],
    "files_touched_per_goal": cfg["budgets"]["files_touched_per_goal"],
}

# spec_path passed to implementer should be relative to the worktree root,
# but the SPEC LIVES in the main project's .claude/agentic/specs/, NOT in the
# worktree. So we pass an absolute path so the implementer can read it.
abs_spec_path = os.path.abspath(spec_path)

project_commands = {
    "test": cfg["commands"]["test"],
    "lint": cfg["commands"]["lint"],
    "typecheck": cfg["commands"].get("typecheck"),
    "build": cfg["commands"].get("build"),
}

# Capture baseline test counts by running the test command on the baseline state.
# The worktree is already at baseline_ref (created from HEAD above).
baseline_test_counts = None
test_cmd = project_commands.get("test")
if test_cmd:
    import subprocess, re
    try:
        proc = subprocess.run(
            test_cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd=worktree_abs,
            timeout=120,
        )
        output = proc.stdout + "\n" + proc.stderr

        passed_n = failed_n = skipped_n = None

        # jest / mocha: "Tests:   3 passed, 0 failed"
        m = re.search(r'Tests?:\s+(\d+)\s+passed', output, re.IGNORECASE)
        if m:
            passed_n = int(m.group(1))
        m2 = re.search(r'Tests?:.*?(\d+)\s+failing', output, re.IGNORECASE)
        if m2:
            failed_n = int(m2.group(1))
        else:
            m2b = re.search(r'(\d+)\s+failing', output, re.IGNORECASE)
            if m2b:
                failed_n = int(m2b.group(1))

        # pytest: "== 3 passed, 0 failed ==" or "=== 3 passed ==="
        if passed_n is None:
            m = re.search(r'={3,}\s*(\d+)\s+passed', output, re.IGNORECASE)
            if m:
                passed_n = int(m.group(1))
        if failed_n is None:
            m = re.search(r'={3,}.*?(\d+)\s+failed', output, re.IGNORECASE)
            if m:
                failed_n = int(m.group(1))

        # Generic: "N passed" / "N failed"
        if passed_n is None:
            m = re.search(r'(\d+)\s+passed', output, re.IGNORECASE)
            if m:
                passed_n = int(m.group(1))
        if failed_n is None:
            m = re.search(r'(\d+)\s+failed', output, re.IGNORECASE)
            if m:
                failed_n = int(m.group(1))

        # Generic fallback: count lines matching ^(PASS|FAIL|ok)
        if passed_n is None:
            pass_lines = [l for l in output.splitlines() if re.match(r'^(PASS|ok)\b', l.strip())]
            fail_lines = [l for l in output.splitlines() if re.match(r'^FAIL\b', l.strip())]
            if pass_lines or fail_lines:
                passed_n = len(pass_lines)
                failed_n = len(fail_lines)

        # skipped
        skipped_n = 0
        m = re.search(r'(\d+)\s+skipped', output, re.IGNORECASE)
        if m:
            skipped_n = int(m.group(1))

        if passed_n is not None:
            baseline_test_counts = {
                "passed": passed_n,
                "failed": failed_n if failed_n is not None else 0,
                "skipped": skipped_n,
            }
        else:
            import sys as _sys
            print(
                f"WARNING: worktree-init: could not parse test counts from output of: {test_cmd}",
                file=_sys.stderr,
            )
    except Exception as exc:
        import sys as _sys
        print(
            f"WARNING: worktree-init: baseline test run failed: {exc}",
            file=_sys.stderr,
        )

# Parse the spec for a `# Walkthrough` section (added in 1.4.0).
# Shape expected in spec body (free-form, parsed leniently):
#
#   # Walkthrough
#   - Acceptance URL: http://localhost:5173/
#   - Dev server command: npm run dev
#   - Dev server ready pattern: Local:.*5173
#   - Acceptance criteria:
#     - Open / and verify ...
#     - Click 'Watchlist' ...
#     - ...
#
# If the section is absent or has no criteria, walkthrough field is null;
# the walkthrough lifecycle then returns verdict: skipped.
walkthrough = None
try:
    import re as _re
    spec_text = open(abs_spec_path).read()
    m = _re.search(r"^# Walkthrough\s*$(.+?)(?=^# |\Z)", spec_text, _re.MULTILINE | _re.DOTALL)
    if m:
        section = m.group(1)
        def grab(label):
            mm = _re.search(rf"-\s*{label}\s*:\s*(.+)", section)
            return mm.group(1).strip() if mm else None
        acc_url = grab("Acceptance URL")
        dev_cmd = grab("Dev server command")
        dev_ready = grab("Dev server ready pattern")
        # Parse acceptance criteria as a bullet list under "Acceptance criteria:"
        criteria_match = _re.search(r"-\s*Acceptance criteria\s*:\s*$(.+?)(?=^-\s|\Z)",
                                    section, _re.MULTILINE | _re.DOTALL)
        criteria = []
        if criteria_match:
            for line in criteria_match.group(1).splitlines():
                line = line.strip()
                if line.startswith("- "):
                    criteria.append(line[2:].strip())
        # Treat "skip", "n/a", "none" (case-insensitive) as explicit skip
        if acc_url and acc_url.lower() in ("skip", "n/a", "none"):
            walkthrough = None
        elif acc_url and criteria:
            walkthrough = {
                "acceptance_url": acc_url,
                "acceptance_criteria": criteria,
                "dev_server_command": dev_cmd,
                "dev_server_ready_pattern": dev_ready,
            }
except Exception as _exc:
    import sys as _sys
    print(f"WARNING: worktree-init: failed to parse Walkthrough section: {_exc}",
          file=_sys.stderr)

kickoff = {
    "goal_id": goal_id,
    "spec_path": abs_spec_path,
    "baseline_ref": baseline_ref,
    "budget": budget,
    "sensitive_paths": cfg["sensitive_paths"],
    "project_commands": project_commands,
    "worktree_path": worktree_abs,
    "baseline": {
        "test_counts": baseline_test_counts,
    },
    "walkthrough": walkthrough,
}

with open(os.path.join(worktree_abs, ".agentic-kickoff.json"), "w") as f:
    json.dump(kickoff, f, indent=2)
PY

# Print worktree path on stdout (caller captures this)
echo "$ABS_WORKTREE_PATH"
