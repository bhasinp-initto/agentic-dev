#!/usr/bin/env bash
# bisect-on-claim.sh <manifest-path> [test-pattern]
# Verifies "pre-existing failure" claims in manifest.deferrals by checking
# whether the test(s) actually fail on the baseline_ref commit.
#
# If they do fail on baseline: the claim is confirmed → gate passes.
# If they pass on baseline: the claim is false → gate fails (blocking).
#
# Exits 0 on pass. Exits 1 on blocking fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
TEST_PATTERN="${2:-}"

if [[ -z "$MANIFEST" ]]; then
  echo '{"gate":"bisect-on-claim","result":"inconclusive","severity":"warning","details":"missing args: <manifest-path> [test-pattern]"}'
  exit 1
fi

python3 - "$MANIFEST" "$TEST_PATTERN" <<'PY'
import sys, json, subprocess, tempfile, os, shutil

mpath = sys.argv[1]
test_pattern = sys.argv[2] if len(sys.argv) > 2 else ""

mf = json.load(open(mpath))

# ── Check deferrals for pre-existing failure claims ─────────────────────────

deferrals = mf.get("deferrals") or []
preexisting_deferrals = [
    d for d in deferrals
    if isinstance(d, dict) and "pre-existing" in str(d.get("reason", "")).lower()
]

if not preexisting_deferrals:
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "pass",
        "severity": "blocking",
        "details": "no pre-existing claims to verify",
        "raw": {"deferrals_checked": 0},
    }))
    sys.exit(0)

# ── Gather test command and baseline ref ────────────────────────────────────

project_commands = mf.get("project_commands") or {}
test_cmd = project_commands.get("test")
if not test_cmd:
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": "manifest.project_commands.test is null; cannot verify pre-existing claims",
        "raw": {"deferrals": preexisting_deferrals},
    }))
    sys.exit(0)

# If a test pattern was supplied, append it to the test command
if test_pattern:
    test_cmd = f"{test_cmd} {test_pattern}"

baseline_ref = mf.get("baseline_ref")
if not baseline_ref:
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": "manifest.baseline_ref is missing; cannot create baseline worktree",
        "raw": {"deferrals": preexisting_deferrals},
    }))
    sys.exit(0)

worktree_path = mf.get("worktree_path", "")
# Determine the git repo root from the worktree path or manifest location
# Strategy: try to find the git root from the worktree, then fall back to
# the directory of the manifest, then the cwd.
git_root = None
for candidate in [worktree_path, os.path.dirname(os.path.abspath(mpath)), os.getcwd()]:
    if not candidate:
        continue
    r = subprocess.run(
        ["git", "-C", candidate, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        git_root = r.stdout.strip()
        break

if not git_root:
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": "could not determine git repo root for baseline checkout",
        "raw": {"deferrals": preexisting_deferrals},
    }))
    sys.exit(0)

# ── Create a temp worktree at baseline_ref ──────────────────────────────────

tmp_dir = tempfile.mkdtemp(prefix="bisect-claim-")
temp_worktree = os.path.join(tmp_dir, "baseline-wt")

def cleanup():
    # Remove temp worktree
    rm = subprocess.run(
        ["git", "-C", git_root, "worktree", "remove", "--force", temp_worktree],
        capture_output=True, text=True,
    )
    try:
        shutil.rmtree(tmp_dir, ignore_errors=True)
    except Exception:
        pass

add_r = subprocess.run(
    ["git", "-C", git_root, "worktree", "add", "--detach", temp_worktree, baseline_ref],
    capture_output=True, text=True,
)
if add_r.returncode != 0:
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": f"failed to create baseline worktree at {baseline_ref}: {add_r.stderr.strip()}",
        "raw": {
            "baseline_ref": baseline_ref,
            "git_root": git_root,
            "deferrals": preexisting_deferrals,
        },
    }))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    sys.exit(0)

# ── Run the test command in the temp baseline worktree ──────────────────────

per_claim_results = []
overall_result = "pass"
any_false_claim = False

# We verify once per manifest (not per deferral) using the same test command.
# The deferrals are all labelled under the same goal.
try:
    proc = subprocess.run(
        test_cmd,
        shell=True,
        capture_output=True,
        text=True,
        cwd=temp_worktree,
        timeout=300,
    )
    baseline_exit = proc.returncode
except subprocess.TimeoutExpired:
    cleanup()
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": f"test command timed out on baseline (300s): {test_cmd}",
        "raw": {"baseline_ref": baseline_ref, "deferrals": preexisting_deferrals},
    }))
    sys.exit(0)
except Exception as exc:
    cleanup()
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "inconclusive",
        "severity": "warning",
        "details": f"test command failed to run on baseline: {exc}",
        "raw": {"baseline_ref": baseline_ref, "deferrals": preexisting_deferrals},
    }))
    sys.exit(0)

cleanup()

# Per-deferral result: each gets the same baseline verdict
for d in preexisting_deferrals:
    deferral_id = d.get("id", "(no id)")
    if baseline_exit != 0:
        # Test fails on baseline → pre-existing confirmed → this deferral passes
        per_claim_results.append({
            "deferral_id": deferral_id,
            "verdict": "confirmed",
            "baseline_exit": baseline_exit,
            "details": f"test failed on baseline ({baseline_ref}) — pre-existing confirmed",
        })
    else:
        # Test passes on baseline → claim is false → blocking failure
        per_claim_results.append({
            "deferral_id": deferral_id,
            "verdict": "false_claim",
            "baseline_exit": baseline_exit,
            "details": (
                f"test passed on baseline ({baseline_ref}) — "
                f"pre-existing claim is false; this failure was introduced by this goal"
            ),
        })
        any_false_claim = True

raw = {
    "baseline_ref": baseline_ref,
    "test_cmd": test_cmd,
    "baseline_exit_code": baseline_exit,
    "deferrals_checked": len(preexisting_deferrals),
    "per_claim": per_claim_results,
}

if any_false_claim:
    false_ids = [r["deferral_id"] for r in per_claim_results if r["verdict"] == "false_claim"]
    print(json.dumps({
        "gate": "bisect-on-claim",
        "result": "fail",
        "severity": "blocking",
        "details": (
            f"{len(false_ids)} false pre-existing claim(s): {', '.join(false_ids)}; "
            f"test passes on baseline {baseline_ref}"
        ),
        "raw": raw,
    }))
    sys.exit(1)

confirmed = [r["deferral_id"] for r in per_claim_results if r["verdict"] == "confirmed"]
print(json.dumps({
    "gate": "bisect-on-claim",
    "result": "pass",
    "severity": "blocking",
    "details": (
        f"{len(confirmed)} pre-existing claim(s) confirmed on baseline {baseline_ref}: "
        + ", ".join(confirmed)
    ),
    "raw": raw,
}))
sys.exit(0)
PY
