#!/usr/bin/env bash
# check-pii.sh — deterministic scan for secrets and PII in a file.
#
# Exit codes:
#   0 — clean (no findings) OR informational findings only
#   1 — high-severity findings (API keys, private keys, DB creds)
#   2 — usage error
#
# Output: JSON to stdout describing each finding (one JSON object per line —
# JSONL — so callers can iterate easily). Stderr is reserved for usage errors.
#
# Patterns borrowed in spirit from ruflo-aidefence (MIT-licensed,
# https://github.com/ruvnet/claude-flow). We do not depend on ruflo's
# runtime; the regex set is reimplemented here under our own license.
#
# Findings are categorized by severity:
#   high     — confirmed secret pattern; pipeline must surface to operator
#   medium   — credential-like pattern that could be a secret
#   info     — low-confidence; flagged for human review only (email/phone etc.)
#
# This script is invoked by:
#   1. PostToolUse hook on Write|Edit for files in .claude/agentic/{escalations,
#      memory.yaml, checklist.yaml, decisions.log, notifications-log.txt}.
#      Per cost policy, hook output is non-blocking (advisory).
#   2. /agentic-dev:_check-approval as a pre-check on the spec before invoking
#      the AI validator. Findings refuse approval until cleaned.
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  echo "Usage: check-pii.sh <file>" >&2
  exit 2
fi
if [[ ! -f "$FILE" ]]; then
  echo "Usage: check-pii.sh <file> — file not found: $FILE" >&2
  exit 2
fi

export FILE
python3 - <<'PY'
import os, re, json, sys

path = os.environ["FILE"]
try:
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
except Exception as e:
    sys.stderr.write(f"check-pii: failed to read {path}: {e}\n")
    sys.exit(2)

# ── Pattern set ──────────────────────────────────────────────────────────────
# Each pattern is a tuple: (name, severity, regex, description)
# regex is matched with re.MULTILINE; findings include the matched span.

PATTERNS = [
    # Cloud provider keys
    ("aws-access-key-id",       "high",
     r"\bAKIA[0-9A-Z]{16}\b",
     "AWS Access Key ID"),
    ("gcp-service-account",     "high",
     r'"type":\s*"service_account"',
     "GCP service account JSON marker"),
    # AI API keys
    ("anthropic-api-key",       "high",
     r"\bsk-ant-api[0-9]{2}-[A-Za-z0-9_\-]{20,}\b",
     "Anthropic API key"),
    ("openai-api-key",          "high",
     r"\bsk-(?:proj-)?[A-Za-z0-9_\-]{20,}\b",
     "OpenAI API key (or similar sk- prefix)"),
    # Version control + chat
    ("github-pat",              "high",
     r"\bgh[oprsu]_[A-Za-z0-9]{36,}\b",
     "GitHub personal access token"),
    ("slack-token",             "high",
     r"\bxox[abprs]-[A-Za-z0-9\-]{10,}\b",
     "Slack token"),
    # Payments
    ("stripe-secret",           "high",
     r"\bsk_(?:test|live)_[A-Za-z0-9]{20,}\b",
     "Stripe secret key"),
    # JWTs
    ("jwt-token",               "medium",
     r"\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b",
     "JWT (could be sensitive depending on claims)"),
    # Database connection strings with credentials embedded
    ("db-conn-string-with-creds", "high",
     r"\b(?:mongodb|postgres(?:ql)?|mysql|redis)(?:\+srv)?://[^:\s]+:[^@\s]+@[^\s]+",
     "Database connection string containing credentials"),
    # Private keys
    ("private-key-pem",         "high",
     r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED |PGP )?PRIVATE KEY-----",
     "Private key (PEM/PGP/OpenSSH)"),
    # Generic API key assignment in code. Allow optional closing quote on the
    # key name (matches both `api_key=...` and `"api_key": ...`).
    ("inline-api-key-assignment", "medium",
     r"(?i)(?:api[_-]?key|secret|token|password|passwd)[\"\']?\s*[:=]\s*[\"\'](?!\$|\<|\{|\[)[^\"\'\n]{12,}[\"\']",
     "Inline assignment of api_key / secret / token / password to a quoted string"),
    # Telegram bot token format (since we have config.yaml field for it)
    ("telegram-bot-token",      "high",
     r"\b[0-9]{8,10}:[A-Za-z0-9_\-]{30,}\b",
     "Telegram bot token format"),
    # Twilio
    ("twilio-account-sid",      "medium",
     r"\bAC[a-f0-9]{32}\b",
     "Twilio Account SID"),
    # Generic high-entropy hex strings (40+ chars). Lower confidence — git SHAs
    # are 40 hex, but stand-alone 64+ hex strings are often hashes/keys.
    # We restrict to >=48 to reduce git-SHA false-positives.
    ("high-entropy-hex",        "info",
     r"\b[a-fA-F0-9]{48,}\b",
     "High-entropy hex string (could be a hash or a secret)"),
]

findings = []
for name, severity, regex, desc in PATTERNS:
    for m in re.finditer(regex, text, re.MULTILINE):
        line_num = text[:m.start()].count("\n") + 1
        # Snippet: the matched span, but clip to 80 chars and redact the
        # middle to avoid printing the full secret in audit logs.
        full = m.group(0)
        if len(full) <= 16:
            redacted = full
        else:
            redacted = full[:6] + "…" + full[-4:]
        findings.append({
            "pattern": name,
            "severity": severity,
            "description": desc,
            "line": line_num,
            "redacted_match": redacted,
        })

# False-positive trim: if a finding's line is inside a fenced code block in
# our own source (e.g., this script's own pattern examples), still report.
# We keep the rule simple — the operator decides.

# Emit JSONL, one finding per line
for f in findings:
    print(json.dumps(f))

# Aggregate severity for exit code
severities = {f["severity"] for f in findings}
if "high" in severities:
    sys.exit(1)
# medium and info exit 0 (advisory only)
sys.exit(0)
PY
