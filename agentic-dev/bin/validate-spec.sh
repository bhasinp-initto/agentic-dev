#!/usr/bin/env bash
# Deterministic validator for .claude/agentic/specs/*.md files.
#
# Two invocation modes:
#  - Direct: `validate-spec.sh <spec-file>` — validates the given file.
#  - Hook: PostToolUse for Write|Edit. Hook input is JSON on stdin; the
#    script extracts tool_input.file_path. If the path doesn't match
#    .claude/agentic/specs/*.md, exits 0 silently.
#
# Exit codes:
#  0 — validation passed (or path doesn't match in hook mode)
#  1 — validation failed
#  2 — usage error
set -euo pipefail

# Determine spec file path
SPEC_FILE=""
if [[ $# -eq 1 ]]; then
  SPEC_FILE="$1"
elif [[ ! -t 0 ]]; then
  # Hook mode: read JSON from stdin, extract file_path
  # Uses [[ ! -t 0 ]] (stdin is not a terminal) to handle both anonymous
  # pipes and file-redirected stdin, as Claude Code may deliver hook JSON
  # via either mechanism.
  INPUT="$(cat)"
  SPEC_FILE="$(printf '%s' "$INPUT" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))')"
  if [[ -z "$SPEC_FILE" ]]; then
    exit 0
  fi
else
  echo "Usage: validate-spec.sh <spec-file>" >&2
  exit 2
fi

# Only validate spec files
if [[ ! "$SPEC_FILE" =~ \.claude/agentic/specs/.*\.md$ ]]; then
  exit 0
fi

if [[ ! -f "$SPEC_FILE" ]]; then
  # Edit may have been a delete; nothing to validate
  exit 0
fi

# Helpers
# Note: failure messages go to stdout so that Claude Code's PostToolUse hook
# mechanism feeds them back into the Claude transcript. The unit tests capture
# both stdout+stderr, so they are unaffected by this choice.
fail() {
  echo "agentic-dev: spec validation failed"
  echo "  file: $SPEC_FILE"
  echo "  ERROR: $*"
  exit 1
}

# Export SPEC_FILE so quoted Python heredocs can read it via os.environ
export SPEC_FILE

# Extract frontmatter (lines between first '---' and second '---')
# Uses unquoted heredoc only for the file-open line; rest is safe.
FRONTMATTER_CHECK="$(python3 - <<'PY'
import sys, os
spec_file = os.environ["SPEC_FILE"]
text = open(spec_file).read()
if not text.startswith("---"):
    print("__NO_FRONTMATTER__")
    sys.exit(0)
parts = text.split("---", 2)
if len(parts) < 3:
    print("__NO_FRONTMATTER__")
    sys.exit(0)
print("__HAS_FRONTMATTER__")
PY
)"

if [[ "$FRONTMATTER_CHECK" == "__NO_FRONTMATTER__" ]]; then
  fail "missing YAML frontmatter (must start with '---' and contain a closing '---')"
fi

# Parse frontmatter; validate required fields, types, formats
PARSE_OUTPUT="$(python3 - <<'PY'
import sys, yaml, re, os
from datetime import datetime

spec_file = os.environ["SPEC_FILE"]
text = open(spec_file).read()
parts = text.split("---", 2)
fm_text = parts[1].strip()

try:
    fm = yaml.safe_load(fm_text)
except yaml.YAMLError as e:
    print(f"PARSE_ERROR: {e}")
    sys.exit(0)

if not isinstance(fm, dict):
    print("PARSE_ERROR: frontmatter is not a YAML mapping")
    sys.exit(0)

required = ["id", "schema_version", "intent_path", "approved", "created_at"]
missing = [k for k in required if k not in fm]
if missing:
    print(f"PARSE_ERROR: missing required frontmatter field(s): {', '.join(missing)}")
    sys.exit(0)

if fm["schema_version"] != "0.1":
    print(f"PARSE_ERROR: schema_version must be '0.1', got {fm['schema_version']!r}")
    sys.exit(0)

if not isinstance(fm["approved"], bool):
    print(f"PARSE_ERROR: approved must be a boolean, got {type(fm['approved']).__name__}")
    sys.exit(0)

if not re.match(r"^\d{4}-\d{2}-\d{2}-[a-z0-9-]+$", str(fm["id"])):
    print(f"PARSE_ERROR: id must match YYYY-MM-DD-<slug>, got {fm['id']!r}")
    sys.exit(0)

try:
    dt = datetime.fromisoformat(str(fm["created_at"]).replace("Z", "+00:00"))
except ValueError:
    print(f"PARSE_ERROR: created_at not a valid date-time, got {fm['created_at']!r}")
    sys.exit(0)
if dt.tzinfo is None:
    print(f"PARSE_ERROR: created_at must include timezone offset (e.g., 'Z' or '+00:00'), got {fm['created_at']!r}")
    sys.exit(0)

# Resolve intent_path: try cwd-relative first, then project-root-relative.
# The spec file lives at <project-root>/.claude/agentic/specs/*.md, so the
# project root is spec_file/../../../.. (4 parents up).
# This handles hook mode where Claude Code may invoke the hook from a
# directory other than the project root.
intent_path = fm["intent_path"]
if not os.path.exists(intent_path):
    # Try resolving relative to the project root derived from the spec path
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(spec_file))))
    alt_path = os.path.join(project_root, intent_path)
    if os.path.exists(alt_path):
        intent_path = alt_path
    else:
        print(f"PARSE_ERROR: intent_path does not resolve to a file: {fm['intent_path']}")
        sys.exit(0)

print(f"OK approved={fm['approved']}")
PY
)"

if [[ "$PARSE_OUTPUT" == PARSE_ERROR* ]]; then
  fail "${PARSE_OUTPUT#PARSE_ERROR: }"
fi

APPROVED="$(printf '%s' "$PARSE_OUTPUT" | sed -n 's/^OK approved=//p')"

# Check Diff budget section parses
BUDGET_OUTPUT="$(python3 - <<'PY'
import re, os
spec_file = os.environ["SPEC_FILE"]
text = open(spec_file).read()
m = re.search(r"^# Diff budget\s*$(.+?)(?=^# |\Z)", text, re.MULTILINE | re.DOTALL)
if not m:
    print("BUDGET_ERROR: missing '# Diff budget' section")
    raise SystemExit
section = m.group(1)
def grab(label):
    mm = re.search(rf"- {label}:\s*(\S+)", section)
    return mm.group(1) if mm else None
wc = grab("Wall clock")
dl = grab("Diff lines")
ft = grab("Files touched")
if not wc or not dl or not ft:
    print("BUDGET_ERROR: budget section must have 'Wall clock', 'Diff lines', and 'Files touched' lines")
    raise SystemExit
try:
    wc_int = int(re.match(r"(\d+)", wc).group(1))
    dl_int = int(dl)
    ft_int = int(ft)
except (AttributeError, ValueError, TypeError):
    print("BUDGET_ERROR: budget values must be positive integers")
    raise SystemExit
if wc_int < 1 or dl_int < 1 or ft_int < 1:
    print("BUDGET_ERROR: budget values must be >= 1")
    raise SystemExit
print("BUDGET_OK")
PY
)"

if [[ "$BUDGET_OUTPUT" == BUDGET_ERROR* ]]; then
  fail "${BUDGET_OUTPUT#BUDGET_ERROR: }"
fi

# Check for unresolved QUESTION-N blocks if approved=true
if [[ "$APPROVED" == "True" ]]; then
  if grep -qE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE"; then
    QUESTIONS="$(grep -nE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" | sed -E 's/^([0-9]+):.*<!-- (QUESTION-[0-9]+) \(([^)]+)\).*/  - \2 (\3) at line \1/')"
    echo "agentic-dev: spec validation failed"
    echo "  file: $SPEC_FILE"
    echo "  ERROR: approved=true but unresolved QUESTION blocks remain:"
    echo "$QUESTIONS"
    echo "  Either answer those questions or set approved=false."
    exit 1
  fi
  if grep -qF "[REPLACE THIS LINE" "$SPEC_FILE"; then
    fail "approved=true but '[REPLACE THIS LINE' placeholder(s) still present in the spec body"
  fi
  echo "agentic-dev: spec validation passed"
  echo "  file: $SPEC_FILE"
  echo "  state: approved"
  echo "  Next: run /agentic-dev:_check-approval $SPEC_FILE to dispatch the AI validator."
else
  REMAINING="$(grep -cE '<!-- QUESTION-[0-9]+ ' "$SPEC_FILE" || true)"
  echo "agentic-dev: spec validation passed"
  echo "  file: $SPEC_FILE"
  echo "  state: draft ($REMAINING questions remaining)"
fi
