#!/usr/bin/env bash
# gate-test-count-check.sh <manifest-path> <kickoff-path>
# Exits 0 on pass/inconclusive / 1 on fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
KICKOFF="${2:-}"
if [[ -z "$MANIFEST" || -z "$KICKOFF" ]]; then
  echo '{"gate":"test-count-check","result":"inconclusive","severity":"warning","details":"missing args"}'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$MANIFEST" "$KICKOFF" "$SCRIPT_DIR" <<'PY'
import sys, json, os

mpath, kpath = sys.argv[1:3]
script_dir = sys.argv[3]
sys.path.insert(0, script_dir)
import agentic_components as ac

mf = json.load(open(mpath))
kf = json.load(open(kpath))

# ── Multi-component baseline comparison ──────────────────────────────────────
kf_components = {c["name"]: c for c in (kf.get("components") or [])}
mf_by_comp = mf.get("tests_by_component") or []

if kf_components and mf_by_comp:
    regressions = []
    compared = []
    for claim in mf_by_comp:
        base = (kf_components.get(claim["name"]) or {}).get("baseline_test_counts")
        if base is None or base.get("passed") is None:
            continue
        compared.append(claim["name"])
        if claim.get("passed", 0) < base["passed"]:
            regressions.append(
                f"{claim['name']}: manifest {claim.get('passed', 0)} < baseline {base['passed']}")
    if regressions:
        print(json.dumps({"gate": "test-count-check", "result": "fail", "severity": "blocking",
                          "details": "per-component count regression: " + "; ".join(regressions),
                          "raw": {"compared": compared}}))
        sys.exit(1)
    print(json.dumps({"gate": "test-count-check", "result": "pass", "severity": "blocking",
                      "details": f"per-component counts >= baseline: {', '.join(compared) or 'none'}",
                      "raw": {"compared": compared}}))
    sys.exit(0)
# ── Single-component path falls through to existing logic below ───────────────

# Read kickoff baseline
baseline = kf.get("baseline", {}) or {}
baseline_counts = baseline.get("test_counts")

if baseline_counts is None:
    print(json.dumps({
        "gate": "test-count-check",
        "result": "inconclusive",
        "severity": "warning",
        "details": (
            "kickoff.baseline.test_counts is null; "
            "baseline was not captured (parse failure or no test command)"
        ),
        "raw": {"baseline_counts": None},
    }))
    sys.exit(0)

baseline_passed = baseline_counts.get("passed")
if baseline_passed is None:
    print(json.dumps({
        "gate": "test-count-check",
        "result": "inconclusive",
        "severity": "warning",
        "details": "kickoff.baseline.test_counts.passed is missing",
        "raw": {"baseline_counts": baseline_counts},
    }))
    sys.exit(0)

# Read manifest test counts
tests = mf.get("tests", {}) or {}
manifest_passed = tests.get("passed")

if manifest_passed is None:
    print(json.dumps({
        "gate": "test-count-check",
        "result": "inconclusive",
        "severity": "warning",
        "details": "manifest.tests.passed is missing",
        "raw": {
            "baseline_passed": baseline_passed,
            "manifest_passed": None,
        },
    }))
    sys.exit(0)

raw = {
    "baseline_passed": baseline_passed,
    "baseline_failed": baseline_counts.get("failed", 0),
    "baseline_skipped": baseline_counts.get("skipped", 0),
    "manifest_passed": manifest_passed,
    "manifest_failed": tests.get("failed", 0),
    "manifest_skipped": tests.get("skipped", 0),
    "delta_passed": manifest_passed - baseline_passed,
}

if manifest_passed < baseline_passed:
    drop = baseline_passed - manifest_passed
    print(json.dumps({
        "gate": "test-count-check",
        "result": "fail",
        "severity": "blocking",
        "details": (
            f"test count dropped: {manifest_passed} passed (manifest) "
            f"< {baseline_passed} passed (baseline); delta={-drop}"
        ),
        "raw": raw,
    }))
    sys.exit(1)

print(json.dumps({
    "gate": "test-count-check",
    "result": "pass",
    "severity": "blocking",
    "details": (
        f"test count ok: {manifest_passed} passed >= {baseline_passed} baseline "
        f"(delta=+{manifest_passed - baseline_passed})"
    ),
    "raw": raw,
}))
sys.exit(0)
PY
