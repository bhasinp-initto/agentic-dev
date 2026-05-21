#!/usr/bin/env bash
# gate-scope-check.sh <manifest-path> <spec-path>
# Exits 0 on pass / 1 on fail. JSON output to stdout.
set -euo pipefail

MANIFEST="${1:-}"
SPEC="${2:-}"
if [[ -z "$MANIFEST" || -z "$SPEC" ]]; then
  echo '{"gate":"scope-check","result":"inconclusive","severity":"warning","details":"missing args"}'
  exit 1
fi

python3 - "$MANIFEST" "$SPEC" <<'PY'
import sys, json, re, fnmatch, subprocess
mpath, spec = sys.argv[1:3]
mf = json.load(open(mpath))
spec_text = open(spec).read()

# Extract "Files in scope" globs
m = re.search(r"^# Files in scope\s*$(.+?)(?=^# |\Z)", spec_text, re.MULTILINE | re.DOTALL)
globs = []
if m:
    for line in m.group(1).splitlines():
        line = line.strip()
        if line.startswith("- "):
            globs.append(line[2:].strip().strip("`"))

worktree = mf["worktree_path"]
baseline = mf["baseline_ref"]
head = mf.get("head_ref")

if not head:
    print(json.dumps({"gate":"scope-check","result":"inconclusive","severity":"warning",
                      "details":"head_ref null; no commits to check"}))
    sys.exit(0)

result = subprocess.run(["git","-C",worktree,"diff","--name-only",f"{baseline}..{head}"],
                       capture_output=True, text=True)
if result.returncode != 0:
    print(json.dumps({"gate":"scope-check","result":"inconclusive","severity":"warning",
                      "details":f"git diff failed: {result.stderr.strip()}"}))
    sys.exit(0)
touched = [f for f in result.stdout.strip().splitlines() if f]

out_of_spec = []
for f in touched:
    if not any(fnmatch.fnmatch(f, g) for g in globs):
        out_of_spec.append(f)

manifest_claim = mf.get("scope_check",{}).get("out_of_spec_files", [])
discipline_issue = sorted(out_of_spec) != sorted(manifest_claim)

if out_of_spec:
    print(json.dumps({
        "gate":"scope-check", "result":"fail", "severity":"blocking",
        "details": f"{len(out_of_spec)} out-of-spec file(s): " + ", ".join(out_of_spec),
        "raw":{
            "computed_out_of_spec": out_of_spec,
            "manifest_claim": manifest_claim,
            "discipline_issue": discipline_issue,
            "globs": globs,
            "touched_files": touched
        }
    }))
    sys.exit(1)
print(json.dumps({"gate":"scope-check","result":"pass","severity":"blocking",
                  "details":f"all {len(touched)} touched files in scope",
                  "raw":{"touched_files": touched, "globs": globs, "discipline_issue": discipline_issue}}))
sys.exit(0)
PY
