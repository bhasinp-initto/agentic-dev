# Phase 7 — Cross-Session Memory + Auto-Learning Plan

**Goal:** Ship v0.7 — `checklist.yaml` (reviewer adversarial-pattern hints) and `memory.yaml` (orchestrator behavioral observations) become live: auto-appended on incidents, read by reviewer/drafter prompts at dispatch.

**Reference design:** `docs/superpowers/specs/2026-05-21-agentic-dev-phase-7-memory-design.md`.

**Cost policy:** Zero claude -p.

---

## Task 1: Schemas + tests

**Files:** `agentic-dev/schemas/{checklist,memory}.schema.json` + `tests/phase-7/{checklist,memory}_schema_test.py` + fixtures.

**Schema specs:** see design §3. Required top-level: schema_version (const "0.1") + entries (array). Entry shapes per design.

**Tests:** each schema gets positive + 3 negative (bad enum/missing field/short string).

**Commit:** `feat(phase-7): checklist + memory schemas`

---

## Task 2: log-incident.sh + test

**File:** `agentic-dev/bin/log-incident.sh` + `tests/phase-7/log_incident_test.sh`.

**Spec:** see design §5. `log-incident.sh <type> <key=value> ...`. type=checklist or memory; appends to appropriate yaml at `.claude/agentic/`; atomic write + schema validation; date auto-populates from current UTC.

**Tests:** append to checklist + memory; bad type refused; missing required keys refused; schema-invalid input refused without touching the file.

**Commit:** `feat(phase-7): log-incident helper`

---

## Task 3: Subagent prompt updates

**Files (modify):**
- `agentic-dev/agents/hardened-reviewer.md` — add section "Reading checklist.yaml at dispatch" per design §6
- `agentic-dev/agents/reviewer-adversary.md` — same addition
- `agentic-dev/agents/spec-drafter.md` — add section "Reading memory.yaml at dispatch"

**Tests:** Update P2/P5 structural tests to assert the new instructions are present.

**Commit:** `feat(phase-7): subagent prompts read checklist + memory at dispatch`

---

## Task 4: Auto-append wiring

**Files (modify):**
- `agentic-dev/skills/_run-reviewer/SKILL.md` — add step after concern processing: call `bin/log-incident.sh checklist ...` for each judgment/uncategorized concern that escalates
- `agentic-dev/skills/_advance-goal/SKILL.md` — add step in halt path: call `bin/log-incident.sh memory ...` with halt reason

**Tests:** Update P5 + P6 structural tests to assert log-incident invocation patterns.

**Commit:** `feat(phase-7): auto-append checklist + memory on incidents`

---

## Task 5: Closer

1. Create `tests/phase-7/run_all.sh` + P1-P6 regression
2. Bump plugin.json to 0.7.0
3. README v0.7 section + CHANGELOG v0.7.0 entry
4. Commit `docs(phase-7): v0.7.0 closer`

---

## Completion checklist

- [ ] All P7 tests pass; P1-P6 still pass
- [ ] plugin.json at 0.7.0
- [ ] CHANGELOG v0.7.0 entry
- [ ] 5 task commits
- [ ] Zero claude -p in P7 dev
