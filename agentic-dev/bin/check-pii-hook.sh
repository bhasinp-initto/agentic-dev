#!/usr/bin/env bash
# check-pii-hook.sh — PostToolUse hook wrapper around check-pii.sh.
#
# Reads Claude Code hook JSON from stdin, extracts tool_input.file_path,
# filters to only sensitive agentic-dev output files (escalations,
# memory.yaml, checklist.yaml, decisions.log, notifications-log.txt),
# and invokes check-pii.sh if the path matches.
#
# Output is ADVISORY — always exits 0. Hooks should not block the
# pipeline on side-channel concerns (test-cost-policy, P7-L4).
#
# Findings (if any) go to stdout so Claude Code surfaces them in the
# operator transcript.
set -euo pipefail

# Read hook JSON from stdin if not a terminal (hook mode); else exit 0 silently.
if [[ -t 0 ]]; then
  # Direct invocation, no stdin — nothing to do.
  exit 0
fi

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))')"

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Filter: only act on sensitive agentic-dev output files
case "$FILE_PATH" in
  *.claude/agentic/escalations/*.md) ;;
  *.claude/agentic/memory.yaml) ;;
  *.claude/agentic/checklist.yaml) ;;
  *.claude/agentic/decisions.log) ;;
  *.claude/agentic/notifications-log.txt) ;;
  *)
    # Not a sensitive file — silently skip
    exit 0
    ;;
esac

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Invoke the scanner
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/check-pii.sh"

set +e
FINDINGS="$("$SCANNER" "$FILE_PATH" 2>/dev/null)"
EXIT=$?
set -e

if [[ -n "$FINDINGS" ]]; then
  COUNT=$(echo "$FINDINGS" | grep -c '"pattern"' || echo 0)
  echo "agentic-dev: PII scan flagged $COUNT finding(s) in $FILE_PATH"
  echo "  (advisory — pipeline continues; review and redact if these are real secrets)"
  echo "$FINDINGS" | while IFS= read -r line; do
    PATTERN=$(echo "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("pattern",""))')
    SEVERITY=$(echo "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("severity",""))')
    LINENO=$(echo "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("line",""))')
    REDACTED=$(echo "$line" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("redacted_match",""))')
    echo "  - [$SEVERITY] $PATTERN at line $LINENO: $REDACTED"
  done
fi

exit 0
