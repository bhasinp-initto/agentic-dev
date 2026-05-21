---
description: Internal skill triggered after deterministic validation passes on an approved spec. Dispatches the spec-validator-ai subagent. On concerns, writes new QUESTION-N blocks back into the spec and reverts approved to false. v0.2 requires the user to invoke this explicitly after deterministic validation passes; future versions may auto-fire from the hook.
---

# /agentic-dev:_check-approval

You are the orchestrator for the AI half of the spec validator. You are invoked explicitly after the deterministic validator reports `state: approved`.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the path to the spec file to validate. If empty, print:
```
agentic-dev: /agentic-dev:_check-approval requires a spec file path. Example: /agentic-dev:_check-approval .claude/agentic/specs/2026-05-20-x.md
```
and exit.

## Pre-checks

1. **File existence**: Verify the spec file exists using the Read tool. If it does not exist, print `agentic-dev: spec file not found: <path>` and exit.

1b. **Path pattern**: Verify that the spec file path (resolved to its canonical form) matches the pattern `.claude/agentic/specs/*.md`. Both relative and absolute paths are accepted, but the path must end with that pattern. If the path does not match, print `agentic-dev: _check-approval target must be a spec file under .claude/agentic/specs/` and exit. This guards against the skill being invoked on arbitrary markdown files.

2. **Approved flag**: Check that the frontmatter contains `approved: true`. If `approved: false`, print `agentic-dev: spec is not approved (approved: false); nothing to validate` and exit.

3. **No QUESTION blocks**: Confirm there are no `<!-- QUESTION-` markers. If any exist, print `agentic-dev: spec has unresolved QUESTION blocks; resolve them before running _check-approval` and exit.

Do NOT run the deterministic validator script. The hook already ran it when the file was saved; running it again is redundant and requires locating the plugin directory.

## Dispatch the AI validator

Read the full contents of the spec file. Then use the Agent tool (subagent_type: spec-validator-ai) with this exact prompt (substitute real values for `<path>` and the spec body):

```
Validate the following spec for measurability of completion criteria and scope coherence. Your ENTIRE response must be ONLY the JSON object. Start with { and end with }. No preamble. No code fences. No explanation.

spec_path: <path>

spec_body:
<full file contents verbatim>
```

## Parse the verdict

After the Agent tool returns, parse the JSON verdict by piping the subagent's response to python3 via stdin. Use the Bash tool with:

```bash
printf '%s' "<the subagent response>" | python3 -c "
import json, sys
try:
    obj = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f'PARSE_ERROR: {e}')
    sys.exit(1)
print(f'verdict={obj.get(\"verdict\")}')
print(f'concerns_count={len(obj.get(\"concerns\", []))}')
for c in obj.get('concerns', []):
    print('concern_category=' + c['category'])
    print('concern_section=' + c['section'])
    print('concern_idx=' + str(c.get('criterion_index', 'null')))
    print('concern_explanation=' + c['explanation'])
    print('concern_question=' + c['suggested_question'].replace('\n', '\\\\n'))
"
```

If python3 prints `PARSE_ERROR:`, treat the response as malformed:
1. Print: `agentic-dev: AI validator returned malformed output; logging to .claude/agentic/validation-log.txt`
2. Use the Bash tool: `echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | MALFORMED | ..." >> .claude/agentic/validation-log.txt`
3. Leave `approved: true` unchanged. Exit.

The stdin-piped approach avoids quoting hazards: the subagent's response can contain any characters including apostrophes, double-quotes, and triple-quotes without breaking the shell command.

## On verdict: clean

Print:
```
agentic-dev: AI validator verdict: clean
  spec: <path>
  status: approved (no concerns)
```

Use the Bash tool to append to `.claude/agentic/validation-log.txt`:
```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <spec-id> | clean" >> .claude/agentic/validation-log.txt
```

**Then enqueue the goal so /agentic-dev:start can run it.** Use the Bash tool to call `enqueue-goal.sh`:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/enqueue-goal.sh <spec-id>
```

The helper validates that the spec is still `approved: true`, finds or appends the matching goal entry in `.claude/agentic/queue.yaml` with `status: approved`, schema-validates, and writes atomically. If the goal is already enqueued at status=approved, the helper is a no-op (idempotent). Print the helper's stdout so the user sees the queue state change. If the helper exits non-zero, surface the error but do NOT revert the AI-validator clean verdict — enqueue is bookkeeping, not validation.

Do NOT modify the spec file. Do not edit anything except the queue (via enqueue-goal.sh) and the validation log.

## On verdict: concerns

Process ALL concerns and insert new QUESTION blocks into the spec file, THEN revert approved.

**Step-by-step for each concern:**

1. Scan the current spec file for `<!-- QUESTION-` markers (use Grep or Read). Find the highest N. If none, highest = 0.

2. For each concern in order, compute N = highest_so_far + 1. Increment highest_so_far for each concern.

3. Build the full QUESTION block text. The `suggested_question` field from the JSON starts with `(<category>)\n**Q:**...`. Prepend the `<!-- QUESTION-N` marker:
   ```
   <!-- QUESTION-<N> (<category>) -->
   **Q:** ...rest of suggested_question...
   ```
   Note: the `suggested_question` value starts with `(<category>)\n` — use that category in the marker. So if `suggested_question` starts with `(completion-criterion)\n**Q:** What latency...` then the marker is `<!-- QUESTION-<N> (completion-criterion) -->`.

4. For the FIRST concern only, also prepend this one-time comment:
   ```
   <!-- spec-validator-ai found new ambiguities; resolve before re-approval -->
   ```

5. **Section-heading matching**: Match the section heading literally. The spec body has headings like `# Completion criteria`, `# Scope — In` (note the em-dash U+2014), `# Scope — Out (deferrals)`. The validator's `section` field contains the heading text WITHOUT the `#` prefix. To find the section:

   a. Build the target by prefixing `# ` to `concern.section` (e.g., `# Completion criteria`).
   b. Search the spec body for an exact line match (case-sensitive, em-dash characters preserved).
   c. If the section is found: insert the new QUESTION-N block immediately below the last existing content in that section, before the next `# ` heading or end-of-file.
   d. **If the section is NOT found** (e.g., the validator named a section that doesn't exist, or em-dash characters don't match): insert the QUESTION block at the END of the spec body and append a one-line warning to `.claude/agentic/validation-log.txt`: `<timestamp> | <spec-id> | warning | section "<concern.section>" not found, inserted at EOF`. Do NOT fail — the QUESTION still surfaces to the user, just at a less ideal location.

**The order of edits matters — follow this sequence:**

6. **FIRST: Revert approved.** Use the Edit tool to change `approved: true` to `approved: false` in the frontmatter. After this Edit, the PostToolUse hook sees `approved: false` with no new QUESTION blocks, emitting "state: draft, N questions remaining" — no spurious error. Reverting `approved` first prevents the hook from seeing an intermediate state with `approved: true` + unresolved QUESTION blocks (which would emit a spurious "validation failed" message in the operator's transcript). With `approved: false` first, every subsequent Edit sees a clean draft state and the hook validates cleanly.

7. **SECOND: Insert QUESTION blocks.** For each concern in order, use the Edit tool to insert the new QUESTION block at the appropriate section (per step 5 above). After each Edit, the hook sees `approved: false` with new QUESTION blocks — "state: draft, N+M questions remaining" — no error.

8. **THIRD: Log.** Use the Bash tool to log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <spec-id> | concerns | <count>" >> .claude/agentic/validation-log.txt
   ```

9. Print exactly this format (one `category:` line per concern):
   ```
   agentic-dev: AI validator verdict: concerns
     spec: <path>
     concerns: <count>
     category: <category-of-concern-1>
     category: <category-of-concern-2>
     action: approved reverted to false; new QUESTION-N blocks added
   Resolve the new questions and re-approve.
   ```
   IMPORTANT: print `category:` (singular) once per concern, not `categories:` (plural). The test script greps for `category: completion-criterion` and `category: scope-coherence` — these exact strings must appear in the output.

## On verdict: anything else

If the parsed JSON has a `verdict` value that is neither `"clean"` nor `"concerns"` (e.g., `"unclear"`, `"unknown"`, missing field, null), treat it as malformed output:

- Print: `agentic-dev: AI validator returned unrecognized verdict: <value>; leaving approved unchanged`
- Append to `.claude/agentic/validation-log.txt`:
  ```
  <ISO-8601 UTC timestamp> | <spec-id> | malformed | unrecognized verdict: <value>
  ```
- Do NOT modify the spec file. Leave `approved: true`.
- Exit.

This is the safe default: don't silently revert approval because of a parsing edge case the validator's contract didn't anticipate.

## Do NOT

- Do not run `find /` or any filesystem-wide search.
- Do not run the deterministic validator script.
- Do not modify the spec body outside what's specified above.
- Do not invoke the spec-drafter.
- Do not commit anything.
