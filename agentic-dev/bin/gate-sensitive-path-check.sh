#!/usr/bin/env bash
# gate-sensitive-path-check.sh <manifest-path> <config-yaml-path>
# Exits 0 on pass / 1 on fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
CONFIG="${2:-}"
if [[ -z "$MANIFEST" || -z "$CONFIG" ]]; then
  echo '{"gate":"sensitive-path-check","result":"inconclusive","severity":"blocking","details":"missing args"}'
  exit 1
fi

python3 - "$MANIFEST" "$CONFIG" <<'PY'
import sys, json, fnmatch, subprocess
try:
    import yaml
except ImportError:
    print(json.dumps({
        "gate": "sensitive-path-check",
        "result": "inconclusive",
        "severity": "blocking",
        "details": "pyyaml not available; cannot parse config"
    }))
    sys.exit(0)

mpath, cpath = sys.argv[1:3]
mf = json.load(open(mpath))
cfg = yaml.safe_load(open(cpath))

sensitive_globs = cfg.get("sensitive_paths", []) or []

worktree = mf.get("worktree_path", "")
baseline = mf.get("baseline_ref", "")
head = mf.get("head_ref")

if not head:
    print(json.dumps({
        "gate": "sensitive-path-check",
        "result": "inconclusive",
        "severity": "blocking",
        "details": "head_ref null; no commits to check",
    }))
    sys.exit(0)

if not worktree or not baseline:
    print(json.dumps({
        "gate": "sensitive-path-check",
        "result": "inconclusive",
        "severity": "blocking",
        "details": "worktree_path or baseline_ref missing from manifest",
    }))
    sys.exit(0)

result = subprocess.run(
    ["git", "-C", worktree, "diff", "--name-only", f"{baseline}..{head}"],
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    print(json.dumps({
        "gate": "sensitive-path-check",
        "result": "inconclusive",
        "severity": "blocking",
        "details": f"git diff failed: {result.stderr.strip()}",
    }))
    sys.exit(0)

touched = [f for f in result.stdout.strip().splitlines() if f]

matched_files = []
match_reasons = []
for f in touched:
    for glob in sensitive_globs:
        if fnmatch.fnmatch(f, glob):
            matched_files.append(f)
            match_reasons.append({"file": f, "matched_glob": glob})
            break  # one glob match is enough per file

raw = {
    "touched_files": touched,
    "sensitive_globs": sensitive_globs,
    "matched_files": matched_files,
    "match_reasons": match_reasons,
}

if matched_files:
    print(json.dumps({
        "gate": "sensitive-path-check",
        "result": "fail",
        "severity": "blocking",
        "details": (
            f"{len(matched_files)} sensitive path(s) touched: "
            + ", ".join(matched_files)
        ),
        "raw": raw,
    }))
    sys.exit(1)

print(json.dumps({
    "gate": "sensitive-path-check",
    "result": "pass",
    "severity": "blocking",
    "details": (
        f"no sensitive paths touched ({len(touched)} file(s) checked "
        f"against {len(sensitive_globs)} glob(s))"
    ),
    "raw": raw,
}))
sys.exit(0)
PY
