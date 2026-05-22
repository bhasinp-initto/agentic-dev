#!/usr/bin/env bash
# Tests for bin/query-checklist.sh.
# Deterministic; zero claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QUERY="$REPO_ROOT/agentic-dev/bin/query-checklist.sh"

TMP="$(mktemp -d -t agentic-query-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved: $TMP" || rm -rf "$TMP"' EXIT
cd "$TMP"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $*" >&2; }

# Setup: an agentic-dev-shaped checklist.yaml with 4 entries
mkdir -p .claude/agentic
cat > .claude/agentic/checklist.yaml <<'YAML'
schema_version: "0.1"
entries:
  - date: "2026-05-01"
    incident_ref: "ESC-001"
    rule: "When code adds a new database query, verify it goes through the tenant-scoped repository pattern, not raw client"
    caught_by: "reviewer"
  - date: "2026-05-05"
    incident_ref: "ESC-002"
    rule: "Convex mutations must use ctx.auth.getUserIdentity() instead of accepting userId as an argument; otherwise IDOR is possible"
    caught_by: "reviewer"
  - date: "2026-05-10"
    incident_ref: "ESC-003"
    rule: "Flask CORS must be restricted to localhost:5173 in dev; unrestricted CORS is a security smell"
    caught_by: "gate"
  - date: "2026-05-15"
    incident_ref: "ESC-004"
    rule: "All new public functions in TypeScript modules must have JSDoc comments documenting parameters and return types"
    caught_by: "adversary"
YAML

# --- 1. Missing checklist file → exit 1 ---
TMP_BAD=$(mktemp -d)
cd "$TMP_BAD"
set +e
"$QUERY" "anything" 2>/dev/null
EX=$?
set -e
cd "$TMP"
if [[ $EX -eq 1 ]]; then
  pass "missing checklist.yaml → exit 1"
else
  fail "expected exit 1 on missing file, got $EX"
fi

# --- 2. Empty query → exit 2 ---
set +e
"$QUERY" "" 2>/dev/null
EX=$?
set -e
if [[ $EX -eq 2 ]]; then
  pass "empty query → exit 2 (usage)"
else
  fail "expected exit 2 on empty query, got $EX"
fi

# --- 3. IDOR query → top result should be the Convex/ctx.auth rule ---
OUT=$("$QUERY" "convex mutation userId IDOR auth")
TOP_REF=$(echo "$OUT" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["incident_ref"])')
if [[ "$TOP_REF" == "ESC-002" ]]; then
  pass "IDOR query: top result is the Convex IDOR rule (ESC-002)"
else
  fail "IDOR query top result should be ESC-002, got $TOP_REF; output: $OUT"
fi

# --- 4. CORS query → top result should be the Flask CORS rule ---
OUT=$("$QUERY" "Flask CORS unrestricted security")
TOP_REF=$(echo "$OUT" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["incident_ref"])')
if [[ "$TOP_REF" == "ESC-003" ]]; then
  pass "CORS query: top result is the Flask CORS rule (ESC-003)"
else
  fail "CORS query top result should be ESC-003, got $TOP_REF; output: $OUT"
fi

# --- 5. JSDoc query → top result should be the docstring rule ---
OUT=$("$QUERY" "TypeScript function JSDoc comment documentation")
TOP_REF=$(echo "$OUT" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["incident_ref"])')
if [[ "$TOP_REF" == "ESC-004" ]]; then
  pass "JSDoc query: top result is the docstring rule (ESC-004)"
else
  fail "JSDoc query top result should be ESC-004, got $TOP_REF; output: $OUT"
fi

# --- 6. Database query → top should be tenant-repo rule ---
OUT=$("$QUERY" "database query tenant raw client repository")
TOP_REF=$(echo "$OUT" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["incident_ref"])')
if [[ "$TOP_REF" == "ESC-001" ]]; then
  pass "DB tenant query: top result is the tenant-repo rule (ESC-001)"
else
  fail "DB tenant query top result should be ESC-001, got $TOP_REF; output: $OUT"
fi

# --- 7. Top-K limit honored ---
COUNT=$("$QUERY" "function code" -k 2 | wc -l | tr -d ' ')
if [[ "$COUNT" -le 2 && "$COUNT" -ge 1 ]]; then
  pass "top-K limit honored (got $COUNT entries with -k 2)"
else
  fail "top-K=2 should return <= 2 entries, got $COUNT"
fi

# --- 8. Output is valid JSONL ---
OUT=$("$QUERY" "convex mutation security")
while IFS= read -r line; do
  if [[ -n "$line" ]]; then
    if ! echo "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
      fail "non-JSON line in output: $line"
      break
    fi
  fi
done <<< "$OUT"
pass "JSONL output: every line is valid JSON"

# --- 9. Results sorted by descending score ---
OUT=$("$QUERY" "security CORS Convex auth")
SCORES=$(echo "$OUT" | python3 -c '
import sys, json
scores = []
for line in sys.stdin:
    if line.strip():
        scores.append(json.loads(line)["score"])
ok = all(scores[i] >= scores[i+1] for i in range(len(scores)-1))
print("OK" if ok else "BAD")
')
if [[ "$SCORES" == "OK" ]]; then
  pass "results sorted by descending score"
else
  fail "results NOT sorted by descending score; output: $OUT"
fi

# --- 10. No matches → no output, exit 0 ---
set +e
OUT=$("$QUERY" "quantum cryptography blockchain machine learning")
EX=$?
set -e
if [[ $EX -eq 0 ]]; then
  # OUT may be empty (no token overlap) — that's the success-no-matches case
  pass "no-match query: exits 0 (output empty or low-score: $(echo -n "$OUT" | wc -c) chars)"
else
  fail "no-match query should exit 0, got $EX"
fi

# --- 11. Rank field starts at 1, monotonically increases ---
OUT=$("$QUERY" "function tenant security")
RANKS=$(echo "$OUT" | python3 -c '
import sys, json
ranks = [json.loads(l)["rank"] for l in sys.stdin if l.strip()]
expected = list(range(1, len(ranks)+1))
print("OK" if ranks == expected else f"BAD: {ranks}")
')
if [[ "$RANKS" == "OK" ]]; then
  pass "rank field starts at 1 and increases monotonically"
else
  fail "rank field broken: $RANKS"
fi

# --- 12. Empty entries array → exit 0, no output ---
cat > .claude/agentic/checklist.yaml <<'YAML'
schema_version: "0.1"
entries: []
YAML
set +e
OUT=$("$QUERY" "anything")
EX=$?
set -e
if [[ $EX -eq 0 && -z "$OUT" ]]; then
  pass "empty checklist.entries → exit 0, no output"
else
  fail "empty entries should exit 0 with no output; got exit $EX, output: $OUT"
fi

echo
echo "query_checklist_test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
