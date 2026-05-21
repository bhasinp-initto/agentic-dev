#!/usr/bin/env bash
# End-to-end test of the approval gate: /agentic-dev:_check-approval on each
# of the three fixtures (clean, unmeasurable, incoherent). Asserts the AI
# validator's verdict and post-conditions on the spec file.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"
FIXTURE_DIR="$REPO_ROOT/tests/phase-2/fixtures"

run_one() {
  local fixture_name="$1"
  local expected_verdict="$2"  # "clean" or "concerns"
  local expected_category="$3" # only meaningful when verdict=concerns

  TMP_PROJECT="$(mktemp -d -t agentic-approval-XXXXXX)"
  trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' RETURN

  cd "$TMP_PROJECT"
  git init -q
  git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

  claude --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --add-dir "$(dirname "$INIT_FIXTURE")" \
    -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

  mkdir -p .claude/agentic/intents .claude/agentic/specs

  # Copy the fixture into the throwaway project. The fixture references an
  # intent file path; we create a stub intent file at that path so the
  # deterministic validator's intent_path check passes.
  cp "$FIXTURE_DIR/$fixture_name" ".claude/agentic/specs/$fixture_name"
  spec_id=$(awk '/^id:/{print $2; exit}' ".claude/agentic/specs/$fixture_name")
  echo "stub" > ".claude/agentic/intents/${spec_id}.md"

  # Set approved=true in the fixture (the gate fires on the flip)
  sed -i.bak 's/^approved: false$/approved: true/' ".claude/agentic/specs/$fixture_name"
  rm -f ".claude/agentic/specs/$fixture_name.bak"

  # Run the check-approval skill
  approval_out="$TMP_PROJECT/_approval_output.txt"
  claude --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    -p "/agentic-dev:_check-approval .claude/agentic/specs/$fixture_name" >"$approval_out" 2>&1 || true

  case "$expected_verdict" in
    clean)
      if ! grep -qE 'verdict: clean' "$approval_out"; then
        echo "FAIL $fixture_name: expected verdict=clean; got:" >&2
        cat "$approval_out" >&2
        return 1
      fi
      # approved should still be true
      if ! grep -qE '^approved:\s*true' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: approved was reverted on a clean verdict" >&2
        return 1
      fi
      echo "PASS $fixture_name: verdict=clean, approved preserved"
      ;;
    concerns)
      if ! grep -qE 'verdict: concerns' "$approval_out"; then
        echo "FAIL $fixture_name: expected verdict=concerns; got:" >&2
        cat "$approval_out" >&2
        return 1
      fi
      if ! grep -qE "category: $expected_category" "$approval_out"; then
        echo "FAIL $fixture_name: expected category=$expected_category in concerns" >&2
        cat "$approval_out" >&2
        return 1
      fi
      # approved should have been reverted to false
      if ! grep -qE '^approved:\s*false' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: approved was NOT reverted on a concerns verdict" >&2
        return 1
      fi
      # New QUESTION-N block(s) should have been written
      if ! grep -qE '<!-- QUESTION-[0-9]+ ' ".claude/agentic/specs/$fixture_name"; then
        echo "FAIL $fixture_name: no new QUESTION-N block was added on a concerns verdict" >&2
        return 1
      fi
      echo "PASS $fixture_name: verdict=concerns, approved reverted, new QUESTION added"
      ;;
  esac
}

run_one spec-clean.md clean ""
run_one spec-unmeasurable-criteria.md concerns completion-criterion
run_one spec-scope-incoherent.md concerns scope-coherence

echo "approval_gate_test: OK"
