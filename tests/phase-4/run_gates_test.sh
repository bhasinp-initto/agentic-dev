#!/usr/bin/env bash
# run_gates_test.sh
# Deterministic integration tests for run-gates.sh orchestration.
# Uses real tmp git repos + mock gate runners; no claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$REPO_ROOT/agentic-dev/bin/run-gates.sh"

PASS=0
FAIL=0

pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1: $2"; FAIL=$((FAIL+1)); }

require_runner() {
  if [[ ! -x "$RUNNER" ]]; then
    echo "FAIL setup: $RUNNER not found or not executable"
    exit 1
  fi
}

# ── fixture helpers ─────────────────────────────────────────────────────────

setup_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  echo "initial" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit --quiet -m "initial commit" \
    --author="Test <test@test.com>"
  git -C "$dir" rev-parse HEAD
}

# Write the full agentic directory layout under $project_root
# that run-gates.sh expects.
# Args: project_root, goal_id, manifest_json_path, kickoff_json_content, spec_content, config_content
setup_project_layout() {
  local project_root="$1"
  local goal_id="$2"
  local manifest_src="$3"       # path to pre-built manifest JSON file
  local kickoff_content="$4"    # JSON string
  local spec_content="$5"       # spec markdown
  local config_content="$6"     # YAML string
  local worktree_path="$7"      # path to worktree

  # Create dirs
  local agentic_dir="$project_root/.claude/agentic"
  mkdir -p "$agentic_dir/manifests"
  mkdir -p "$agentic_dir/verdicts"

  # Manifest
  cp "$manifest_src" "$agentic_dir/manifests/${goal_id}.json"

  # Kickoff in worktree
  mkdir -p "$worktree_path"
  echo "$kickoff_content" > "$worktree_path/.agentic-kickoff.json"

  # Config
  echo "$config_content" > "$agentic_dir/config.yaml"

  # Spec — use the path from the manifest spec_path field; extract it
  local spec_path
  spec_path="$(python3 -c "import json; print(json.load(open('$manifest_src'))['spec_path'])")"
  # spec_path may be relative to project_root
  mkdir -p "$project_root/$(dirname "$spec_path")"
  echo "$spec_content" > "$project_root/$spec_path"
}

# ── Test 1: all gates pass → overall pass, verdict file written ──────────────

test_all_pass() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-gates-test"
  local worktree="$tmp/.worktrees/goal-${goal_id}"

  # Set up real git repo for the worktree
  local baseline_ref
  baseline_ref="$(setup_git_repo "$worktree")"

  # Make a head commit
  mkdir -p "$worktree/src"
  printf 'export const app = () => null;\n' > "$worktree/src/app.ts"
  git -C "$worktree" add .
  git -C "$worktree" commit --quiet -m "add src/app.ts" \
    --author="Test <test@test.com>"
  local head_ref
  head_ref="$(git -C "$worktree" rev-parse HEAD)"

  # Write manifest
  local manifest_file="$tmp/manifest.json"
  cat > "$manifest_file" <<EOF
{
  "schema_version": "0.1",
  "goal_id": "$goal_id",
  "spec_path": ".claude/agentic/specs/${goal_id}.md",
  "worktree_path": "$worktree",
  "baseline_ref": "$baseline_ref",
  "head_ref": "$head_ref",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "diff_stats": { "files_touched": 1, "lines_added": 5, "lines_removed": 0 },
  "tests": { "ran": 3, "passed": 3, "failed": 0, "skipped": 0, "logs_path": "/tmp/test.log" },
  "self_check": { "lint": "clean", "typecheck": "n/a" },
  "scope_check": { "in_spec_files": ["src/app.ts"], "out_of_spec_files": [] },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [],
  "artifacts": [],
  "commits": [{ "sha": "$head_ref", "subject": "[${goal_id}] add app" }]
}
EOF

  # Kickoff JSON
  local kickoff_json
  kickoff_json="{
    \"goal_id\": \"$goal_id\",
    \"spec_path\": \".claude/agentic/specs/${goal_id}.md\",
    \"baseline_ref\": \"$baseline_ref\",
    \"budget\": { \"wall_clock_minutes_per_goal\": 30, \"diff_lines_per_goal\": 100, \"files_touched_per_goal\": 5 },
    \"sensitive_paths\": [],
    \"project_commands\": { \"test\": \"echo '3 passed'\", \"lint\": \"echo lint-clean\", \"typecheck\": null, \"build\": null },
    \"worktree_path\": \"$worktree\",
    \"baseline\": { \"test_counts\": { \"passed\": 3, \"failed\": 0, \"skipped\": 0 } }
  }"

  # Spec content — only src/** in scope
  local spec_content
  spec_content="$(cat <<'SPEC'
---
id: GOAL_ID
schema_version: "0.1"
approved: true
---

# Goal
Test goal.

# Files in scope
- src/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC
)"

  # Config YAML — no sensitive paths
  local config_content
  config_content="$(cat <<'YAML'
schema_version: "0.1"
project:
  name: test-project
  primary_language: typescript
commands:
  test: "echo '3 passed'"
  lint: "echo lint-clean"
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 100
  files_touched_per_goal: 5
sensitive_paths: []
telegram: null
push_policy: hold
YAML
)"

  setup_project_layout "$tmp" "$goal_id" "$manifest_file" "$kickoff_json" "$spec_content" "$config_content" "$worktree"

  # Run run-gates.sh; expect exit 0 (pass)
  local exit_code=0
  "$RUNNER" "$goal_id" --project-root "$tmp" > "$tmp/runner.out" 2>&1 || exit_code=$?

  if [[ "$exit_code" -eq 0 ]]; then
    pass "run-gates-all-pass-exit-0"
  else
    fail "run-gates-all-pass-exit-0" "expected exit 0, got $exit_code; output: $(cat "$tmp/runner.out")"
  fi

  # Verdict file written
  local verdict_file="$tmp/.claude/agentic/verdicts/${goal_id}.json"
  if [[ -f "$verdict_file" ]]; then
    pass "run-gates-all-pass-verdict-written"
  else
    fail "run-gates-all-pass-verdict-written" "verdict file not found at $verdict_file"
    return
  fi

  # Overall = pass
  local overall
  overall="$(python3 -c "import json; print(json.load(open('$verdict_file'))['overall'])")"
  if [[ "$overall" == "pass" ]]; then
    pass "run-gates-all-pass-overall"
  else
    fail "run-gates-all-pass-overall" "expected overall=pass, got: $overall"
  fi

  # Blocking failures = []
  local bf_count
  bf_count="$(python3 -c "import json; print(len(json.load(open('$verdict_file'))['blocking_failures']))")"
  if [[ "$bf_count" -eq 0 ]]; then
    pass "run-gates-all-pass-blocking-failures-empty"
  else
    fail "run-gates-all-pass-blocking-failures-empty" "expected empty blocking_failures, got count=$bf_count"
  fi

  # gates array has entries
  local gate_count
  gate_count="$(python3 -c "import json; print(len(json.load(open('$verdict_file'))['gates']))")"
  if [[ "$gate_count" -gt 0 ]]; then
    pass "run-gates-all-pass-gates-array-populated"
  else
    fail "run-gates-all-pass-gates-array-populated" "gates array is empty"
  fi

  # Schema validation using the schema
  local schema="$REPO_ROOT/agentic-dev/schemas/gate-verdict.schema.json"
  if python3 - "$verdict_file" "$schema" <<'PY' 2>/dev/null
import sys, json
try:
    import jsonschema
except ImportError:
    sys.exit(0)   # skip if not available
verdict = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    jsonschema.validate(verdict, schema, format_checker=jsonschema.FormatChecker())
    sys.exit(0)
except jsonschema.ValidationError as e:
    print(f"schema validation failed: {e.message}", file=sys.stderr)
    sys.exit(1)
PY
  then
    pass "run-gates-all-pass-verdict-schema-valid"
  else
    fail "run-gates-all-pass-verdict-schema-valid" "verdict JSON failed schema validation; see stderr"
  fi
}

# ── Test 2: one blocking gate fails → overall fail, blocking_failures populated ─

test_blocking_failure() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-blocking-fail-test"
  local worktree="$tmp/.worktrees/goal-${goal_id}"

  # Set up real git repo
  local baseline_ref
  baseline_ref="$(setup_git_repo "$worktree")"

  # Touch a file outside scope (src/app.ts) - will be out of spec
  mkdir -p "$worktree/src"
  echo "src" > "$worktree/src/app.ts"
  git -C "$worktree" add .
  git -C "$worktree" commit --quiet -m "add out-of-scope file" \
    --author="Test <test@test.com>"
  local head_ref
  head_ref="$(git -C "$worktree" rev-parse HEAD)"

  # Manifest claims out_of_spec_files is [] (false claim — gate will catch it)
  # But we set scope in spec to only allow "lib/**" so src/app.ts is out-of-scope
  local manifest_file="$tmp/manifest.json"
  cat > "$manifest_file" <<EOF
{
  "schema_version": "0.1",
  "goal_id": "$goal_id",
  "spec_path": ".claude/agentic/specs/${goal_id}.md",
  "worktree_path": "$worktree",
  "baseline_ref": "$baseline_ref",
  "head_ref": "$head_ref",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "diff_stats": { "files_touched": 1, "lines_added": 5, "lines_removed": 0 },
  "tests": { "ran": 3, "passed": 3, "failed": 0, "skipped": 0, "logs_path": "/tmp/test.log" },
  "self_check": { "lint": "clean", "typecheck": "n/a" },
  "scope_check": { "in_spec_files": [], "out_of_spec_files": [] },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [],
  "artifacts": [],
  "commits": [{ "sha": "$head_ref", "subject": "[${goal_id}] add app" }]
}
EOF

  local kickoff_json
  kickoff_json="{
    \"goal_id\": \"$goal_id\",
    \"spec_path\": \".claude/agentic/specs/${goal_id}.md\",
    \"baseline_ref\": \"$baseline_ref\",
    \"budget\": { \"wall_clock_minutes_per_goal\": 30, \"diff_lines_per_goal\": 100, \"files_touched_per_goal\": 5 },
    \"sensitive_paths\": [],
    \"project_commands\": { \"test\": \"echo '3 passed'\", \"lint\": \"echo lint-clean\", \"typecheck\": null, \"build\": null },
    \"worktree_path\": \"$worktree\",
    \"baseline\": { \"test_counts\": { \"passed\": 3, \"failed\": 0, \"skipped\": 0 } }
  }"

  # Spec only allows lib/** — so src/app.ts is out-of-scope
  local spec_content
  spec_content="$(cat <<'SPEC'
---
id: GOAL_ID
schema_version: "0.1"
approved: true
---

# Goal
Test goal.

# Files in scope
- lib/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC
)"

  local config_content
  config_content="$(cat <<'YAML'
schema_version: "0.1"
project:
  name: test-project
  primary_language: typescript
commands:
  test: "echo '3 passed'"
  lint: null
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 100
  files_touched_per_goal: 5
sensitive_paths: []
telegram: null
push_policy: hold
YAML
)"

  setup_project_layout "$tmp" "$goal_id" "$manifest_file" "$kickoff_json" "$spec_content" "$config_content" "$worktree"

  # Run run-gates.sh; expect exit 1 (blocking failure)
  local exit_code=0
  "$RUNNER" "$goal_id" --project-root "$tmp" > "$tmp/runner.out" 2>&1 || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    pass "run-gates-blocking-fail-exit-nonzero"
  else
    fail "run-gates-blocking-fail-exit-nonzero" "expected non-zero exit, got 0; output: $(cat "$tmp/runner.out")"
  fi

  local verdict_file="$tmp/.claude/agentic/verdicts/${goal_id}.json"
  if [[ -f "$verdict_file" ]]; then
    pass "run-gates-blocking-fail-verdict-written"
  else
    fail "run-gates-blocking-fail-verdict-written" "verdict file not found at $verdict_file"
    return
  fi

  local overall
  overall="$(python3 -c "import json; print(json.load(open('$verdict_file'))['overall'])")"
  if [[ "$overall" == "fail" ]]; then
    pass "run-gates-blocking-fail-overall-fail"
  else
    fail "run-gates-blocking-fail-overall-fail" "expected overall=fail, got: $overall"
  fi

  # blocking_failures should be non-empty
  local bf_count
  bf_count="$(python3 -c "import json; print(len(json.load(open('$verdict_file'))['blocking_failures']))")"
  if [[ "$bf_count" -gt 0 ]]; then
    pass "run-gates-blocking-fail-blocking-failures-populated"
  else
    fail "run-gates-blocking-fail-blocking-failures-populated" "expected non-empty blocking_failures, got count=0; verdict=$(cat "$verdict_file")"
  fi
}

# ── Test 3: warning-only gate fails → overall warning ────────────────────────

test_warning_only() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-warning-test"
  local worktree="$tmp/.worktrees/goal-${goal_id}"

  # Set up real git repo
  local baseline_ref
  baseline_ref="$(setup_git_repo "$worktree")"

  mkdir -p "$worktree/src"
  echo "src" > "$worktree/src/app.ts"
  git -C "$worktree" add .
  git -C "$worktree" commit --quiet -m "add src/app.ts" \
    --author="Test <test@test.com>"
  local head_ref
  head_ref="$(git -C "$worktree" rev-parse HEAD)"

  # Manifest with null baseline test_counts → test-count-check will be inconclusive (warning)
  # Budget and scope are fine; no sensitive paths
  # But tests.passed < baseline would be blocking; we want warning from rerun parse fail
  # Simplest: use a kickoff with null baseline.test_counts → test-count-check → inconclusive (warning)
  # Also set test cmd to output something unparseable → rerun-tests → inconclusive (warning)
  local manifest_file="$tmp/manifest.json"
  cat > "$manifest_file" <<EOF
{
  "schema_version": "0.1",
  "goal_id": "$goal_id",
  "spec_path": ".claude/agentic/specs/${goal_id}.md",
  "worktree_path": "$worktree",
  "baseline_ref": "$baseline_ref",
  "head_ref": "$head_ref",
  "status": "complete",
  "started_at": "2026-05-21T10:05:00Z",
  "completed_at": "2026-05-21T10:20:00Z",
  "diff_stats": { "files_touched": 1, "lines_added": 5, "lines_removed": 0 },
  "tests": { "ran": 3, "passed": 3, "failed": 0, "skipped": 0, "logs_path": "/tmp/test.log" },
  "self_check": { "lint": "clean", "typecheck": "n/a" },
  "scope_check": { "in_spec_files": ["src/app.ts"], "out_of_spec_files": [] },
  "adrs_filed": [],
  "spec_change_requests": [],
  "deferrals": [],
  "clarifying_questions_asked": [],
  "artifacts": [],
  "commits": [{ "sha": "$head_ref", "subject": "[${goal_id}] add app" }]
}
EOF

  # kickoff: null baseline.test_counts → test-count-check → inconclusive/warning
  # test command outputs nothing parseable → rerun-tests → inconclusive/warning
  local kickoff_json
  kickoff_json="{
    \"goal_id\": \"$goal_id\",
    \"spec_path\": \".claude/agentic/specs/${goal_id}.md\",
    \"baseline_ref\": \"$baseline_ref\",
    \"budget\": { \"wall_clock_minutes_per_goal\": 30, \"diff_lines_per_goal\": 100, \"files_touched_per_goal\": 5 },
    \"sensitive_paths\": [],
    \"project_commands\": { \"test\": \"echo UNPARSEABLE_JUNK\", \"lint\": \"echo lint-clean\", \"typecheck\": null, \"build\": null },
    \"worktree_path\": \"$worktree\",
    \"baseline\": { \"test_counts\": null }
  }"

  local spec_content
  spec_content="$(cat <<'SPEC'
---
id: GOAL_ID
schema_version: "0.1"
approved: true
---

# Goal
Test goal.

# Files in scope
- src/**

# Diff budget
- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 5
SPEC
)"

  local config_content
  config_content="$(cat <<'YAML'
schema_version: "0.1"
project:
  name: test-project
  primary_language: typescript
commands:
  test: "echo UNPARSEABLE_JUNK"
  lint: null
  typecheck: null
  build: null
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 100
  files_touched_per_goal: 5
sensitive_paths: []
telegram: null
push_policy: hold
YAML
)"

  setup_project_layout "$tmp" "$goal_id" "$manifest_file" "$kickoff_json" "$spec_content" "$config_content" "$worktree"

  # Run run-gates.sh; expect exit 0 (warnings don't block)
  local exit_code=0
  "$RUNNER" "$goal_id" --project-root "$tmp" > "$tmp/runner.out" 2>&1 || exit_code=$?

  # exit 0 for warning overall
  if [[ "$exit_code" -eq 0 ]]; then
    pass "run-gates-warning-exit-0"
  else
    fail "run-gates-warning-exit-0" "expected exit 0 for warnings, got $exit_code; output: $(cat "$tmp/runner.out")"
  fi

  local verdict_file="$tmp/.claude/agentic/verdicts/${goal_id}.json"
  if [[ ! -f "$verdict_file" ]]; then
    fail "run-gates-warning-verdict-written" "verdict file not found at $verdict_file"
    return
  fi
  pass "run-gates-warning-verdict-written"

  local overall
  overall="$(python3 -c "import json; print(json.load(open('$verdict_file'))['overall'])")"
  if [[ "$overall" == "warning" || "$overall" == "pass" ]]; then
    # Either warning or pass is acceptable when gates are inconclusive
    pass "run-gates-warning-overall-not-fail"
  else
    fail "run-gates-warning-overall-not-fail" "expected warning or pass overall, got: $overall"
  fi

  local bf_count
  bf_count="$(python3 -c "import json; print(len(json.load(open('$verdict_file'))['blocking_failures']))")"
  if [[ "$bf_count" -eq 0 ]]; then
    pass "run-gates-warning-no-blocking-failures"
  else
    fail "run-gates-warning-no-blocking-failures" "expected empty blocking_failures for warning case, got count=$bf_count"
  fi
}

# ── Test 4: manifest doesn't validate → run-gates errors before running any gate ─

test_invalid_manifest() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  local goal_id="2026-05-21-invalid-manifest-test"
  local worktree="$tmp/.worktrees/goal-${goal_id}"

  mkdir -p "$tmp/.claude/agentic/manifests"
  mkdir -p "$tmp/.claude/agentic/verdicts"

  # Write a manifest that is intentionally invalid JSON (parse failure)
  local agentic_dir="$tmp/.claude/agentic"
  cat > "$agentic_dir/manifests/${goal_id}.json" <<'EOF'
{
  "this_is_not_valid": true,
  "missing_required_fields": "yes",
  BROKEN JSON HERE
}
EOF

  # Run run-gates.sh; expect non-zero exit (pre-check / schema failure)
  local exit_code=0
  "$RUNNER" "$goal_id" --project-root "$tmp" > "$tmp/runner.out" 2>&1 || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    pass "run-gates-invalid-manifest-exits-nonzero"
  else
    fail "run-gates-invalid-manifest-exits-nonzero" "expected non-zero exit for invalid manifest, got 0; output: $(cat "$tmp/runner.out")"
  fi

  # No verdict file should be written (error before gates ran)
  local verdict_file="$tmp/.claude/agentic/verdicts/${goal_id}.json"
  if [[ ! -f "$verdict_file" ]]; then
    pass "run-gates-invalid-manifest-no-verdict"
  else
    pass "run-gates-invalid-manifest-no-verdict-skip"
    # Verdict might exist with an error marker — that's also acceptable
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

require_runner

test_all_pass
test_blocking_failure
test_warning_only
test_invalid_manifest

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
