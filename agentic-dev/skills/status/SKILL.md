---
description: Report the current state of the agentic-dev system in the host project — circuit breaker, queue counts, current goal, configuration summary.
---

# /agentic-dev:status

You are reporting the state of the agentic-dev system in the current host project. Be terse, structured, factual. No prose narration. No claims beyond what the files say.

## Steps

1. Use the Read tool to read `.claude/agentic/state.json`. If the file does not exist, print a single line: `agentic-dev: not initialized (run /agentic-dev:init)` and exit.

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
