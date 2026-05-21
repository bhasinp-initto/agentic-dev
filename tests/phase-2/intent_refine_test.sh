#!/usr/bin/env bash
# Verify /agentic-dev:intent --refine <spec-path> re-runs the drafter on a
# partial spec, preserving the human's existing answers and emitting zero
# or more new QUESTION-N blocks if answers exposed new ambiguities.
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.claude/agentic-dev-test.env" ] && source "$HOME/.claude/agentic-dev-test.env"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/agentic-dev"
INIT_FIXTURE="$REPO_ROOT/tests/phase-1/fixtures/init-input.yaml"

TMP_PROJECT="$(mktemp -d -t agentic-refine-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved tmp project at: $TMP_PROJECT" || rm -rf "$TMP_PROJECT"' EXIT

cd "$TMP_PROJECT"
git init -q
git -c user.email=test@test -c user.name=test commit -q --allow-empty -m "initial"

# Init + first intent
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  --add-dir "$(dirname "$INIT_FIXTURE")" \
  -p "/agentic-dev:init $INIT_FIXTURE" >/dev/null 2>&1 || true

claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent Add rate limiting per-tenant to the API" >/dev/null 2>&1 || true

spec_files=(.claude/agentic/specs/*.md)
if [[ "${spec_files[0]}" == ".claude/agentic/specs/*.md" ]]; then
  echo "FAIL setup: fresh /agentic-dev:intent did not produce any spec file" >&2
  ls -la .claude/agentic/specs/ >&2 || true
  exit 1
fi
SPEC="${spec_files[0]}"

# Answer the first QUESTION-N block; leave the rest unanswered
python3 - <<PY
import re
text = open("$SPEC").read()
# Find the first QUESTION block and replace its "Your answer:" line with "A"
def replace_first_answer(match):
    block = match.group(0)
    return re.sub(r"\*\*Your answer:\*\*.*", "**Your answer:** A", block, count=1)
new_text = re.sub(
    r"<!-- QUESTION-1 [^>]+-->.*?\*\*Your answer:\*\*[^\n]*",
    replace_first_answer,
    text,
    count=1,
    flags=re.DOTALL,
)
open("$SPEC", "w").write(new_text)
PY

# Snapshot the spec before refining
cp "$SPEC" "$SPEC.before-refine"

# Run refine
refine_out="$TMP_PROJECT/_refine_output.txt"
claude --plugin-dir "$PLUGIN_DIR" \
  --dangerously-skip-permissions \
  -p "/agentic-dev:intent --refine $SPEC" >"$refine_out" 2>&1 || true

if [[ ! -f "$SPEC" ]]; then
  echo "FAIL: spec file disappeared after refine" >&2
  cat "$refine_out" >&2
  exit 1
fi

# The refine output must confirm that --refine mode ran (not fall back to
# "not supported" or silently do nothing). Look for the "(refined)" annotation
# or "intent drafted" in the output (skill prints one of these on success).
if ! grep -qE '\(refined\)|intent drafted' "$refine_out"; then
  echo "FAIL: --refine mode was not recognized by the skill (no '(refined)' or 'intent drafted' in output; error refusals also indicate non-recognition)" >&2
  cat "$refine_out" >&2
  exit 1
fi
echo "PASS --refine mode was recognized by the skill"

# The answer to QUESTION-1 must still be "A"
if ! grep -qE '\*\*Your answer:\*\* A' "$SPEC"; then
  echo "FAIL: --refine overwrote the human's answer to QUESTION-1" >&2
  diff "$SPEC.before-refine" "$SPEC" >&2 || true
  exit 1
fi
echo "PASS --refine preserved the human's answer to QUESTION-1"

# The frontmatter id must be unchanged
id_before=$(awk '/^id:/{print $2; exit}' "$SPEC.before-refine")
id_after=$(awk '/^id:/{print $2; exit}' "$SPEC")
if [[ "$id_before" != "$id_after" ]]; then
  echo "FAIL: --refine changed frontmatter id ($id_before -> $id_after)" >&2
  exit 1
fi
echo "PASS --refine preserved frontmatter id"

# The deterministic validator must still pass (approved is still false)
"$PLUGIN_DIR/bin/validate-spec.sh" "$SPEC"
echo "PASS --refine output still passes deterministic validation"

echo "intent_refine_test: OK"
