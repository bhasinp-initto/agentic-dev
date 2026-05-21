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

After the Agent tool returns, parse the JSON from the subagent's response using the Bash tool:

```bash
python3 -c "
import json, sys
text = '''<subagent-response>'''
obj = json.loads(text)
print('verdict=' + obj['verdict'])
for c in obj.get('concerns', []):
    print('concern_category=' + c['category'])
    print('concern_section=' + c['section'])
    print('concern_idx=' + str(c.get('criterion_index', 'null')))
    print('concern_explanation=' + c['explanation'])
    print('concern_question=' + c['suggested_question'].replace('\n', '\\\\n'))
"
```

If the python3 command fails (JSON parse error), take these actions:
1. Print: `agentic-dev: AI validator returned malformed output; logging to .claude/agentic/validation-log.txt`
2. Use the Bash tool: `echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | MALFORMED | ..." >> .claude/agentic/validation-log.txt`
3. Leave `approved: true` unchanged. Exit.

## On verdict: clean

Print exactly:
```
agentic-dev: AI validator verdict: clean
  spec: <path>
  status: approved (no concerns)
```

Use the Bash tool to append to `.claude/agentic/validation-log.txt`:
```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <spec-id> | clean" >> .claude/agentic/validation-log.txt
```

Do NOT modify the spec file. Do not edit anything.

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
   Note: the `suggested_question` value starts with `(<category>)\n` — use that category in the marker. So if `suggested_question` starts with `(completion-criteria)\n**Q:** What latency...` then the marker is `<!-- QUESTION-<N> (completion-criteria) -->`.

4. For the FIRST concern only, also prepend this one-time comment:
   ```
   <!-- spec-validator-ai found new ambiguities; resolve before re-approval -->
   ```

5. Use the Edit tool to insert the new block(s) into the spec. Find the section named in `concern.section` and insert the new QUESTION block just before the next `# ` heading that follows that section. If the section is the last one, insert before the end of the file.

**After inserting all QUESTION blocks:**

6. Use the Edit tool to change `approved: true` to `approved: false` in the frontmatter.

7. Use the Bash tool to log:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <spec-id> | concerns | <count>" >> .claude/agentic/validation-log.txt
   ```

8. Print exactly this format (one `category:` line per concern):
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

## Do NOT

- Do not run `find /` or any filesystem-wide search.
- Do not run the deterministic validator script.
- Do not modify the spec body outside what's specified above.
- Do not invoke the spec-drafter.
- Do not commit anything.
