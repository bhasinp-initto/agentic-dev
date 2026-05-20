# Three-Role Agentic Development Pattern — Design

**Status:** Draft for review
**Date:** 2026-05-20
**Author:** Brainstorming session
**Source:** Evolution of `three-role-pattern.md` (the original human + conversational-Claude + Claude-Code pattern) into an agentic system where Role 2 is automated and pulls the human in only when needed.

---

## 1. Intent

Build a development system where:

- **Role 1 (Human)** stays the architectural authority and quality bar, but is pulled into the loop only when something genuinely needs human judgment.
- **Role 2 (Agentic)** runs an autonomous loop that drives implementation, reviews work, and escalates to the human conservatively — no over-confidence, no eagerness to deliver.
- **Role 3 (Implementer)** continues to do the actual coding work in a worktree.

The system must support **overnight async progress**: the human queues work in the evening, the system runs through it autonomously, and any blocking signal trips a circuit breaker that halts the queue and notifies the human. **Quality is the prime concern**; the system errs on the side of stopping rather than guessing.

## 2. Goals

- **G1** — Reduce per-cycle human wall-clock time (motivation #1 from the original brainstorm).
- **G2** — Enable overnight unattended progress with hard stops on any concern (motivation #2).
- **G3** — Preserve the original pattern's quality properties (specifications first, honest reporting, verification with teeth, methodology that improves from incidents).
- **G4** — Bill against the Max subscription's interactive usage, not the post-June-15 programmatic credit pool.
- **G5** — No third-party plugin dependencies (no ruflo, no Nimbalyst runtime). Build on stock Claude Code primitives.
- **G6** — Keep the architecture pivotable: today's same-model reviewer (Option C) should be swappable to cross-model (Codex) review later (Option B/D) via configuration.

## 3. Non-goals

- Multi-developer collaboration (single-developer projects only for v1).
- Headless / `claude -p` operation (would land in the programmatic billing pool).
- Visual IDE / dashboard (the morning review surface is plain files + Telegram digest).
- Fully unattended execution across days (daily morning checkpoint is intentional).
- Replacing the original three-role pattern wholesale for projects where the human-in-every-cycle property is desirable.

## 4. The roles, refined

The original "Role 2" is split into three subagents inside the agentic system, plus the implementer. The split mirrors the original document's insight that **cognitive bandwidth dedicated to one job produces better outcomes than one entity juggling multiple jobs**.

```
Role 1 — Human (you)
  ↑ pulled in only by orchestrator escalation
Role 2a — Orchestrator (Claude Code skill, agentic)
  - drives the loop, runs deterministic gates, computes verdicts,
    routes to subagents, decides what to escalate
Role 2b — Reviewer (Claude Code subagent, read-only)
  - audits diffs against spec; outputs structured verdict only;
    no Edit/Write/mutating Bash tools
Role 2c — Spec drafter (Claude Code subagent)
  - expands human intent into spec with flagged questions;
    refuses to guess on architectural decisions
Role 3 — Implementer (Claude Code subagent, agentic on a worktree)
  - implements the spec in an isolated worktree;
    asks clarifying questions through the orchestrator;
    produces a structured completion manifest
```

**Why three subagents instead of one Role 2:** correlated blind spots are the central risk of same-model review. Separating drafter, reviewer, and orchestrator with sharply different system prompts, tool sets, and roles is the practical hardening lever available without going cross-model. The reviewer in particular must never become "the orchestrator that also reviews" — when an agent has agentic power, it gets tempted to fix-and-proceed instead of flag-and-halt.

## 5. Execution substrate (Path A)

All four agents run inside a single **long-lived interactive Claude Code session** that the human launches. Subagents dispatch via the native `Agent` tool, which keeps usage on the Max plan's interactive budget rather than the post-June-15 programmatic credit pool.

The system is packaged as a **Claude plugin** named `agentic-dev`, installed once per machine and reused across any number of host projects. The plugin ships the *software* (skills, subagents, hooks, gate scripts, default prompts); each host project keeps its own *state* in `.claude/agentic/`. This separation means upgrading the plugin lifts every project at once, while project-specific overrides (custom prompts, project test/lint commands) stay local to that project.

| Concern | Mechanism |
|---|---|
| Packaging & distribution | Claude plugin `agentic-dev` via git-hosted marketplace; namespaced skills like `/agentic-dev:run` |
| Orchestrator's main loop | Plugin skill: `/agentic-dev:run` |
| Subagent definitions | Plugin's `agents/` directory (spec-drafter, hardened-reviewer, reviewer-adversary, implementer-strict) |
| Deterministic gates | Plugin's `hooks/hooks.json` + shell scripts in plugin's `bin/` |
| Between-cycle sleeps | `ScheduleWakeup` or `/loop` (stock Claude Code skill) |
| Per-project state, queue, escalations, checklist | Files under `.claude/agentic/` in the host project (git-versioned with the project) |
| Notifications | Telegram MCP (declared via plugin's `.mcp.json`) + local file queue |
| Worktree isolation | Native `git worktree`, one per goal (Nimbalyst pattern borrowed) |
| Structured diff | JSON envelope around git patch (Nimbalyst pattern borrowed) |

**State-in-files discipline** is load-bearing. The orchestrator's conversation context is a thin shell; all durable state lives on disk. At any wake-up, the orchestrator re-derives "what's next?" by reading `.claude/agentic/state.json`, the queue, and the manifests. This bounds context growth and makes morning restart trivial.

## 6. The lifecycle

### 6.1 Intent → Spec → Approval (sync, the human's high-leverage time)

```
1. Human states intent
   - Free-form: voice note, issue text, paragraph
   - Stored as `.claude/agentic/intents/<id>.md`

2. Spec drafter expands intent → draft spec with flagged questions
   - Output: `.claude/agentic/specs/YYYY-MM-DD-<topic>.md`
   - Structured Q&A sections with concrete option choices
   - Drafter is forbidden from guessing on architectural decisions:
     "If a reasonable engineer could pick differently and it would
      matter to the outcome, you must flag it — even if one option
      seems obviously better to you."

3. Human answers questions inline; drafter iterates
   - Async-friendly: human can leave and return
   - Drafter loops until no flagged ambiguities remain

4. Drafter self-review (placeholder scan, contradictions, scope check)

5. Spec validator (deterministic + light AI)
   - File references resolve in the actual repo
   - All required sections present
   - Completion criteria measurable
   - Budgets sane

6. Human approves spec — LOAD-BEARING checkpoint
   - Explicit, recorded `approved: true` in frontmatter
   - Orchestrator never proceeds on silent approval or "looks ok"
```

### 6.2 Kickoff (orchestrator builds the handoff package)

The kickoff is not a "compressed prompt." It is a structured package the orchestrator hands to the implementer subagent:

```yaml
spec_path: .claude/agentic/specs/2026-05-20-rate-limiting.md
worktree_path: .worktrees/goal-2026-05-20-rate-limiting  # fresh git worktree
baseline:
  git_ref: <main HEAD sha at kickoff>
  test_counts: { passed: 412, failed: 0, skipped: 3 }
  lint_status: clean
  typecheck_status: clean
budget:
  diff_lines_max: 800
  files_touched_max: 25
  wall_clock_minutes_max: 90
adr_slot: docs/adr/ADR-NNNN-rate-limiting.md
```

### 6.3 Implementation (the implementer subagent runs)

Behavior contract:

- **Clarifying questions go to the orchestrator, not the human.** The orchestrator answers only if the answer is literally derivable from the spec text. Anything requiring inference, judgment, or new architectural decision → escalate to human, pause the implementer.
- **Ask before doing, not after.** The implementer is forbidden from "I assumed X" prose in any output. If unsure, ask first.
- **No prose verdict.** Implementer never claims success; that's the reviewer's job.
- **Completion output is a structured manifest** (section 6.4) written to `.claude/agentic/manifests/<goal-id>.json`.

### 6.4 Completion manifest (what the implementer hands back)

```json
{
  "spec_id": "2026-05-20-rate-limiting",
  "baseline_ref": "abc123",
  "head_ref": "def456",
  "diff_stats": { "files_touched": 11, "lines_added": 342, "lines_removed": 47 },
  "tests": { "ran": 421, "passed": 421, "failed": 0, "skipped": 3, "logs_path": "..." },
  "coverage_delta": "+0.4%",
  "scope_check": {
    "in_spec_files": [...],
    "out_of_spec_files": []
  },
  "adrs_filed": ["docs/adr/ADR-0042-rate-limiting.md"],
  "spec_change_requests": [],
  "deferrals": [
    { "item": "Admin override UI", "reason": "deferred to phase 2 per spec §7" }
  ],
  "clarifying_questions_asked": [
    {
      "question": "Should rate limits apply per-tenant or per-API-key?",
      "resolved_by": "spec_text",
      "answer": "per-tenant, per spec §3.2"
    }
  ],
  "artifacts": [
    { "kind": "playwright_screenshot", "path": "..." }
  ],
  "self_check": { "lint": "clean", "typecheck": "clean" }
}
```

**No prose summary. No "I built X." No "everything looks good."** Concerns about the work surface as `spec_change_requests` or `deferrals` — structured, machine-readable, reviewer-visible.

### 6.5 Verification (the orchestrator runs gates and routes to reviewer)

In order; each stage can halt the next:

1. **Deterministic gates** (orchestrator-owned hooks, no AI judgment):
   - Scope check: any file outside `scope_check.in_spec_files`? → blocking
   - Budget check: diff exceeds `budget.diff_lines_max` or `files_touched_max`? → blocking
   - Sensitive-path check: any of `auth/`, `migrations/`, `schema/`, `secrets/`, `payments/`, `infra/` touched? → escalate regardless of reviewer verdict
   - Test count: `tests.passed < baseline.test_counts.passed`? → blocking
   - Lint/typecheck: anything other than `clean` in self_check? → blocking (unless explicit deferral)

2. **Orchestrator re-runs the test suite itself** in the worktree.
   Does not trust the implementer's reported counts. Mismatch with manifest → blocking, no review needed.

3. **Reviewer subagent runs.** Receives:
   - Spec
   - Structured diff (JSON envelope around git patch)
   - Test output (raw, not "all passed" claim)
   - Artifacts (screenshots, logs)

   Does NOT receive: implementer's reasoning, commit messages by implementer, any prose framing of "what was done."

   Outputs: structured JSON verdict (section 7).

4. **Walkthrough** (for UI/integration work): Playwright runs against the worktree on golden paths and spec-attached edge cases. Findings categorized by severity.

5. **Second-pass adversary** on otherwise-clean reviews: "The first reviewer said this is clean. Find what they missed." Different system prompt; same artifacts. Cheap, surprisingly effective.

6. **Pre-existing-failure forensic**: if any failing test in the manifest is claimed "pre-existing," orchestrator runs `git bisect` against `baseline_ref`. Real pre-existing → noted. Caused by this diff → blocking.

## 7. Reviewer hardening (Option C with teeth)

The reviewer is a Claude Code subagent with sharply restricted configuration:

**System prompt**, adversarial (excerpt):
> Assume this diff is broken. The implementer's job was to make it look correct. Your job is to find where it isn't. List every concern with file:line and severity. If you find nothing, you must state what you specifically checked and why each check would have caught the relevant failure mode. You may not issue a "clean" verdict without enumerating checks performed.

**Tool restrictions** (in subagent `tools:` allowlist):
- Read, Grep, Glob: allowed
- Bash: allowed only for `git diff`, `git log`, test execution (read-only flags), file inspection
- Edit, Write, NotebookEdit: **denied**
- Agent dispatch: **denied** (no sub-sub-agent shenanigans)

**Input restrictions** (enforced by orchestrator at hand-off):
- Spec ✓
- Diff (structured JSON envelope) ✓
- Test output ✓
- Artifacts ✓
- Implementer's manifest `clarifying_questions_asked` + `deferrals` + `spec_change_requests` ✓ (these are structured, not narrative)
- Implementer's reasoning / commit messages / prose summary: **stripped before hand-off**

**Output schema**:
```json
{
  "verdict": "clean | concern | blocking",
  "concerns": [
    {
      "file": "src/foo.ts",
      "line": 42,
      "severity": "blocking | concern",
      "category": "mechanical | judgment",
      "description": "..."
    }
  ],
  "checks_run": [
    {
      "name": "scope_against_spec",
      "outcome": "pass | fail",
      "evidence": "..."
    }
  ]
}
```

**Memory of past failures**: `.claude/agentic/checklist.yaml` is appended to every time an incident produces a learning. The reviewer's prompt includes the current checklist as adversarial-pattern hints. Self-improving without requiring human curation, though the human can prune/edit the checklist freely.

## 8. Escalation policy

**Both deterministic gates AND reviewer-recommended escalation can trip the breaker. Once tripped, no AI can de-escalate.** Human must explicitly reset.

| Source | Signal | Action |
|---|---|---|
| Gate | Sensitive path touched | Escalate, regardless of reviewer verdict |
| Gate | Out-of-spec file touched | Escalate |
| Gate | Diff/file budget exceeded | Escalate |
| Gate | Test count drop | Escalate |
| Gate | Self_check non-clean | Escalate |
| Re-run | Manifest test counts don't match observed | Escalate |
| Reviewer | Verdict `blocking` | Escalate |
| Reviewer | Verdict `concern`, category `judgment` | Escalate |
| Reviewer | Verdict `concern`, category `mechanical` | Auto-fix loop, see §9 |
| Reviewer | Round-trips > 3 without convergence | Escalate |
| Forensic | "Pre-existing" failure actually introduced by this diff | Escalate |
| Spec drift | Implementer files `spec_change_requests` | Escalate (drafter + human re-engage) |
| Budget | 100% of token/$ wall-clock budget hit | Escalate (hard halt) |
| Budget | 80% of budget | Warning (non-blocking, in digest) |

**Default for uncategorized concerns: `judgment` → escalate.** Anti-eagerness applied to the categorization itself.

## 9. Concern handling — hybrid by type

When the reviewer returns `concern`:

- **`category: mechanical`** (coverage low, missing docstring, lint nit, missing test edge case, formatting drift) → orchestrator opens an auto-fix subtask for the implementer with the concern as a structured task. Re-review after fix. **Hard cap: 2 rounds**. After 2 rounds without convergence → escalate.
- **`category: judgment`** (architectural choice, security smell, scope drift, ambiguous error handling, API shape disagreement) → no auto-fix attempt. Escalate immediately.
- **`category: uncategorized`** → defaults to judgment → escalate.

The implementer in auto-fix mode receives the concern as a fresh task with the original spec + diff + concern. It does not get to argue back; it either fixes or escalates with a spec_change_request.

## 10. Overnight queue model (Path B from §Question 6 — linear queue + drafter running ahead)

The unit of an overnight run is a **queue**, not a single goal.

```
Queue state (persisted in .claude/agentic/queue.yaml):

  goals:
    - id: 2026-05-20-rate-limiting
      spec_path: ...
      status: approved   # ready to run
    - id: 2026-05-20-audit-log
      spec_path: ...
      status: approved
    - id: 2026-05-21-tenant-export
      spec_path: ...
      status: drafted    # drafter staged, not yet human-approved
    - id: 2026-05-21-search-index
      spec_path: null
      status: intent_only

  circuit_breaker: { state: running | halted | completed, halted_reason: "..." }
```

**Only `status: approved` goals run.** The drafter can prepare specs ahead of time (status `drafted`), but they sit in the queue until the human's next approval pass. This means **overnight throughput is gated by how many goals the human spec-approved before bed** — exactly the right tradeoff: human attention spent on the load-bearing decision (spec approval), not on real-time approvals during execution.

The drafter runs concurrently with the implementer when the queue has intent-only items. It cannot proceed without human spec-approval; it only stages drafts.

## 11. Circuit breaker

Single global state: `{ running, halted, completed }`. Any blocking signal flips to `halted`.

**On halt:**
1. Current goal's worktree is **frozen in place** (not rolled back). Human inspects it.
2. Downstream queued goals stay queued (not abandoned).
3. Escalation packet generated at `.claude/agentic/escalations/<timestamp>.md` with:
   - What was running
   - Why it halted (which signal, source)
   - Structured concerns from reviewer
   - Artifacts to inspect (diff, test output, manifest, screenshots)
   - Suggested next actions
4. Notification sent (see §12).
5. Orchestrator sleeps. No AI can reset.

**On human reset** (`/agentic-dev:resume` skill):
- Options: `resume` (re-attempt current goal), `skip` (mark current abandoned, advance), `address` (have implementer fix concerns), `replan` (re-engage drafter), `abort` (halt full queue).
- All decisions logged to `.claude/agentic/decisions.log`.

## 12. Escalation mechanics — severity-tiered

| Severity | Channel | Latency |
|---|---|---|
| `blocking` (circuit breaker trip) | Telegram push + file packet | Immediate |
| `budget 100%` (hard halt) | Telegram push + file packet | Immediate |
| `queue idle` (drafter blocked on human approval too long) | Telegram push + file packet | After N minutes |
| `concern` deferred from clean runs | Morning digest only | Next sync |
| `budget 80%` warning | Morning digest only | Next sync |
| `queue completion` | Telegram push + morning digest | Immediate (because the queue is now idle) |
| `clean goal completed` | Log only, no notification | None |

**Telegram payload is structured for triage on phone**: status emoji, goal id, one-line reason, deep-link to local escalation packet. Human can decide at 2am whether to investigate or wait.

Fallback: if Telegram MCP fails, all severities downgrade to file-queue-only and a `notifications.failed` log entry. The orchestrator never silently drops a notification.

## 13. Cross-session memory — the self-improving property

Two append-only files in `.claude/agentic/`:

**`checklist.yaml`** — reviewer adversarial-pattern hints:
```yaml
- date: 2026-05-22
  incident: ESC-2026-05-22-001
  rule: "When code adds a new DB query, check it goes through the tenant-scoped repository, not raw client"
  caught_by: human  # or `reviewer` (near-miss) or `gate`
```

**`memory.yaml`** — orchestrator behavioral memory (less prescriptive):
```yaml
- date: 2026-05-22
  observation: "Implementer tried to assume tenant_id for rate limiter; should have asked"
  consequence: "Added rule to drafter: rate-limit specs must explicitly state per-tenant scoping"
```

Both are loaded into the relevant subagent's prompt at dispatch time. The system gets harder to fool with each cycle.

Human can prune/edit/curate at any time. Files are git-diffable and audit-friendly.

## 14. State layout

The system has two layout trees: what ships in the **plugin** (versioned software, shared across all host projects) and what lives in each **host project** (versioned per-project state and overrides).

### 14.1 Plugin layout (what ships in `agentic-dev`)

```
agentic-dev/                              # the plugin directory
├── .claude-plugin/
│   └── plugin.json                       # name, version, description, author
├── README.md                             # install + usage
├── skills/
│   ├── init/SKILL.md                     # /agentic-dev:init  — bootstrap a project
│   ├── intent/SKILL.md                   # /agentic-dev:intent — start a new goal
│   ├── run/SKILL.md                      # /agentic-dev:run    — orchestrator main loop
│   ├── start/SKILL.md                    # /agentic-dev:start  — launch overnight queue
│   ├── resume/SKILL.md                   # /agentic-dev:resume — after a halt
│   ├── review/SKILL.md                   # /agentic-dev:review — morning review
│   ├── status/SKILL.md                   # /agentic-dev:status — current queue/state
│   └── restart/SKILL.md                  # /agentic-dev:restart — daily orchestrator reset
├── agents/
│   ├── spec-drafter.md                   # subagent: spec drafter
│   ├── implementer-strict.md             # subagent: implementer
│   ├── hardened-reviewer.md              # subagent: reviewer (read-only, adversarial)
│   └── reviewer-adversary.md             # subagent: second-pass adversary
├── hooks/
│   └── hooks.json                        # deterministic gate wiring
├── bin/
│   ├── scope-check.sh                    # gate: in-scope-files only
│   ├── sensitive-path-check.sh           # gate: auth/migrations/etc.
│   ├── budget-check.sh                   # gate: diff/file budget
│   ├── test-count-check.sh               # gate: test count drop
│   ├── rerun-tests.sh                    # orchestrator-owned test re-run
│   ├── bisect-on-claim.sh                # forensic for "pre-existing" failures
│   ├── strip-implementer-prose.sh        # strip reasoning before reviewer hand-off
│   └── telegram-send.sh                  # notification helper
├── prompts/                              # default subagent + skill system prompts
│   ├── orchestrator.md
│   ├── spec-drafter.md
│   ├── reviewer.md
│   ├── reviewer-adversary.md
│   └── implementer.md
├── schemas/
│   ├── spec.schema.yaml                  # spec frontmatter + section requirements
│   ├── manifest.schema.json              # completion manifest schema
│   ├── diff-envelope.schema.json         # structured diff schema
│   ├── verdict.schema.json               # reviewer output schema
│   └── escalation.schema.json            # escalation packet schema
├── .mcp.json                             # declares Telegram MCP dependency
└── settings.json                         # default settings applied when enabled
```

### 14.2 Per-project layout (lives in each host project)

```
<host-project>/
├── .claude/agentic/                      # versioned with the project
│   ├── state.json                        # orchestrator state, circuit breaker
│   ├── queue.yaml                        # goal queue
│   ├── config.yaml                       # project overrides: test/lint commands, budgets, telegram chat id
│   ├── intents/<id>.md                   # raw human intents
│   ├── specs/YYYY-MM-DD-<topic>.md       # drafted + approved specs
│   ├── manifests/<goal-id>.json          # completion manifests
│   ├── diffs/<goal-id>.json              # structured diff envelopes
│   ├── artifacts/<goal-id>/*             # screenshots, logs, test output
│   ├── escalations/<timestamp>-<goal-id>.md  # escalation packets
│   ├── checklist.yaml                    # reviewer adversarial-pattern hints (per-project)
│   ├── memory.yaml                       # orchestrator behavioral memory (per-project)
│   ├── decisions.log                     # human-reset decisions
│   └── prompts/                          # OPTIONAL per-project prompt overrides; if missing, plugin defaults apply
│       └── *.md
└── .worktrees/                           # one per active goal; cleaned on clean completion, preserved on halt
    └── goal-<id>/
```

**Precedence rules** when both plugin and project provide a thing:
- System prompts: per-project `.claude/agentic/prompts/*.md` overrides plugin's `prompts/*.md`
- Configuration: per-project `config.yaml` overrides plugin's `settings.json` defaults
- Checklist/memory: per-project files extend (do not replace) any plugin-provided baseline checklist

## 15. Spec template

Required sections (drafter generates, validator enforces, human approves):

1. **Intent** — one paragraph, the human's words preserved
2. **Scope** — what's included
3. **Out-of-scope** — what's explicitly NOT included, with reasoning
4. **Files in scope** — globs/paths the implementer is allowed to touch
5. **Architectural decisions** — explicit choices made at spec time (with alternatives considered)
6. **ADR candidates** — questions that warrant a formal ADR
7. **Test strategy** — what new tests, what existing tests must still pass
8. **Completion criteria** — measurable conditions for "done"
9. **Diff budget** — lines added/removed, files touched, wall-clock
10. **Deferrals** — items deliberately pushed to later
11. **Approval** — frontmatter `approved: true` set by human, with timestamp

Validator checks: all sections present, file references resolve, completion criteria contain measurable predicates (no "should work well"), out-of-scope is non-empty (forces the drafter to think about boundaries).

## 16. Defaults (overridable in `.claude/agentic/config.yaml`)

| Setting | Default | Why |
|---|---|---|
| Push-to-origin policy | Hold (human pushes after morning review) | Quality prime |
| Worktree on halt | Freeze in place | Forensic inspection possible |
| Auto-fix round cap | 2 | Prevent infinite mechanical-concern loops |
| Reviewer second-pass adversary | Enabled | Cheap, catches first-pass misses |
| Spec drift handling | Halt + drafter re-engage | Forensic over fast-forward |
| Budget — wall-clock per goal | 90 min | Sized for substantial-but-not-epic goals |
| Budget — diff lines per goal | 800 | Spec must declare own budget if larger |
| Telegram severity routing | §12 table | Sleep-friendly defaults |
| Cycle wake-up interval (ScheduleWakeup) | 30s while running, idle on halt | Responsive but not chatty |

## 17. Pivotability — preserving Options B / D as future configuration

Three contracts at the seam keep cross-model review (Codex) a config change later:

1. **Reviewer input** — a directory containing `spec.md`, `diff.json`, `tests.json`, `artifacts/`. Whatever the reviewer needs comes from this directory.
2. **Reviewer output** — the JSON schema in §7. Stable.
3. **Reviewer as subprocess** — orchestrator shells out to a reviewer command. Doesn't care if it's a Claude Code Agent dispatch, a Codex CLI invocation, or `bash run-linter.sh`. Just consumes the JSON.

If we keep those three clean, then:
- Option B (hybrid by stakes) is routing logic in the orchestrator: route to a Codex subprocess for high-stakes diffs.
- Option D (ensemble) is running both subprocesses in parallel and reconciling.

**Lock-in risk** lives in the spec drafter, not the reviewer. If the drafter's questions assume Claude-style phrasing or interaction, swapping it is harder. Mitigation: drafter outputs structured Q&A (JSON with question + options + flagged ambiguity type) rather than free-form prose, so the drafter is also swappable.

## 18. Borrowings from Nimbalyst (pattern, not dependency)

Two specific ideas adopted; no Nimbalyst code or runtime.

**Worktree-per-session isolation.** Each goal runs in `.worktrees/goal-<id>/` (native `git worktree`). Avoids cross-goal interference, makes "freeze on halt" cleanly enforceable, opens the door to parallel goals later (though v1 is linear). When a goal completes cleanly, worktree is pruned. When halted, preserved.

**Structured diff format.** Diffs are serialized as `.claude/agentic/diffs/<goal-id>.json` with the raw patch wrapped in a schema:
```json
{
  "goal_id": "...",
  "baseline_ref": "...",
  "head_ref": "...",
  "files": [
    {
      "path": "src/foo.ts",
      "change_kind": "modified | added | deleted | renamed",
      "lines_added": 12,
      "lines_removed": 3,
      "hunks": [...]
    }
  ],
  "raw_patch": "..."
}
```
Reviewer and gates parse against schema rather than scraping text. Also gives the human a clean substrate for morning diff review (rendered in any editor that understands JSON).

## 19. The human's day-in-the-life

**Evening (10–20 min, sync):**
- `/agentic-dev:intent "..."` for each thing to queue → drafter runs → human answers questions inline in spec files → marks `approved: true` for the ones ready to run
- Optionally: `/agentic-dev:start --until 07:00` to launch the overnight queue

**Overnight (async):**
- Orchestrator processes queue, dispatching subagents, running gates, routing concerns
- On any blocking signal: halt, freeze worktree, write escalation packet, Telegram push
- On clean goal completion: commit (hold), advance to next
- On queue completion: stop at clean state, Telegram digest

**Morning (15–30 min, sync):**
- Telegram digest: "3 goals clean, 1 halted on ESC-2026-05-21-002"
- `/agentic-dev:review` opens morning packet: list of clean goals (with diffs to inspect), escalations to triage, new checklist rules the system proposes (human approves or rejects)
- For each clean goal: review diff → `git push` (or push all)
- For halted: read escalation, choose `resume / skip / address / replan / abort`

**Provisioning the system (one-time per machine, ~15 min):**
- Install Claude Code (already installed)
- Add the plugin marketplace: `/plugin marketplace add <agentic-dev-repo-url>`
- Install the plugin: `/plugin install agentic-dev`
- Plugin's skills, subagents, hooks, gate scripts, and `.mcp.json` declarations are now available

**Per-project bootstrap (~5 min, runs once per host project):**
- In the host project directory, run `/agentic-dev:init`
- The skill creates `.claude/agentic/` structure, prompts for project test/lint commands, Telegram chat id, budget defaults, and any prompt overrides
- Project is now ready; the same plugin serves any number of projects

## 20. What's load-bearing (the properties the design depends on)

Drawn from the conversation; restated here as testable properties of the final system:

- **L1** — Reviewer never sees implementer's reasoning. Strip-before-handoff is enforced in the orchestrator.
- **L2** — Reviewer is read-only. Subagent tool list omits all mutating tools.
- **L3** — Orchestrator trusts artifacts, not claims. Test counts are re-run by orchestrator, not taken from manifest.
- **L4** — Implementer asks before doing, never after. "I assumed X" prose is a defect, not a deferral.
- **L5** — Spec approval is non-skippable. No silent approval.
- **L6** — Both deterministic gates and reviewer recommendations can escalate; once tripped, no AI can de-escalate.
- **L7** — Uncategorized concerns default to `judgment` → escalate. Anti-eagerness applied to categorization.
- **L8** — All durable state in files, not conversation. Bounds drift; enables crash/restart.
- **L9** — Worktree freezes on halt; never rolled back. Forensic-friendly.
- **L10** — Push is hold-by-default; human pushes after morning review.

## 21. Open questions / out-of-scope for v1

- **Cross-model reviewer (Options B/D)** — designed-for, not built. Pivot is configuration when triggered.
- **Multi-developer collaboration** — single-developer only for v1.
- **Visual dashboard** — morning review is files + Telegram. Nimbalyst could be revisited later as a viewing surface if needed.
- **Parallel goals** — architecture supports it (worktree per goal), but v1 runs goals linearly to avoid concurrent-modification surprises.
- **Long-running session drift mitigation** — daily morning `/agentic-dev:restart` is the working answer. If this proves insufficient, the next step is moving the orchestrator out of Claude Code into a thin Bash daemon that re-launches Claude Code sessions per cycle, accepting the programmatic billing implication.
- **Forensic git bisect cost** — bisect can be expensive on large repos. If a project has slow tests, bisect-on-"pre-existing"-claims may need a budget; if budget hit before resolution, escalate anyway.
- **Reviewer of the reviewer** — second-pass adversary is the answer; not adding a third pass unless empirically warranted.

## 22. Scope of the v1 build

Roughly 2–3 weeks of focused work, less if we descope:

1. **Plugin scaffold** — `.claude-plugin/plugin.json`, README, directory layout per §14.1
2. **Skills** — `/agentic-dev:init`, `:intent`, `:run`, `:start`, `:resume`, `:review`, `:status`, `:restart`
3. **Subagent definitions** — `spec-drafter`, `implementer-strict`, `hardened-reviewer`, `reviewer-adversary`
4. **State schemas + validators** — spec, manifest, diff envelope, verdict, escalation packet, queue, config
5. **Deterministic gate scripts in `bin/`** — scope, sensitive-path, budget, test-count, rerun-tests, bisect-on-claim, strip-implementer-prose, telegram-send
6. **Hook wiring** in `hooks/hooks.json` to invoke the gate scripts at the right Claude Code events
7. **Plugin `.mcp.json`** declaring Telegram MCP dependency
8. **Marketplace** — `marketplace.json` listing the plugin, hosted in a git repo for private install
9. **Plugin-level README + CLAUDE.md template** for host projects (so new sessions in a host project have context)
10. **Local install validation** — `claude --plugin-dir ./agentic-dev` end-to-end smoke test against a throwaway project

Descopable for a v0:
- Walkthrough/Playwright integration (defer; not all goals need UI verification)
- Second-pass adversary (start without; add when first-pass misses become a pattern)
- Auto-checklist self-improvement (start with manual checklist edits; auto-append later)
- Community-marketplace submission (private marketplace first; submit later if worth sharing)
- Memory/checklist self-improvement (start with manual checklist; auto-append later)

---

## 23. Distribution and lifecycle

How `agentic-dev` gets built, hosted, installed, configured, and upgraded.

### 23.1 Source repository

A single git repository (this one, `agenticDev/`) holds:
- The plugin source tree under `agentic-dev/` (created in v1 implementation)
- A `marketplace.json` at the repo root declaring the plugin
- This design doc, planning docs, and any future ADRs under `docs/`

The plugin is the only thing distributed; the rest is project documentation.

### 23.2 Hosting strategy

**v1 — private git repo as marketplace.** Push to a GitHub repo you control. Users (initially just you) add the marketplace with:

```
/plugin marketplace add <github-org>/agentic-dev
/plugin install agentic-dev
```

No marketplace approval, no public exposure, full control over rollout. Good fit while the system is still being shaped by real usage.

**v2 (optional) — community marketplace submission.** If the plugin is worth sharing publicly, submit via Anthropic's review form to land in `claude-plugins-community`. Pinned to specific commit SHAs, auto-updated by CI. Approval requires `claude plugin validate` to pass locally + Anthropic's automated safety screen.

**v3 (unlikely) — official marketplace.** Curated by Anthropic at their discretion; no application process.

### 23.3 Versioning

Use **explicit `version` field** in `plugin.json`, not commit-SHA versioning. Reason: with SHA versioning, every commit counts as a new version, which would push partially-developed changes to any installed user. Explicit versioning gives a stable rollout cadence.

Semantic versioning, with the following meaning for breaking changes:
- **Major** — incompatible state-schema changes (e.g., manifest schema bumped, queue.yaml format breaks)
- **Minor** — new skills, new gates, new defaults that don't break existing projects
- **Patch** — bug fixes, prompt refinements, documentation

State-schema migrations ship as part of major bumps with explicit migration scripts in `bin/migrate-vN-to-vM.sh`.

### 23.4 Per-project upgrade flow

When the plugin updates:
1. User runs `/plugin update agentic-dev`
2. Plugin's `agents/`, `skills/`, `hooks/`, `bin/`, `prompts/`, `schemas/` all refresh
3. Each host project picks up the new version on next session start
4. If the new version has a schema migration, `/agentic-dev:status` detects it and prompts the user to run the migration script before continuing

Per-project state in `.claude/agentic/` is **never** modified by a plugin upgrade. Only explicit migration scripts touch it, and only with the user's go-ahead.

### 23.5 Configuration surface

Three layers, in order of precedence (highest wins):

1. **Per-project overrides** in `.claude/agentic/config.yaml` and `.claude/agentic/prompts/*.md`
2. **Plugin defaults** in plugin's `settings.json`, `prompts/`, and `bin/` scripts
3. **Built-in fallbacks** baked into skill and subagent definitions

Each host project answers (via `/agentic-dev:init`):
- Test command (`npm test`, `pytest`, `go test ./...`, etc.)
- Lint command
- Typecheck command (if any)
- Telegram chat id (if using notifications)
- Budget caps (defaults reasonable; override per project)
- Sensitive-path globs (defaults sensible; project may add more)
- Spec/diff directory locations (defaults fine for most projects)

These land in `.claude/agentic/config.yaml`, git-versioned with the project.

### 23.6 Validation and CI for the plugin itself

The plugin repo has its own CI:
- `claude plugin validate` runs on every PR
- Schema linting on `schemas/*.json` and `schemas/*.yaml`
- Shell scripts in `bin/` pass `shellcheck`
- Smoke test: spin up a throwaway repo, run `claude --plugin-dir ./agentic-dev`, exercise `/agentic-dev:init` + `/agentic-dev:status`

The smoke test catches the most common regression: a plugin update that subtly breaks one of the skills or hook wirings.

### 23.7 Disinstall and project independence

A host project that has used `agentic-dev` keeps its `.claude/agentic/` state forever — the directory is plain files, readable without the plugin. If the plugin is uninstalled, the project still has its specs, manifests, escalations, decisions log, etc. as documentation of what happened.

Removing the plugin without disabling per-project state cleanup is intentional: the project's audit trail of how it was built shouldn't disappear because someone uninstalled a tool.

---

## Appendix A — Mapping to the original three-role-pattern.md

| Original property | Agentic equivalent |
|---|---|
| Conversational Claude drafts specs | Spec drafter subagent (§4, §6.1) |
| Compressed kickoff prompt to Claude Code | Structured kickoff package (§6.2) |
| Claude Code asks clarifying questions | Implementer asks orchestrator; orchestrator answers from spec only (§6.3) |
| Developer reviews completion summary | Reviewer subagent + deterministic gates + orchestrator verdict (§6.4–6.5) |
| Conversational Claude pushes back | Adversarial reviewer prompt + second-pass adversary (§7) |
| Methodology improves from incidents | checklist.yaml + memory.yaml (§13) |
| Stop at clean state | Circuit breaker, queue, freeze-on-halt (§10–11) |
| Verification has teeth | Re-run tests, forensic bisect, structured diff, no prose claims (§6.5) |

## Appendix B — Why not Path B / D right now

Path B (SDK daemon) and Path D (thin wrapper invoking `claude -p`) both fall into Anthropic's **programmatic billing pool** post-June-15-2026 ($200/mo for Max 20x, non-rollover). For overnight runs with multiple substantial goals, this cap is realistic to hit within a few nights. Path A's interactive billing is intended to avoid this cap entirely.

**Working assumption flagged for verification:** Path A relies on the read of Anthropic's policy that subagents dispatched via the `Agent` tool within a human-launched interactive Claude Code session bill against the Max plan's interactive budget rather than the separate programmatic credit pool. This is the most natural reading of the published distinction, but is not yet confirmed in writing by Anthropic at the level of "subagent dispatch within an interactive session." **Worth verifying with Anthropic support before committing significant build effort** — if subagent-Agent-tool usage gets classified as programmatic, the entire economic case for Path A changes and we should revisit Path B with budget-aware throttling.

If the long-running interactive session model proves untenable for non-billing reasons (e.g., context drift not bounded by daily restart, crash-recovery awkwardness), the migration target is Path B with budget-aware throttling.
