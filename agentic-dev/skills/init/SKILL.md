---
description: Bootstrap a host project with the .claude/agentic/ state tree, project config, and starter state/queue files. Idempotent — safe to re-run.
---

# /agentic-dev:init

You are bootstrapping the current working directory as a host project for the agentic-dev system.

## How to interpret `$ARGUMENTS`

`$ARGUMENTS` may be one of:

1. **Empty** — prompt the user interactively for each config value (see "Interactive prompts" below).
2. **A path to a YAML file** — read that file and use its values as the configuration. Do not prompt interactively. The YAML must conform to `agentic-dev/schemas/config.schema.json` (relative to the plugin install root). Use the values directly; do not invent or modify them.

The YAML mode is for testing and scripted onboarding; the interactive mode is for normal human use.

**CRITICAL for YAML mode:** If `$ARGUMENTS` is non-empty, treat it as a path to a YAML config file. Use the Read tool to load it. If the file does not exist or is not valid YAML, report a clear error and exit without creating any files. Otherwise, you MUST:
1. Parse the YAML content
2. Use every value from the file exactly as written — no substitutions, no defaults, no invented values
3. Do NOT prompt the user for any values
4. Do NOT ask any questions — proceed directly to creating all files

## Idempotence

Before doing anything, check whether `.claude/agentic/` already exists in the current working directory.

- If it does **not** exist: create the full structure as specified below.
- If it **does** exist: do not overwrite any existing files. Print a summary of what is already present and exit. Do not prompt for re-configuration unless the user explicitly asks.

To check: use the Bash tool to run `test -d .claude/agentic && echo EXISTS || echo NOT_EXISTS`.

## Required directory structure

Create the following under `.claude/agentic/` in the current working directory:

```
.claude/agentic/
├── state.json
├── queue.yaml
├── config.yaml
├── checklist.yaml
├── memory.yaml
├── decisions.log
├── intents/
├── specs/
├── manifests/
├── diffs/
├── artifacts/
├── escalations/
└── prompts/
```

Use the Bash tool with `mkdir -p` for directories. Use the Write tool for file contents.

For each empty directory listed above, create a `.gitkeep` file inside it so the directory survives git commits.

## File contents

### `state.json`

```json
{
  "schema_version": "0.1",
  "circuit_breaker": {
    "state": "idle",
    "halted_reason": null,
    "halted_at": null,
    "halted_goal_id": null
  },
  "current_goal": null,
  "last_updated": "<CURRENT ISO 8601 UTC TIMESTAMP>"
}
```

Replace `<CURRENT ISO 8601 UTC TIMESTAMP>` with the actual current UTC timestamp in `YYYY-MM-DDTHH:MM:SSZ` format. Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` via the Bash tool to obtain it.

### `queue.yaml`

```yaml
schema_version: "0.1"
goals: []
```

### `config.yaml`

Write the configuration values gathered from either the YAML input file or the interactive prompts. Schema reference: `agentic-dev/schemas/config.schema.json` (defined in the plugin source — do NOT attempt to read it at runtime from the host project's working directory). Just verify the file you're producing is well-formed YAML and contains the required keys listed below.

Required fields and their derivations:

- `schema_version`: ALWAYS `"0.1"` (literal constant). This is always written to config.yaml even in YAML mode — it is the schema version of the file you're producing, not a user-supplied value. If the YAML input includes `schema_version`, it must equal `"0.1"`; reject anything else.
- `project.name`: from input or prompt; default to basename of current working directory
- `project.primary_language`: from input or prompt; ask "What is the primary language of this project? (e.g., python, typescript, go, rust)"; may be null
- `commands.test`: from input or prompt; ask "What command runs the test suite? (e.g., `npm test`, `pytest -q`, `go test ./...`)"; required, non-empty
- `commands.lint`: from input or prompt; ask "What command runs the linter? (e.g., `npm run lint`, `ruff check .`, `golangci-lint run`)"; required, non-empty
- `commands.typecheck`: from input or prompt; ask "What command runs the typechecker? (Leave blank if N/A)"; may be null
- `commands.build`: from input or prompt; ask "What command builds the project? (Leave blank if N/A)"; may be null
- `budgets.wall_clock_minutes_per_goal`: default `90` unless overridden in input
- `budgets.diff_lines_per_goal`: default `800` unless overridden in input
- `budgets.files_touched_per_goal`: default `25` unless overridden in input
- `sensitive_paths`: default to `["auth/**", "migrations/**", "schema/**", "secrets/**", "payments/**", "infra/**"]` unless overridden in input
- `telegram`: default `null` unless overridden in input
- `push_policy`: default `"hold"` unless overridden in input

After writing, validate the file is well-formed YAML and contains all required keys before exiting.

**IMPORTANT:** When writing config.yaml from a YAML input file, reproduce the exact values from that file. The `null` YAML values for `typecheck`, `build`, and `telegram` must be written as YAML `null` (or just left as blank/`~`). The `push_policy: hold` must be written as a plain string without quotes in YAML.

### `checklist.yaml`

```yaml
# Reviewer adversarial-pattern hints. Append-only. Each entry is an incident-derived rule.
# Schema: list of { date, incident, rule, caught_by }
entries: []
```

### `memory.yaml`

```yaml
# Orchestrator behavioral memory. Append-only. Each entry is an observation + consequence.
# Schema: list of { date, observation, consequence }
entries: []
```

### `decisions.log`

Create an empty file with a single header line:
```
# Human-reset decisions log. Append-only. Each entry: ISO timestamp | decision | goal_id | notes
```

## Interactive prompts (when `$ARGUMENTS` is empty)

Use the AskUserQuestion tool for each value that does not have a sensible default. Group related questions where possible (e.g., all three commands in one AskUserQuestion call with multiple questions).

For `project.name`, use the current directory basename as the default; only ask if the user wants to override.

For `sensitive_paths`, do not prompt — use the defaults. Tell the user they can edit `.claude/agentic/config.yaml` later to add project-specific sensitive paths.

For `telegram`, do not prompt during init. Inform the user that Telegram setup is done later via a future skill (`/agentic-dev:configure-telegram`, not in v0.1).

## Output

After all files are written, print a structured summary:

```
agentic-dev: init complete
  state file:      .claude/agentic/state.json
  queue file:      .claude/agentic/queue.yaml
  config file:     .claude/agentic/config.yaml
  test command:    <commands.test>
  lint command:    <commands.lint>
  budgets:         <wall_clock>m / <diff_lines>lines / <files_touched>files per goal
  push policy:     <push_policy>
  sensitive paths: <count> patterns

Next steps:
  - Review .claude/agentic/config.yaml and adjust as needed
  - When ready to queue a goal, run /agentic-dev:intent (ships in P2)
  - To inspect state, run /agentic-dev:status
```

## Do NOT

- Do not overwrite existing files. Idempotence is load-bearing.
- Do not invent values that the user didn't provide and that don't have a documented default.
- Do not skip the state.json or queue.yaml schema-required fields.
- Do not modify `.gitignore`, `package.json`, or any other project file.
- Do not commit anything. The user commits.
