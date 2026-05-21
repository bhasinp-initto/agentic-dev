#!/usr/bin/env bash
# generate-escalation.sh <goal-id> <trigger> [extra-summary]
#
# Generates a structured escalation packet for a goal that has been halted.
# Writes to .claude/agentic/escalations/<ISO-timestamp>-<goal-id>.md as
# Markdown with YAML frontmatter.
#
# Triggers: reviewer_blocking | judgment_concerns | gate_failure |
#           auto_fix_exhausted | budget_hard_halt | spec_drift
#
# Exit codes:
#   0 — escalation packet written; path printed to stdout
#   1 — invalid args, missing manifest, or schema validation failure

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

GOAL_ID="${1:-}"
TRIGGER="${2:-}"
EXTRA_SUMMARY="${3:-}"

VALID_TRIGGERS="reviewer_blocking judgment_concerns gate_failure auto_fix_exhausted budget_hard_halt spec_drift"
GOAL_ID_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$'

usage() {
  echo "Usage: generate-escalation.sh <goal-id> <trigger> [extra-summary]" >&2
  echo "Triggers: reviewer_blocking | judgment_concerns | gate_failure | auto_fix_exhausted | budget_hard_halt | spec_drift" >&2
}

# Validate goal-id
if [[ -z "$GOAL_ID" ]]; then
  echo "generate-escalation: missing goal-id" >&2
  usage
  exit 1
fi

if ! echo "$GOAL_ID" | grep -Eq "$GOAL_ID_PATTERN"; then
  echo "generate-escalation: invalid goal-id format '$GOAL_ID' (expected YYYY-MM-DD-<slug>)" >&2
  usage
  exit 1
fi

# Validate trigger
if [[ -z "$TRIGGER" ]]; then
  echo "generate-escalation: missing trigger" >&2
  usage
  exit 1
fi

TRIGGER_VALID=false
for t in $VALID_TRIGGERS; do
  if [[ "$TRIGGER" == "$t" ]]; then
    TRIGGER_VALID=true
    break
  fi
done

if [[ "$TRIGGER_VALID" != "true" ]]; then
  echo "generate-escalation: invalid trigger '$TRIGGER'" >&2
  usage
  exit 1
fi

# ── Path resolution ───────────────────────────────────────────────────────────

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="$SCRIPT_DIR/../schemas/escalation-packet.schema.json"

MANIFEST_PATH="$PROJECT_ROOT/.claude/agentic/manifests/${GOAL_ID}.json"
REVIEWER_VERDICT_PATH="$PROJECT_ROOT/.claude/agentic/reviewer-verdicts/${GOAL_ID}.json"
GATE_VERDICT_PATH="$PROJECT_ROOT/.claude/agentic/verdicts/${GOAL_ID}.json"
DIFF_ENVELOPE_PATH="$PROJECT_ROOT/.claude/agentic/diffs/${GOAL_ID}.json"
ESCALATION_DIR="$PROJECT_ROOT/.claude/agentic/escalations"

# ── Pre-checks ────────────────────────────────────────────────────────────────

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "generate-escalation: manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

# ── Build escalation packet via Python ───────────────────────────────────────

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
FILE_TIMESTAMP="$(date -u +"%Y-%m-%dT%H-%M-%SZ" 2>/dev/null || python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H-%M-%SZ'))")"

mkdir -p "$ESCALATION_DIR"

ESCALATION_FILE="$ESCALATION_DIR/${FILE_TIMESTAMP}-${GOAL_ID}.md"

python3 - \
  "$GOAL_ID" \
  "$TRIGGER" \
  "$TIMESTAMP" \
  "$MANIFEST_PATH" \
  "${REVIEWER_VERDICT_PATH}" \
  "${GATE_VERDICT_PATH}" \
  "${DIFF_ENVELOPE_PATH}" \
  "$ESCALATION_FILE" \
  "$EXTRA_SUMMARY" \
  "$SCHEMA_PATH" \
  "$PROJECT_ROOT" \
  <<'PY'
import sys, json, os
from datetime import datetime, timezone

(goal_id, trigger, generated_at, manifest_path, reviewer_verdict_path,
 gate_verdict_path, diff_envelope_path, escalation_file,
 extra_summary, schema_path, project_root) = sys.argv[1:12]

# ── Load manifest ──────────────────────────────────────────────────────────────
try:
    manifest = json.loads(open(manifest_path).read())
except Exception as e:
    print(f"generate-escalation: ERROR reading manifest: {e}", file=sys.stderr)
    sys.exit(1)

spec_path = manifest.get("spec_path", "")
worktree_path = manifest.get("worktree_path", "")

# ── Load optional files ────────────────────────────────────────────────────────
reviewer_verdict = None
if os.path.isfile(reviewer_verdict_path):
    try:
        reviewer_verdict = json.loads(open(reviewer_verdict_path).read())
    except Exception:
        pass

gate_verdict = None
if os.path.isfile(gate_verdict_path):
    try:
        gate_verdict = json.loads(open(gate_verdict_path).read())
    except Exception:
        pass

diff_envelope_exists = os.path.isfile(diff_envelope_path)

# ── Build concerns ─────────────────────────────────────────────────────────────
concerns = []

if reviewer_verdict and reviewer_verdict.get("concerns"):
    concerns = reviewer_verdict["concerns"]
elif gate_verdict and gate_verdict.get("blocking_failures"):
    # Repackage gate blocking_failures as concerns
    for bf in gate_verdict["blocking_failures"]:
        concerns.append({
            "file": "",
            "line": 0,
            "severity": "blocking",
            "category": "judgment",
            "description": f"Gate '{bf}' failed: blocking gate failure"
        })

# ── Build summary ──────────────────────────────────────────────────────────────
concern_count = len(concerns)
judgment_count = sum(1 for c in concerns if c.get("category") in ("judgment", "uncategorized"))
mechanical_count = sum(1 for c in concerns if c.get("category") == "mechanical")

trigger_labels = {
    "reviewer_blocking": "reviewer issued a blocking verdict",
    "judgment_concerns": f"{judgment_count} judgment-category concern(s) from reviewer",
    "gate_failure": "deterministic gate(s) failed",
    "auto_fix_exhausted": "auto-fix loop cap reached without convergence",
    "budget_hard_halt": "hard budget limit reached",
    "spec_drift": "implementation drift detected from spec",
}
trigger_desc = trigger_labels.get(trigger, trigger)

if extra_summary:
    summary = extra_summary
else:
    summary = (
        f"Goal {goal_id} halted: {trigger_desc}. "
        f"{concern_count} concern(s) require human review before proceeding."
    )

suggested_next_actions = ["resume", "skip", "address", "replan", "abort"]

# ── Build packet dict ──────────────────────────────────────────────────────────
packet = {
    "schema_version": "0.1",
    "goal_id": goal_id,
    "generated_at": generated_at,
    "trigger": trigger,
    "concerns": concerns,
    "manifest_path": os.path.relpath(manifest_path, project_root),
    "summary": summary,
    "suggested_next_actions": suggested_next_actions,
}

# Optional fields (set if found)
if reviewer_verdict:
    packet["verdict_path"] = os.path.relpath(reviewer_verdict_path, project_root)
else:
    packet["verdict_path"] = None

if diff_envelope_exists:
    packet["diff_envelope_path"] = os.path.relpath(diff_envelope_path, project_root)
else:
    packet["diff_envelope_path"] = None

if spec_path:
    # Resolve spec_path (may be relative to project root)
    if os.path.isabs(spec_path):
        packet["spec_path"] = spec_path
    else:
        packet["spec_path"] = spec_path
else:
    packet["spec_path"] = None

if worktree_path:
    packet["worktree_path"] = worktree_path
else:
    packet["worktree_path"] = None

# ── Validate against schema (optional — warn only) ────────────────────────────
try:
    import jsonschema
    schema = json.loads(open(schema_path).read())
    jsonschema.validate(packet, schema, format_checker=jsonschema.FormatChecker())
except ImportError:
    pass  # jsonschema not installed; skip validation
except jsonschema.ValidationError as e:
    print(f"generate-escalation: WARNING: packet failed schema validation: {e.message}", file=sys.stderr)
except Exception:
    pass

# ── Build YAML frontmatter ─────────────────────────────────────────────────────
def yaml_str(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    # Escape for YAML single-quoted string
    s = str(v)
    if any(c in s for c in [':', '#', '[', ']', '{', '}', '\n', "'", '"']):
        return json.dumps(s)  # fall back to JSON double-quote style
    return f'"{s}"'

# Build concerns YAML list
def concern_to_yaml(c, indent="  "):
    lines = [f"  - file: {yaml_str(c.get('file', ''))}"]
    lines.append(f"    line: {c.get('line', 0)}")
    lines.append(f"    severity: {yaml_str(c.get('severity', 'concern'))}")
    lines.append(f"    category: {yaml_str(c.get('category', 'uncategorized'))}")
    lines.append(f"    description: {yaml_str(c.get('description', ''))}")
    return "\n".join(lines)

concerns_yaml = ""
if concerns:
    concerns_yaml = "\n" + "\n".join(concern_to_yaml(c) for c in concerns)
else:
    concerns_yaml = " []"

actions_yaml = "\n" + "\n".join(f"  - {yaml_str(a)}" for a in suggested_next_actions)

frontmatter_lines = [
    "---",
    f"schema_version: {yaml_str(packet['schema_version'])}",
    f"goal_id: {yaml_str(packet['goal_id'])}",
    f"generated_at: {yaml_str(packet['generated_at'])}",
    f"trigger: {yaml_str(packet['trigger'])}",
    f"manifest_path: {yaml_str(packet['manifest_path'])}",
    f"summary: {yaml_str(packet['summary'])}",
    f"concerns:{concerns_yaml}",
    f"suggested_next_actions:{actions_yaml}",
    f"verdict_path: {yaml_str(packet.get('verdict_path'))}",
    f"diff_envelope_path: {yaml_str(packet.get('diff_envelope_path'))}",
    f"spec_path: {yaml_str(packet.get('spec_path'))}",
    f"worktree_path: {yaml_str(packet.get('worktree_path'))}",
    "---",
]
frontmatter = "\n".join(frontmatter_lines)

# ── Build markdown body ────────────────────────────────────────────────────────
trigger_label = trigger.replace("_", " ").title()
goal_section = f"**Goal ID:** `{goal_id}`"
if spec_path:
    goal_section += f"\n**Spec:** `{spec_path}`"
if worktree_path:
    goal_section += f"\n**Worktree:** `{worktree_path}`"

concerns_md = ""
if concerns:
    bullets = []
    for c in concerns:
        loc = f"`{c.get('file', '')}:{c.get('line', 0)}`" if c.get("file") else ""
        sev = c.get("severity", "concern")
        cat = c.get("category", "uncategorized")
        desc = c.get("description", "")
        bullets.append(f"- [{sev.upper()} / {cat}] {loc} {desc}".strip())
    concerns_md = "\n".join(bullets)
else:
    concerns_md = "_No specific concerns recorded._"

files_md_parts = []
files_md_parts.append(f"- **Manifest:** `{packet['manifest_path']}`")
if packet.get("verdict_path"):
    files_md_parts.append(f"- **Reviewer Verdict:** `{packet['verdict_path']}`")
if packet.get("diff_envelope_path"):
    files_md_parts.append(f"- **Diff Envelope:** `{packet['diff_envelope_path']}`")
if packet.get("spec_path"):
    files_md_parts.append(f"- **Spec:** `{packet['spec_path']}`")
files_md = "\n".join(files_md_parts)

actions_md = "\n".join(f"- `{a}`" for a in suggested_next_actions)

body = f"""# Escalation Packet: {goal_id}

## Summary

{summary}

## Trigger

**{trigger_label}** (`{trigger}`)

## Goal

{goal_section}

## Concerns

{concerns_md}

## Files

{files_md}

## Suggested Next Actions

{actions_md}
"""

# ── Write to disk ─────────────────────────────────────────────────────────────
content = frontmatter + "\n\n" + body
with open(escalation_file, "w") as f:
    f.write(content)

# Print relative path from project root
rel_path = os.path.relpath(escalation_file, project_root)
print(f".claude/agentic/escalations/{os.path.basename(escalation_file)}")
PY

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "generate-escalation: ERROR: failed to generate escalation packet" >&2
  exit 1
fi

exit 0
