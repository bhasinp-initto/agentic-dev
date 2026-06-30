# Multi-Component Support (fullstack monorepos)

**Date:** 2026-06-30
**Status:** Approved design — ready for implementation plan

## Problem

The agentic-dev pipeline is hardwired to a single toolchain. `config.yaml` carries one
`commands.{test,lint,typecheck,build}` and one `project.primary_language`
(`agentic-dev/schemas/config.schema.json:19-28`). That single set flows through the whole
pipeline:

- `bin/worktree-init.sh:91-96` copies the single command set into the kickoff and runs the
  baseline test **once, from the worktree root**.
- `bin/gate-rerun-tests.sh` re-runs that single `test` command from the worktree root and
  compares pass/fail counts to the manifest.
- `bin/gate-test-count-check.sh` compares manifest counts to the single baseline.

A typical fullstack monorepo has **separate directories with separate toolchains** — e.g.
`backend/` (pytest, ruff) and `frontend/` (npm test, eslint), each run from its own
directory. The current model can register only one of them. The other half is never tested,
linted, or gated. Result: the plugin can't be used on most real projects.

## Goal

Let one project declare multiple components, each with its own working directory and
toolchain, and have the gate pipeline test/lint each component **from its own directory**.
When a goal runs, only the components whose directories the diff touched are gated.

## Non-goals

- Per-goal command overrides in the spec (a fine future add-on; not this change).
- A new independent lint-**rerun** gate. Lint stays self-reported by the implementer today;
  this change only makes that reporting per-component.
- Changes to the Playwright walkthrough — it is already configured per-spec.

## Load-bearing decision: backward compatibility via normalization

We do **not** migrate existing configs. The existing top-level `project.primary_language` +
`commands` remain valid as the **single-component shorthand**. A single normalization rule is
applied wherever config is consumed:

> If `components` is present and non-empty, use it. Otherwise synthesize a one-element list:
> `[{ name: project.name, path: ".", primary_language: project.primary_language, commands: <top-level commands> }]`.

Consequences:
- Every existing onboarded project keeps working with no edits.
- Every existing single-component test passes unchanged.
- `path: "."` is the "matches everything" component (current behavior).

## Design

### 1. Config data model — `schemas/config.schema.json`

Add an optional top-level `components` array. Each item:

```yaml
components:
  - name: backend            # required, non-empty, unique within the list
    path: backend            # required; dir relative to repo root; "." allowed
    primary_language: python # optional, nullable
    commands:
      test: "pytest -q"      # required, non-empty
      lint: "ruff check ."   # required, non-empty
      typecheck: "mypy ."    # optional, nullable
      build: null            # optional, nullable
  - name: frontend
    path: frontend
    primary_language: typescript
    commands:
      test: "npm test"
      lint: "npm run lint"
      typecheck: "tsc --noEmit"
      build: "npm run build"
```

Rules:
- `components` is optional. If present it must be non-empty; each item requires
  `name`, `path`, and `commands.{test,lint}`.
- The top-level `commands` block remains required by the schema (single-component shorthand
  and back-compat). When `components` is supplied, the top-level `commands` is still written
  (mirrors the first/primary component) so older readers and the existing schema stay valid.
- `name` values must be unique. `path` values should not be nested in a way that makes
  ownership ambiguous (see touched-component detection); document this, do not hard-enforce.

### 2. Touched-component detection (shared rule)

A changed file `f` belongs to component `C` when `f` is within `C.path`:
- `C.path == "."` → owns every file.
- otherwise → `f` equals `C.path` or starts with `C.path + "/"` (path-segment prefix; avoid
  `front` matching `frontend`).

For a goal, the **selected components** = every component owning ≥1 changed file. The changed
file list comes from the manifest (`scope_check.in_spec_files` + `scope_check.out_of_spec_files`;
fall back to the diff envelope if needed). Files owned by no component are ignored for gating
but surfaced as a warning in gate output so the gap is visible. If multiple components could
own a file (nested paths), the **most specific** (longest matching `path`) wins.

### 3. Worktree baseline — `bin/worktree-init.sh`

- Build a `components` array in the kickoff. For each component, run its `test` command from
  `worktree/<path>` and capture per-component baseline counts using the existing cascading
  count parser.
- Keep `project_commands` and `baseline.test_counts` populated from the **first** component so
  any transition-period reader still works. New per-component logic reads `kickoff.components`.

Kickoff shape (additive):

```json
{
  "project_commands": { "test": "...", "lint": "...", "typecheck": null, "build": null },
  "baseline": { "test_counts": { "passed": 0, "failed": 0, "skipped": 0 } },
  "components": [
    {
      "name": "backend",
      "path": "backend",
      "commands": { "test": "...", "lint": "...", "typecheck": null, "build": null },
      "baseline_test_counts": { "passed": 0, "failed": 0, "skipped": 0 }
    }
  ]
}
```

### 4. Manifest — `schemas/manifest.schema.json`

Add optional `tests_by_component`:

```json
"tests_by_component": {
  "type": "array",
  "items": {
    "type": "object",
    "required": ["name", "ran", "passed", "failed", "skipped"],
    "additionalProperties": false,
    "properties": {
      "name": { "type": "string", "minLength": 1 },
      "ran": { "type": "integer", "minimum": 0 },
      "passed": { "type": "integer", "minimum": 0 },
      "failed": { "type": "integer", "minimum": 0 },
      "skipped": { "type": "integer", "minimum": 0 }
    }
  }
}
```

The aggregate `tests` object stays required (the **sum** across reported components) for status
display and single-component back-compat. `self_check.{lint,typecheck}` stays aggregate:
`clean` only if every touched component is clean; `failures` if any touched component fails.

### 5. Gates

**`bin/gate-rerun-tests.sh`** — if the kickoff has `components` and the manifest has
`tests_by_component`, iterate the **touched** components: run each component's `test` from
`worktree/<path>`, parse counts, compare to that component's manifest claim. Any per-component
mismatch is a blocking fail naming the component. If per-component data is absent (single
shorthand), fall back to today's single aggregate comparison.

**`bin/gate-test-count-check.sh`** — same shape: compare per-component manifest counts to the
matching per-component kickoff baseline when available; else fall back to the single baseline.

### 6. Implementer — `agents/implementer-strict.md`

- Read `kickoff.components`. For each component whose directory the change touches, run that
  component's `test` and `lint` **from its directory** before claiming completion.
- Report `tests_by_component` in the manifest plus the aggregate `tests` (the sum).
- The "completion" rule becomes: all in-scope work done AND every touched component's tests
  pass AND every touched component's lint/typecheck pass.

### 7. Init flow — `skills/init/SKILL.md`

- **Interactive:** first ask whether the project has a single component or multiple. Single →
  today's flow (writes top-level `commands`, no `components`). Multiple → loop collecting
  `name`, `path`, and the command set per component; write the `components` array (and mirror
  the first component into the top-level `commands` for schema/back-compat).
- **YAML mode:** accept an optional `components` block and reproduce it verbatim, same as
  other fields.
- Idempotence, the "do not overwrite", and "user commits" rules are unchanged.

### 8. Status + tests

- `skills/status/SKILL.md` lists each component (name, path, test/lint commands).
- Add multi-component fixtures and gate tests under `tests/`. Existing single-component tests
  must pass unchanged (the normalization rule guarantees this).

## Testing strategy

- **Normalization:** a config with only top-level `commands` produces exactly one component
  with `path: "."` and the original commands.
- **Detection:** files map to the correct component; `front` does not match `frontend`;
  nested paths resolve to the most specific; unmatched files produce a warning, not a crash.
- **Worktree baseline:** per-component baseline counts captured from each component dir.
- **Rerun gate:** a per-component count mismatch blocks and names the component; untouched
  components are not run.
- **Back-compat:** the full existing single-component test suite passes with no edits.

## Files touched

- `schemas/config.schema.json` (add `components`)
- `schemas/manifest.schema.json` (add `tests_by_component`)
- `bin/worktree-init.sh` (per-component baseline + kickoff `components`)
- `bin/gate-rerun-tests.sh` (per-touched-component rerun)
- `bin/gate-test-count-check.sh` (per-component baseline compare)
- `agents/implementer-strict.md` (run + report per touched component)
- `skills/init/SKILL.md` (multi-component prompts + YAML)
- `skills/status/SKILL.md` (list components)
- `tests/` (multi-component fixtures + cases)
