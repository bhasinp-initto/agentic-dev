#!/usr/bin/env bash
# telegram-notify.sh <severity> <message> [packet-path]
#
# Sends a Telegram notification for a given severity level. If Telegram is
# not configured in .claude/agentic/config.yaml, logs to
# .claude/agentic/notifications-log.txt and exits 0.
#
# Severities: blocking | digest | warning | info
#
# Exit codes:
#   0 — notification sent, logged, or gracefully skipped (notifications are advisory)
#   1 — invalid usage (missing or invalid severity)
#
# Notifications NEVER fail the pipeline. Any Telegram API error → log + exit 0.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

SEVERITY="${1:-}"
MESSAGE="${2:-}"
PACKET_PATH="${3:-}"

VALID_SEVERITIES="blocking digest warning info"

usage() {
  echo "Usage: telegram-notify.sh <severity> <message> [packet-path]" >&2
  echo "Severities: blocking | digest | warning | info" >&2
}

# Validate severity present
if [[ -z "$SEVERITY" ]]; then
  usage
  exit 1
fi

# Validate message present
if [[ -z "$MESSAGE" ]]; then
  usage
  exit 1
fi

# Validate severity is one of the valid values
SEVERITY_VALID=false
for s in $VALID_SEVERITIES; do
  if [[ "$SEVERITY" == "$s" ]]; then
    SEVERITY_VALID=true
    break
  fi
done

if [[ "$SEVERITY_VALID" != "true" ]]; then
  echo "telegram-notify: invalid severity '$SEVERITY'" >&2
  usage
  exit 1
fi

# ── Locate config.yaml ────────────────────────────────────────────────────────

PROJECT_ROOT="$(pwd)"
CONFIG_PATH="$PROJECT_ROOT/.claude/agentic/config.yaml"

LOG_DIR="$PROJECT_ROOT/.claude/agentic"
LOG_FILE="$LOG_DIR/notifications-log.txt"

# ── Logging helper ────────────────────────────────────────────────────────────

log_notification() {
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mkdir -p "$LOG_DIR"
  echo "${ts} | ${SEVERITY} | ${MESSAGE}" >> "$LOG_FILE"
}

# ── Config not found → log and exit 0 ────────────────────────────────────────

if [[ ! -f "$CONFIG_PATH" ]]; then
  log_notification
  echo "no config; logged"
  exit 0
fi

# ── Read telegram config via Python + yaml ────────────────────────────────────

read_telegram_config() {
  python3 - "$CONFIG_PATH" <<'PY'
import sys, json

config_path = sys.argv[1]

# Try PyYAML first; fall back to simple regex for basic YAML
try:
    import yaml
    with open(config_path) as f:
        config = yaml.safe_load(f)
except ImportError:
    # Manual parse: look for "telegram:" block
    import re
    text = open(config_path).read()
    m = re.search(r'^telegram\s*:\s*null', text, re.MULTILINE)
    if m:
        print(json.dumps({"configured": False}))
        sys.exit(0)
    bot_m = re.search(r'^\s+bot_token\s*:\s*["\']?([^\s"\'#]+)["\']?', text, re.MULTILINE)
    chat_m = re.search(r'^\s+chat_id\s*:\s*["\']?([^\s"\'#]+)["\']?', text, re.MULTILINE)
    if bot_m and chat_m:
        print(json.dumps({
            "configured": True,
            "bot_token": bot_m.group(1),
            "chat_id": chat_m.group(1)
        }))
    else:
        print(json.dumps({"configured": False}))
    sys.exit(0)

telegram = config.get("telegram")
if not telegram:
    print(json.dumps({"configured": False}))
    sys.exit(0)

bot_token = telegram.get("bot_token") if isinstance(telegram, dict) else None
chat_id = telegram.get("chat_id") if isinstance(telegram, dict) else None

if not bot_token or not chat_id:
    print(json.dumps({"configured": False}))
    sys.exit(0)

print(json.dumps({
    "configured": True,
    "bot_token": str(bot_token),
    "chat_id": str(chat_id)
}))
PY
}

TELEGRAM_JSON=""
if ! TELEGRAM_JSON="$(read_telegram_config 2>/dev/null)"; then
  log_notification
  echo "telegram not configured; logged to notifications-log.txt"
  exit 0
fi

CONFIGURED="$(echo "$TELEGRAM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['configured'])")"

if [[ "$CONFIGURED" != "True" ]]; then
  log_notification
  echo "telegram not configured; logged to notifications-log.txt"
  exit 0
fi

BOT_TOKEN="$(echo "$TELEGRAM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['bot_token'])")"
CHAT_ID="$(echo "$TELEGRAM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['chat_id'])")"

# ── Severity emoji/label mapping ──────────────────────────────────────────────

case "$SEVERITY" in
  blocking) LABEL="🚨 BLOCKING" ;;
  warning)  LABEL="⚠️ WARNING" ;;
  digest)   LABEL="📋 DIGEST" ;;
  info)     LABEL="ℹ️ INFO" ;;
  *)        LABEL="$SEVERITY" ;;
esac

# ── Build message text ────────────────────────────────────────────────────────

MSG_TEXT="${LABEL}: ${MESSAGE}"
if [[ -n "$PACKET_PATH" ]]; then
  MSG_TEXT="${MSG_TEXT}

Packet: \`${PACKET_PATH}\`"
fi

# ── POST to Telegram Bot API ──────────────────────────────────────────────────

API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

PAYLOAD="$(python3 -c "
import json, sys
payload = {
    'chat_id': '$CHAT_ID',
    'text': $(python3 -c "import json; print(json.dumps('$MSG_TEXT'))"),
    'parse_mode': 'Markdown'
}
print(json.dumps(payload))
")"

CURL_EXIT=0
CURL_OUT=""
CURL_OUT="$(curl --silent --show-error --fail --max-time 10 \
  -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>&1)" || CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  # HTTP failure — log and exit 0 (notifications are advisory)
  log_notification
  echo "telegram-notify: WARNING: Telegram API call failed (curl exit $CURL_EXIT); logged to notifications-log.txt" >&2
  exit 0
fi

echo "notified via Telegram"
exit 0
