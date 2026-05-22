#!/usr/bin/env bash
# Tests for bin/check-pii.sh.
# Deterministic; zero claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$REPO_ROOT/agentic-dev/bin/check-pii.sh"

TMP="$(mktemp -d -t agentic-pii-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved: $TMP" || rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $*" >&2; }

# Helper: write content to a file, run check, capture exit + jsonl output
run_check() {
  local content="$1"
  local file="$TMP/case-$$-$RANDOM.txt"
  printf '%s' "$content" > "$file"
  set +e
  OUT="$("$CHECK" "$file" 2>&1)"
  EXIT=$?
  set -e
  rm -f "$file"
}

# --- 1. Empty file → no findings, exit 0 ---
run_check ""
if [[ $EXIT -eq 0 && -z "$OUT" ]]; then
  pass "empty file: no findings, exit 0"
else
  fail "empty file: expected exit 0, no output; got exit $EXIT, output: $OUT"
fi

# --- 2. Anthropic API key → high severity, exit 1 ---
run_check "ANTHROPIC_API_KEY=sk-ant-api03-TBM0l1AORZnsThZsZpAmVbMZZbYeCcjW2fgf3edaSj9mmvCO7"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "anthropic-api-key"'; then
  pass "anthropic-api-key detected (exit 1, finding emitted)"
else
  fail "anthropic-api-key not detected: exit $EXIT, output: $OUT"
fi

# Verify the matched value is redacted, not printed in full
if echo "$OUT" | grep -q 'sk-ant-api03-TBM0l1AORZnsThZsZpAmVbMZZbYeCcjW2fgf3edaSj9mmvCO7'; then
  fail "anthropic-api-key found in plain text in output (should be redacted)"
else
  pass "anthropic-api-key value redacted, not printed in plain text"
fi

# --- 3. AWS access key → high severity ---
run_check "Use this: AKIAIOSFODNN7EXAMPLE for testing"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "aws-access-key-id"'; then
  pass "aws-access-key-id detected"
else
  fail "aws-access-key-id not detected: exit $EXIT, output: $OUT"
fi

# --- 4. GitHub PAT → high severity ---
run_check "token=ghp_1234567890abcdefghijklmnopqrstuvwxyz12"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "github-pat"'; then
  pass "github-pat detected"
else
  fail "github-pat not detected: exit $EXIT, output: $OUT"
fi

# --- 5. Slack bot token → high severity ---
run_check "SLACK=xoxb-1234567890-abcdefghijkl"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "slack-token"'; then
  pass "slack-token detected"
else
  fail "slack-token not detected: exit $EXIT, output: $OUT"
fi

# --- 6. DB connection string with creds → high severity ---
run_check "DB=postgresql://admin:supersecret@db.example.com:5432/myapp"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "db-conn-string-with-creds"'; then
  pass "db-conn-string-with-creds detected"
else
  fail "db-conn-string-with-creds not detected: exit $EXIT, output: $OUT"
fi

# --- 7. Private key block → high severity ---
run_check "-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...
-----END RSA PRIVATE KEY-----"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "private-key-pem"'; then
  pass "private-key-pem detected"
else
  fail "private-key-pem not detected: exit $EXIT, output: $OUT"
fi

# --- 8. Telegram bot token format ---
run_check "bot_token: 123456789:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
if [[ $EXIT -eq 1 ]] && echo "$OUT" | grep -q '"pattern": "telegram-bot-token"'; then
  pass "telegram-bot-token detected"
else
  fail "telegram-bot-token not detected: exit $EXIT, output: $OUT"
fi

# --- 9. JWT → medium severity (does not trigger exit 1) ---
run_check "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.abc123def456"
if [[ $EXIT -eq 0 ]] && echo "$OUT" | grep -q '"pattern": "jwt-token"'; then
  pass "jwt-token detected as medium (exit 0, finding emitted)"
else
  fail "jwt-token not detected at medium: exit $EXIT, output: $OUT"
fi

# --- 10. Inline api_key= assignment → medium severity ---
run_check 'config = { "api_key": "abcdef123456789012345678901234567890" }'
if [[ $EXIT -eq 0 ]] && echo "$OUT" | grep -q '"pattern": "inline-api-key-assignment"'; then
  pass "inline-api-key-assignment detected as medium"
else
  fail "inline-api-key-assignment not detected: exit $EXIT, output: $OUT"
fi

# --- 11. Git SHA → should NOT trigger (40 chars is below our high-entropy hex threshold of 48) ---
run_check "baseline_ref: 1234567890abcdef1234567890abcdef12345678"
if [[ $EXIT -eq 0 ]] && ! echo "$OUT" | grep -q '"pattern": "high-entropy-hex"'; then
  pass "git SHA (40 hex) does not trigger high-entropy-hex"
else
  fail "git SHA wrongly triggered high-entropy-hex: exit $EXIT, output: $OUT"
fi

# --- 12. UUID → should NOT trigger (well-known format, not in our pattern set) ---
run_check "session_id: 550e8400-e29b-41d4-a716-446655440000"
if [[ $EXIT -eq 0 && -z "$OUT" ]]; then
  pass "UUID does not trigger any pattern"
else
  fail "UUID wrongly triggered a pattern: exit $EXIT, output: $OUT"
fi

# --- 13. Normal prose → no findings ---
run_check "This is a regular sentence describing a goal. The implementer should add a /health endpoint that returns 200 OK with JSON body {\"status\": \"healthy\"}. Tests live in tests/health.test.ts."
if [[ $EXIT -eq 0 && -z "$OUT" ]]; then
  pass "normal prose: no false positives"
else
  fail "normal prose wrongly triggered patterns: exit $EXIT, output: $OUT"
fi

# --- 14. Multiple findings → exit code reflects highest severity (high → exit 1) ---
run_check "key1=sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890
jwt=eyJabc.eyJdef.ghi
db=postgres://u:p@host/db"
if [[ $EXIT -eq 1 ]]; then
  FOUND_COUNT=$(echo "$OUT" | grep -c '"pattern"')
  if [[ $FOUND_COUNT -ge 3 ]]; then
    pass "multiple findings: $FOUND_COUNT patterns emitted, exit reflects highest severity"
  else
    fail "multiple findings: expected >=3 patterns, got $FOUND_COUNT"
  fi
else
  fail "multiple findings: expected exit 1 (highest severity = high), got $EXIT"
fi

# --- 15. Line number reported correctly ---
content="line one is fine
line two also fine
key=sk-ant-api03-secretvaluethatislongenoughtomatch
line four is fine"
run_check "$content"
if echo "$OUT" | grep -q '"line": 3'; then
  pass "line number reported correctly (line 3)"
else
  fail "line number not reported correctly: $OUT"
fi

# --- 16. Output is valid JSONL ---
run_check "key=ghp_1234567890abcdefghijklmnopqrstuvwxyz12 and aws=AKIAIOSFODNN7EXAMPLE"
if [[ -n "$OUT" ]]; then
  while IFS= read -r line; do
    if ! echo "$line" | python3 -c "import json, sys; json.loads(sys.stdin.read())" 2>/dev/null; then
      fail "output line not valid JSON: $line"
      break
    fi
  done <<< "$OUT"
  pass "JSONL output: each line is valid JSON"
fi

# --- 17. Missing file → exit 2 ---
set +e
"$CHECK" /tmp/nonexistent-file-$$-$RANDOM 2>/dev/null
EX=$?
set -e
if [[ $EX -eq 2 ]]; then
  pass "missing file → exit 2 (usage error)"
else
  fail "missing file should exit 2, got $EX"
fi

# --- 18. No args → exit 2 ---
set +e
"$CHECK" 2>/dev/null
EX=$?
set -e
if [[ $EX -eq 2 ]]; then
  pass "no args → exit 2"
else
  fail "no args should exit 2, got $EX"
fi

echo
echo "check_pii_test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
