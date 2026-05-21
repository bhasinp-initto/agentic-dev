#!/usr/bin/env bash
# Tests for bin/enqueue-goal.sh.
#
# Deterministic; zero claude -p.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENQUEUE="$REPO_ROOT/agentic-dev/bin/enqueue-goal.sh"

TMP="$(mktemp -d -t agentic-enqueue-XXXXXX)"
trap '[ "${KEEP_TMP:-0}" = "1" ] && echo "Preserved: $TMP" || rm -rf "$TMP"' EXIT

cd "$TMP"
# Minimal project state
mkdir -p .claude/agentic/{intents,specs}
cat > .claude/agentic/queue.yaml <<'YAML'
schema_version: "0.2"
goals: []
YAML

# 1. Helper requires goal-id
if "$ENQUEUE" 2>/dev/null; then
  echo "FAIL: enqueue-goal.sh did not error on missing goal-id" >&2
  exit 1
fi
echo "PASS missing goal-id rejected"

# 2. Helper rejects bad goal-id format
if "$ENQUEUE" "not-a-valid-id" 2>/dev/null; then
  echo "FAIL: enqueue-goal.sh did not error on bad format" >&2
  exit 1
fi
echo "PASS bad-format goal-id rejected"

# 3. Helper rejects when spec missing
if "$ENQUEUE" "2026-05-21-no-such-spec" 2>/dev/null; then
  echo "FAIL: enqueue-goal.sh did not error on missing spec" >&2
  exit 1
fi
echo "PASS missing spec rejected"

# 4. Helper rejects spec with approved=false
GOAL_ID="2026-05-21-test-goal"
SPEC=".claude/agentic/specs/${GOAL_ID}.md"
cat > "$SPEC" <<EOF
---
id: $GOAL_ID
schema_version: "0.1"
intent_path: .claude/agentic/intents/${GOAL_ID}.md
approved: false
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test.
EOF

if "$ENQUEUE" "$GOAL_ID" 2>/dev/null; then
  echo "FAIL: enqueue-goal.sh did not error on approved=false spec" >&2
  exit 1
fi
echo "PASS approved=false spec rejected"

# 5. Happy path: approved spec enqueues
sed -i.bak 's/approved: false/approved: true/' "$SPEC"
rm -f "$SPEC.bak"

OUT=$("$ENQUEUE" "$GOAL_ID" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "FAIL: enqueue-goal.sh errored on happy path: $OUT" >&2
  exit 1
fi

# Verify queue.yaml has the goal
COUNT=$(python3 -c "import yaml; q=yaml.safe_load(open('.claude/agentic/queue.yaml')); print(len(q.get('goals', [])))")
if [[ "$COUNT" != "1" ]]; then
  echo "FAIL: queue.yaml should have 1 goal after enqueue, has $COUNT" >&2
  exit 1
fi
echo "PASS happy path appends goal to queue"

# Verify goal fields are correct
STATUS=$(python3 -c "import yaml; q=yaml.safe_load(open('.claude/agentic/queue.yaml')); print(q['goals'][0]['status'])")
if [[ "$STATUS" != "approved" ]]; then
  echo "FAIL: enqueued goal status should be 'approved', got '$STATUS'" >&2
  exit 1
fi
echo "PASS enqueued goal has status=approved"

ENQ_ID=$(python3 -c "import yaml; q=yaml.safe_load(open('.claude/agentic/queue.yaml')); print(q['goals'][0]['id'])")
if [[ "$ENQ_ID" != "$GOAL_ID" ]]; then
  echo "FAIL: enqueued goal id mismatch ($ENQ_ID vs $GOAL_ID)" >&2
  exit 1
fi
echo "PASS enqueued goal id matches"

# 6. Idempotency: re-running on already-approved goal is a no-op
OUT2=$("$ENQUEUE" "$GOAL_ID" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "FAIL: re-enqueue errored: $OUT2" >&2
  exit 1
fi
COUNT2=$(python3 -c "import yaml; q=yaml.safe_load(open('.claude/agentic/queue.yaml')); print(len(q.get('goals', [])))")
if [[ "$COUNT2" != "1" ]]; then
  echo "FAIL: re-enqueue created duplicate (count=$COUNT2)" >&2
  exit 1
fi
echo "PASS idempotent on already-approved"

# 7. Promotion: drafted goal gets promoted to approved
cat > .claude/agentic/queue.yaml <<'YAML'
schema_version: "0.2"
goals:
  - id: 2026-05-21-drafted-goal
    spec_path: .claude/agentic/specs/2026-05-21-drafted-goal.md
    intent_path: null
    status: drafted
    added_at: "2026-05-21T10:00:00Z"
YAML
GOAL2="2026-05-21-drafted-goal"
cat > ".claude/agentic/specs/${GOAL2}.md" <<EOF
---
id: $GOAL2
schema_version: "0.1"
intent_path: .claude/agentic/intents/${GOAL2}.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test.
EOF

OUT3=$("$ENQUEUE" "$GOAL2" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "FAIL: promotion errored: $OUT3" >&2
  exit 1
fi
PROMOTED_STATUS=$(python3 -c "import yaml; q=yaml.safe_load(open('.claude/agentic/queue.yaml')); print([g for g in q['goals'] if g['id']=='$GOAL2'][0]['status'])")
if [[ "$PROMOTED_STATUS" != "approved" ]]; then
  echo "FAIL: drafted goal should be promoted to approved, got $PROMOTED_STATUS" >&2
  exit 1
fi
echo "PASS drafted goal promoted to approved"

# 8. Refuses to clobber running/completed/halted goals
cat > .claude/agentic/queue.yaml <<'YAML'
schema_version: "0.2"
goals:
  - id: 2026-05-21-running-goal
    spec_path: .claude/agentic/specs/2026-05-21-running-goal.md
    intent_path: null
    status: running
    added_at: "2026-05-21T10:00:00Z"
YAML
GOAL3="2026-05-21-running-goal"
cat > ".claude/agentic/specs/${GOAL3}.md" <<EOF
---
id: $GOAL3
schema_version: "0.1"
intent_path: .claude/agentic/intents/${GOAL3}.md
approved: true
created_at: "2026-05-21T10:00:00Z"
---

# Intent
Test.
EOF

if "$ENQUEUE" "$GOAL3" 2>/dev/null; then
  echo "FAIL: enqueue-goal.sh wrongly clobbered running goal" >&2
  exit 1
fi
echo "PASS refuses to clobber running goal"

echo
echo "enqueue_goal_test: OK"
