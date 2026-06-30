#!/usr/bin/env bash
# gate-rerun-tests.sh <manifest-path> <kickoff-path>
# Independently re-runs the project test command in the worktree and compares
# the actual pass/fail counts to what the manifest claims.
#
# Exits 0 on pass or inconclusive. Exits 1 on blocking fail.
# JSON output to stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST="${1:-}"
KICKOFF="${2:-}"
if [[ -z "$MANIFEST" || -z "$KICKOFF" ]]; then
  echo '{"gate":"rerun-tests","result":"inconclusive","severity":"warning","details":"missing args: <manifest-path> <kickoff-path>"}'
  exit 1
fi

python3 - "$MANIFEST" "$KICKOFF" "$SCRIPT_DIR" <<'PY'
import sys, json, subprocess, re

mpath, kpath = sys.argv[1:3]
mf = json.load(open(mpath))
kf = json.load(open(kpath))

import sys, os
script_dir = sys.argv[3]
sys.path.insert(0, script_dir)
import agentic_components as ac

kf_components = kf.get("components")
mf_by_comp = {c["name"]: c for c in (mf.get("tests_by_component") or [])}

if kf_components and mf_by_comp:
    # ── Multi-component path ────────────────────────────────────────────────
    worktree_path = mf.get("worktree_path")
    changed = (mf.get("scope_check", {}) or {}).get("in_spec_files", []) + \
              (mf.get("scope_check", {}) or {}).get("out_of_spec_files", [])
    touched, _unmatched = ac.select_touched(kf_components, changed)

    if not worktree_path:
        print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                          "severity": "warning",
                          "details": "manifest.worktree_path missing"}))
        sys.exit(0)

    import subprocess, re
    mismatches = []
    checked = []
    for comp in touched:
        test_cmd = comp["commands"].get("test")
        claim = mf_by_comp.get(comp["name"])
        if not test_cmd or claim is None:
            continue
        cwd = os.path.join(worktree_path, comp["path"]) if comp["path"] not in (".", "") else worktree_path
        try:
            proc = subprocess.run(test_cmd, shell=True, capture_output=True,
                                  text=True, cwd=cwd, timeout=300)
        except Exception as exc:
            print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                              "severity": "warning",
                              "details": f"{comp['name']}: test run failed: {exc}"}))
            sys.exit(0)
        counts = ac.parse_test_counts(proc.stdout + "\n" + proc.stderr)
        if counts is None:
            print(json.dumps({"gate": "rerun-tests", "result": "inconclusive",
                              "severity": "warning",
                              "details": f"{comp['name']}: could not parse counts for {test_cmd}"}))
            sys.exit(0)
        checked.append(comp["name"])
        if counts["passed"] != claim.get("passed") or counts["failed"] != claim.get("failed", 0):
            mismatches.append(
                f"{comp['name']}: actual {counts['passed']}p/{counts['failed']}f vs "
                f"manifest {claim.get('passed')}p/{claim.get('failed', 0)}f")

    if mismatches:
        print(json.dumps({"gate": "rerun-tests", "result": "fail", "severity": "blocking",
                          "details": "per-component test mismatch: " + "; ".join(mismatches),
                          "raw": {"checked": checked}}))
        sys.exit(1)
    print(json.dumps({"gate": "rerun-tests", "result": "pass", "severity": "blocking",
                      "details": f"per-component test counts match: {', '.join(checked) or 'no touched components'}",
                      "raw": {"checked": checked}}))
    sys.exit(0)
# ── Single-component path falls through to existing logic below ─────────────

test_cmd = (kf.get("project_commands") or {}).get("test")
worktree_path = mf.get("worktree_path")

if not test_cmd:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": "kickoff.project_commands.test is null; cannot re-run tests",
        "raw": {"test_cmd": None},
    }))
    sys.exit(0)

if not worktree_path:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": "manifest.worktree_path is missing; cannot locate worktree",
        "raw": {"worktree_path": None},
    }))
    sys.exit(0)

# Run the test command in the worktree
try:
    proc = subprocess.run(
        test_cmd,
        shell=True,
        capture_output=True,
        text=True,
        cwd=worktree_path,
        timeout=300,
    )
except subprocess.TimeoutExpired:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": f"test command timed out (300s): {test_cmd}",
        "raw": {"test_cmd": test_cmd, "worktree_path": worktree_path},
    }))
    sys.exit(0)
except Exception as exc:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": f"test command failed to run: {exc}",
        "raw": {"test_cmd": test_cmd, "worktree_path": worktree_path},
    }))
    sys.exit(0)

output = proc.stdout + "\n" + proc.stderr

# ── Parse test counts (cascading regex, consistent with worktree-init.sh) ──

passed_n = failed_n = None

# jest / mocha: "Tests:   3 passed"  or  "Tests:   3 passed, 1 failed"
m = re.search(r'Tests?:\s+(\d+)\s+passed', output, re.IGNORECASE)
if m:
    passed_n = int(m.group(1))
m2 = re.search(r'Tests?:.*?(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
if m2:
    failed_n = int(m2.group(1))
else:
    m2b = re.search(r'(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
    if m2b:
        failed_n = int(m2b.group(1))

# pytest: "=== 5 passed ==="  or  "=== 5 passed, 1 failed ==="
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

# Generic fallback: count lines matching ^(PASS|ok) or ^FAIL
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

# ── Inconclusive if we could not parse ─────────────────────────────────────

if passed_n is None:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": (
            f"could not parse test counts from command output; "
            f"test command: {test_cmd}"
        ),
        "raw": {
            "test_cmd": test_cmd,
            "worktree_path": worktree_path,
            "exit_code": proc.returncode,
            "stdout_tail": proc.stdout[-500:] if proc.stdout else "",
        },
    }))
    sys.exit(0)

if failed_n is None:
    failed_n = 0

actual_passed = passed_n
actual_failed = failed_n

# ── Compare to manifest claims ──────────────────────────────────────────────

tests = mf.get("tests", {}) or {}
manifest_passed = tests.get("passed")
manifest_failed = tests.get("failed", 0)

raw = {
    "test_cmd": test_cmd,
    "worktree_path": worktree_path,
    "exit_code": proc.returncode,
    "actual_passed": actual_passed,
    "actual_failed": actual_failed,
    "actual_skipped": skipped_n,
    "manifest_passed": manifest_passed,
    "manifest_failed": manifest_failed,
}

if manifest_passed is None:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "inconclusive",
        "severity": "warning",
        "details": "manifest.tests.passed is missing; cannot compare",
        "raw": raw,
    }))
    sys.exit(0)

mismatches = []
if actual_passed != manifest_passed:
    mismatches.append(
        f"passed: actual={actual_passed} vs manifest={manifest_passed}"
    )
if actual_failed != manifest_failed:
    mismatches.append(
        f"failed: actual={actual_failed} vs manifest={manifest_failed}"
    )

if mismatches:
    print(json.dumps({
        "gate": "rerun-tests",
        "result": "fail",
        "severity": "blocking",
        "details": "test count mismatch: " + "; ".join(mismatches),
        "raw": raw,
    }))
    sys.exit(1)

print(json.dumps({
    "gate": "rerun-tests",
    "result": "pass",
    "severity": "blocking",
    "details": (
        f"test counts match manifest: "
        f"{actual_passed} passed, {actual_failed} failed"
    ),
    "raw": raw,
}))
sys.exit(0)
PY
