---
description: Report the current state of the agentic-dev system in the host project — circuit breaker, queue counts, current goal, configuration summary.
---

# /agentic-dev:status

You are reporting the state of the agentic-dev system in the current host project. Be terse, structured, factual. No prose narration. No claims beyond what the files say.

## Steps

1. Use the Read tool to check all three required state files:
   - `.claude/agentic/state.json`
   - `.claude/agentic/queue.yaml`
   - `.claude/agentic/config.yaml`

   - If ALL three are missing: print `agentic-dev: not initialized (run /agentic-dev:init)` and exit.
   - If `state.json` is missing but the others exist: print `agentic-dev: not initialized (run /agentic-dev:init)` and exit. (state.json is the authoritative initialization marker.)
   - If `state.json` exists but `queue.yaml` and/or `config.yaml` are missing: print `agentic-dev: warning — partial initialization detected (run /agentic-dev:init to repair)` followed by a list of which files are missing. Then continue to produce a partial report — read whichever files do exist, show their data, and clearly mark the missing-file sections (e.g., `  queue:             (file missing)` or `  project:           (config.yaml missing)`).

   The point: never silently fall back to defaults. Always make missing-file state visible to the user.

2. Use the Read tool to read `.claude/agentic/queue.yaml`.

3. Use the Read tool to read `.claude/agentic/config.yaml`.

4. Compute queue counts by status. Group goals by their `status` field; for each status that has at least one goal, you will report it.

5. Print a structured status block:

```
agentic-dev: status

  project:           <config.project.name>
  language:          <config.project.primary_language or "unspecified">
  push policy:       <config.push_policy>

  circuit breaker:   <state.circuit_breaker.state>
  current goal:      <state.current_goal or "none">
  last updated:      <state.last_updated>

  queue:
    intent_only:     <count>
    drafted:         <count>
    approved:        <count>
    running:         <count>
    completed:       <count>
    halted:          <count>
    abandoned:       <count>

(Only print the status lines whose count > 0. Skip any status with count = 0. If
all counts are zero, print `    (queue is empty)` as a single line under `queue:`
instead of any individual status lines. See Step 6 for full empty-queue handling.)

  test command:      <config.commands.test>
  lint command:      <config.commands.lint>
  typecheck:         <config.commands.typecheck or "n/a">
  build:             <config.commands.build or "n/a">

  budgets per goal:
    wall clock:      <config.budgets.wall_clock_minutes_per_goal>m
    diff lines:      <config.budgets.diff_lines_per_goal>
    files touched:   <config.budgets.files_touched_per_goal>
```

If the circuit breaker state is `halted`, append a halt block after the budgets section:

```

  HALTED:
    reason:          <state.circuit_breaker.halted_reason>
    at:              <state.circuit_breaker.halted_at>
    goal:            <state.circuit_breaker.halted_goal_id>
```

6. Skip any queue-status counts that are zero (only print non-zero ones). If the queue is entirely empty, print `    (queue is empty)` under the `queue:` heading instead of a list.

## Do NOT

- Do not modify any files. This skill is read-only.
- Do not infer state that isn't in the files. If `current_goal` is null, print "none" — don't guess.
- Do not run any commands. Just read files and format output.
- Do not invoke other skills or subagents.
