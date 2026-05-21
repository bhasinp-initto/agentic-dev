---
description: User entry point for drafting a new spec. Records the raw intent text, dispatches the spec-drafter subagent to produce a structured draft, writes the draft to disk. v0.2 supports fresh path and --refine mode.
---

# /agentic-dev:intent

You are the user entry point for drafting a new agentic-dev spec.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the free-form intent text describing what work the user wants to specify. It should be a single coherent goal in 1–3 sentences. If it's empty, refuse with: `agentic-dev: /agentic-dev:intent requires a free-form goal description. Example: /agentic-dev:intent "Add rate limiting per-tenant"`.

## --refine mode

If `$ARGUMENTS` begins with `--refine ` (a literal `--refine` followed by a space), this is refine mode.

Parse the remaining text as a spec file path. If the path:
- Does not exist → print `agentic-dev: --refine target does not exist: <path>` and exit.
- Does not match `.claude/agentic/specs/*.md` → print `agentic-dev: --refine target must be a spec file under .claude/agentic/specs/` and exit.
- Has `approved: true` in its frontmatter → print `agentic-dev: cannot --refine an approved spec; set approved: false first if you want to re-open it` and exit.

Otherwise:

1. Read the current spec file in full.
2. Parse it: extract the existing frontmatter, the sections, and the existing QUESTION-N blocks (both answered and unanswered).
3. Dispatch the spec-drafter subagent with refine inputs (described in the drafter agent definition). The drafter receives the CURRENT spec body and must produce an UPDATED spec body that:
   - Preserves every "Your answer:" line that has been modified by the human (anything that's not `[REPLACE THIS LINE...]`).
   - May add new QUESTION-N blocks if the human's answers exposed new ambiguities.
   - Never deletes or modifies existing answered QUESTIONs.
4. Write the drafter's response verbatim to the spec file (overwrites the previous content).
5. Print the same next-steps as the fresh path, but with `(refined)` annotating the spec path.

Skip the id generation, the idempotency check, the intent-file write step, and the config-defaults lookup in refine mode — they only apply to fresh intents.

## Pre-checks

Before doing anything else:

1. Verify the current working directory contains `.claude/agentic/state.json`. If it does not, print: `agentic-dev: not initialized in this project (run /agentic-dev:init first)` and exit.

2. Read `.claude/agentic/config.yaml` to extract the diff-budget defaults and sensitive_paths defaults. You'll pass these to the drafter.

## Generate the intent id

1. Derive a kebab-case slug from the first 5–8 meaningful words of `$ARGUMENTS`. Strip stop words ("the", "a", "an", "to", "for", "of", "in", "on", "and", "or", "but"). Lowercase. Replace non-alphanumerics with hyphens. Collapse repeated hyphens. Trim leading/trailing hyphens.

1a. If the derived slug is empty (e.g., the input was all stop words, or all punctuation), refuse: print `agentic-dev: cannot derive a meaningful slug from input. Please rephrase the goal with at least 1–2 content words. Got: "<$ARGUMENTS>"` and exit. Do NOT continue.

1b. If the slug exceeds 60 characters, truncate at the last hyphen that keeps it ≤60 characters, preserving meaningful word boundaries.

2. Get today's date in UTC: use `date -u +"%Y-%m-%d"` via the Bash tool.
3. Construct `intent_id` = `<YYYY-MM-DD>-<slug>`.
4. Construct `created_at` = current UTC timestamp in `YYYY-MM-DDTHH:MM:SSZ` format: `date -u +"%Y-%m-%dT%H:%M:%SZ"`.

## Idempotency check

Check if `.claude/agentic/intents/<intent_id>.md` already exists. If it does:
- Print: `agentic-dev: intent already exists at .claude/agentic/intents/<intent_id>.md`
- Print: `  Spec file: .claude/agentic/specs/<intent_id>.md`
- Print: `  To re-draft, use /agentic-dev:intent --refine .claude/agentic/specs/<intent_id>.md`
- Exit without writing anything.

## Write the intent file

Use the Write tool to create `.claude/agentic/intents/<intent_id>.md` with:
```markdown
---
id: <intent_id>
created_at: <created_at>
---

<$ARGUMENTS verbatim>
```

## Dispatch the spec-drafter subagent

Use the Agent tool (subagent_type: spec-drafter) with a prompt that includes:
```
You are drafting a spec for this intent.

intent_id: <intent_id>
intent_path: .claude/agentic/intents/<intent_id>.md
created_at: <created_at>

intent_text:
<$ARGUMENTS verbatim>

config_defaults (from .claude/agentic/config.yaml):
- wall_clock_minutes_per_goal: <value>
- diff_lines_per_goal: <value>
- files_touched_per_goal: <value>
- sensitive_paths: <list>

repo_overview:
<a brief summary of the host project: directory layout from `ls` or `find . -maxdepth 2 -type d`, primary language from .claude/agentic/config.yaml>

Output the complete spec markdown per your calibration table and output contract. Begin with the frontmatter opener `---`.
```

**Substitute all `<…>` placeholders with the actual computed values before dispatching.** The drafter must see real values (e.g., `intent_id: 2026-05-20-add-rate-limiting`), not literal placeholder text.

## Capture the drafter's output

The Agent tool returns the drafter's response. The response should begin with `---` (the frontmatter opener). If it doesn't, or if the response starts with `ERROR:`, do NOT write a spec file. Instead:
- Print the drafter's response to the user.
- Print: `agentic-dev: drafter did not return a valid spec.`
- Print: `  intent file preserved at: .claude/agentic/intents/<intent_id>.md`
- Print: `  To retry the draft, delete the intent file and re-run /agentic-dev:intent, or run /agentic-dev:intent --refine <spec-path> if a spec file already exists.`
- Exit.

## Write the spec file

If the drafter returned a valid spec body (starts with `---`):
- Use the Write tool to create `.claude/agentic/specs/<intent_id>.md` with the drafter's response verbatim.
- Count the number of `<!-- QUESTION-` markers in the body.
- Print:
  ```
  agentic-dev: intent drafted

    intent: .claude/agentic/intents/<intent_id>.md
    spec:   .claude/agentic/specs/<intent_id>.md
    questions to resolve: <count>

  Next:
    - Open the spec file and answer each QUESTION-N block by replacing the "Your answer:" line.
    - When all questions are resolved, set `approved: true` in the spec frontmatter.
    - After approval, run /agentic-dev:_check-approval <spec-path> to dispatch the AI validator.
  ```

## Do NOT

- Do not modify any project files outside `.claude/agentic/`.
- Do not commit anything.
- Do not invoke /agentic-dev:_check-approval automatically — that's an explicit user action.
- Do not modify the drafter's output before writing it. If it's malformed, refuse rather than fix it.
