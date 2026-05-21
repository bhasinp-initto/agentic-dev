---
description: Internal lifecycle skill (orchestrator-invoked). Sets up a worktree for an approved spec, dispatches implementer-strict subagent, captures the structured manifest, generates a diff envelope. Does NOT decide if work is "done" — that's reviewer's job in P5.
---

# /agentic-dev:_run-implementer

You are the lifecycle skill that runs one implementer pass for one approved spec. You are invoked explicitly (in P3) for testing, or by the orchestrator (P6+) as part of the autonomous loop.

**Internal skill** — the underscore prefix (`_run-implementer`) signals that this skill is not for direct human invocation in the normal agentic-dev workflow. It is dispatched by the orchestrator (P6+) or used directly by tests. Running it manually is fine for debugging.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` is the spec path to an approved spec file: `.claude/agentic/specs/<goal-id>.md`. If empty, print: `agentic-dev: /agentic-dev:_run-implementer requires a spec file path. Example: /agentic-dev:_run-implementer .claude/agentic/specs/2026-05-21-x.md` and exit.

## Pre-checks

1. Verify the spec file exists at the given spec path.
2. Verify the spec path matches `.claude/agentic/specs/*.md`.
3. Read the spec frontmatter. If `approved: false` or the `approved` key is absent, refuse with: `agentic-dev: spec not approved; cannot run implementer`. The spec must have `approved: true`.
4. Run `agentic-dev/bin/validate-spec.sh <spec-path>` to ensure mechanical correctness. If it exits non-zero, surface the validator's output and exit — do not proceed with a broken spec.

## Initialize the worktree

Extract the `goal_id` from the spec's filename (`.claude/agentic/specs/<goal-id>.md` → `<goal-id>`).

Run `agentic-dev/bin/worktree-init.sh <goal-id>` via the Bash tool. Capture stdout — this is the absolute path to the new worktree. If the command exits non-zero, surface the error and exit.

The kickoff JSON package at `<worktree-path>/.agentic-kickoff.json` is written by `worktree-init.sh` and contains goal_id, spec_path, baseline_ref, budget, sensitive_paths, project_commands, and worktree_path.

## Dispatch the implementer

Use the Agent tool with `subagent_type: implementer-strict`. Pass a prompt that instructs the subagent to:

1. Change working directory to the worktree path (via Bash — `cd <absolute worktree path>`).
2. Read `.agentic-kickoff.json` in that working directory.
3. Begin implementation per the spec.
4. Output its final manifest as a JSON object (no preamble, no fences).

Example dispatch prompt:

```
You are dispatched as implementer-strict for goal <goal_id>.

Worktree path (cd here first): <absolute worktree path>
Kickoff package: <absolute worktree path>/.agentic-kickoff.json
Spec path: <absolute spec path>

Per your calibration table and output contract:
- Read the kickoff and spec
- Plan tests, write tests first (TDD red), implement (green), commit in worktree
- Halt on ambiguity with clarifying_questions; never guess
- Out_of_spec_files must stay empty — that's a discipline failure
- When done (or blocked or interrupted), output your manifest as a single JSON
  object. No preamble. No code fences. Just JSON.
```

## Capture the manifest

The implementer's response should be a single JSON object. Parse and validate it:

1. Use Python (via Bash) to parse the implementer response as JSON. If parsing fails (malformed JSON), write a stub manifest with `status: implementer-output-malformed` to `.claude/agentic/manifests/<goal-id>.json`. Save the raw response to `.claude/agentic/manifests/<goal-id>.raw.json` for debugging. Log the error to `.claude/agentic/validation-log.txt`.

2. If parsing succeeds, validate the parsed manifest against `agentic-dev/schemas/manifest.schema.json` (use Python + jsonschema). If schema validation fails, save the malformed output to `.claude/agentic/manifests/<goal-id>.raw.json` and write a fallback manifest with `status: implementer-output-malformed`. Log to validation-log.txt.

3. If both parsing and schema validation pass, write the manifest to `.claude/agentic/manifests/<goal-id>.json` using the Write tool.

## Generate the diff envelope

After the manifest is written, generate the structured diff:

1. Read the manifest's `baseline_ref` and `head_ref`.
2. If `head_ref` is null (implementer halted before committing): skip diff envelope generation; note in stdout: `diff envelope: skipped - no commits`.
3. Otherwise:
   - Use Bash to run `git -C <worktree_path> diff --stat <baseline_ref>..<head_ref>` and full `git -C <worktree_path> diff <baseline_ref>..<head_ref>` for the raw patch.
   - Build the diff-envelope JSON per `agentic-dev/schemas/diff-envelope.schema.json`.
   - Validate the diff envelope against the diff-envelope schema (Python + jsonschema).
   - Write the validated envelope to `.claude/agentic/diffs/<goal-id>.json`.

## Output

Print a structured summary:

```
agentic-dev: implementer run complete

  goal: <goal_id>
  status: <manifest.status>
  worktree: <worktree_path>
  manifest: .claude/agentic/manifests/<goal_id>.json
  diff envelope: .claude/agentic/diffs/<goal_id>.json (or "skipped - no commits")

  diff stats: <files_touched> files / +<lines_added> -<lines_removed>
  tests: <ran> ran / <passed> passed / <failed> failed / <skipped> skipped
  lint: <lint>  typecheck: <typecheck>

  clarifying questions: <count>
  spec change requests: <count>
  deferrals: <count>
  out-of-spec files: <count>  <- should be 0; non-zero is a discipline failure

Next:
  - (P5) reviewer checks the manifest + diff envelope
  - (P6) orchestrator decides whether to advance, escalate, or halt
```

## Do NOT

- Do NOT clean up the worktree. Successful goals are cleaned by the orchestrator (P6) only after the reviewer (P5) approves. Halted goals are preserved for forensics.
- Do NOT mark the goal "complete" in the queue. That's the orchestrator's job after reviewer approval.
- Do NOT edit the spec file.
- Do NOT push anything.
- Do NOT call another skill (no nested skill invocation).
