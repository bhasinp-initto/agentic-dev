# Phase 7 — Cross-Session Memory + Auto-Learning Design

**Date:** 2026-05-21 · **Phase:** P7/8 · **Umbrella spec:** §13 (cross-session memory pattern)

## 1. Intent

P7 ships the self-improving discipline: when an incident occurs (reviewer catches something, gate fires, escalation happens), an append-only entry lands in `.claude/agentic/checklist.yaml` (reviewer adversarial-pattern hints) or `.claude/agentic/memory.yaml` (orchestrator behavioral memory). Subagent prompts (drafter, hardened-reviewer, reviewer-adversary) read these at dispatch time and adapt their behavior. The system gets harder to fool each cycle without explicit human curation, though the human can prune/edit at any time.

## 2. Goals

- **G1** — Schemas for `checklist.yaml` and `memory.yaml` matching the umbrella §13 shape.
- **G2** — `bin/log-incident.sh` helper — single entry point for appending incidents.
- **G3** — Auto-append wiring in `_run-reviewer` (judgment concerns → checklist entries) and `_advance-goal` (halt patterns → memory entries).
- **G4** — Subagent prompt modifications — `hardened-reviewer` and `reviewer-adversary` read `.claude/agentic/checklist.yaml` at dispatch; `spec-drafter` reads `memory.yaml`.
- **G5** — Zero `claude -p` in P7 tests (per cost policy).

## 3. Schemas

### `checklist.schema.json`

```json
{
  "schema_version": "0.1",
  "entries": [
    {
      "date": "2026-05-21",
      "incident_ref": "ESC-2026-05-21-001",
      "rule": "When code adds a new DB query, check it goes through the tenant-scoped repository, not raw client",
      "caught_by": "human | reviewer | adversary | gate"
    }
  ]
}
```

Required at top level: schema_version (const "0.1"), entries (array).
Entries required: date (YYYY-MM-DD), incident_ref (string), rule (string min 10), caught_by (enum).

### `memory.schema.json`

```json
{
  "schema_version": "0.1",
  "entries": [
    {
      "date": "2026-05-21",
      "observation": "Implementer guessed tenant_id when spec was silent",
      "consequence": "Added explicit rule to drafter calibration table for tenant-scoping specs"
    }
  ]
}
```

Top-level: schema_version, entries. Entry fields: date, observation (string min 10), consequence (string min 10).

## 4. Architecture

```
agentic-dev/
├── schemas/
│   ├── checklist.schema.json   NEW
│   └── memory.schema.json      NEW
├── bin/
│   └── log-incident.sh         NEW — appends to checklist OR memory
└── (modifications)
    ├── agents/hardened-reviewer.md      — instruction to read checklist.yaml
    ├── agents/reviewer-adversary.md     — same
    ├── agents/spec-drafter.md           — instruction to read memory.yaml
    ├── skills/_run-reviewer/SKILL.md    — append to checklist on judgment concerns
    └── skills/_advance-goal/SKILL.md    — append to memory on halts
```

The init skill (P1) already creates checklist.yaml and memory.yaml as empty files — P7 just adds schemas + wiring.

## 5. `bin/log-incident.sh`

```
Usage: log-incident.sh <type> <key=value> [<key=value> ...]
Type: checklist | memory
```

- type=checklist: requires `rule`, `caught_by` (and ideally `incident_ref`); date auto-populates from now
- type=memory: requires `observation`, `consequence`; date auto-populates

Reads existing YAML, appends to entries array, validates against schema, atomic write.

## 6. Subagent prompt modifications

### hardened-reviewer + reviewer-adversary

Add a new section near the top: "Before reviewing, read `.claude/agentic/checklist.yaml`. Each entry is a rule derived from a past incident. Apply these rules as additional adversarial-pattern hints during your review. They are not exhaustive — your judgment dimensions (spec compliance + risk detection) still apply — but specifically check for the pattern each entry names."

If checklist.yaml has no entries (fresh project), proceed with default behavior.

### spec-drafter

Add a section: "Before drafting, read `.claude/agentic/memory.yaml`. Past observations may inform the questions you should flag for this intent. For example, if memory has 'Implementer guessed tenant_id when spec was silent', proactively include a QUESTION-N about tenant scoping when drafting any spec that touches tenant-aware code."

If memory.yaml has no entries, proceed with defaults.

## 7. Auto-append wiring

### `_run-reviewer` updates

After processing concerns:
- For each `judgment` or `uncategorized` concern that triggers escalation, call `bin/log-incident.sh checklist rule="<concern.description>" caught_by=reviewer incident_ref="<escalation packet name>"`
- This happens BEFORE generating the escalation packet so the packet itself can note "added to checklist for future reviews"

### `_advance-goal` updates

On halt path:
- After circuit-breaker halt, call `bin/log-incident.sh memory observation="<reason>" consequence="goal <id> halted; review escalation packet for resolution"`
- Conservative: only on halts, not every escalation (would generate too many low-signal entries)

## 8. Testing strategy

Deterministic only. Zero `claude -p`.

- `checklist_schema_test.py` — positive + 3 negative
- `memory_schema_test.py` — positive + 3 negative
- `log_incident_test.sh` — appending to checklist and memory; bad type refused; validation errors caught
- Structural tests for the agent/skill modifications (verify required phrases added)

## 9. Load-bearing properties

- **P7-L1** — checklist + memory are append-only (no deletions or modifications by the system; only humans prune)
- **P7-L2** — Schemas validated on every append; corrupt entries refused before write
- **P7-L3** — Reviewer reads checklist at dispatch — fresh state per goal
- **P7-L4** — Failures to append (schema fails, file lock, etc.) log and continue; never block the pipeline

## 10. Scope of v0.7 build

T1: 2 schemas + 2 schema tests
T2: bin/log-incident.sh + test
T3: Subagent prompt modifications (hardened-reviewer, reviewer-adversary, spec-drafter) + structural test updates
T4: Auto-append wiring in _run-reviewer + _advance-goal + structural test updates
T5: Aggregator + version bump + docs

5 tasks (smaller than prior phases). Estimated cost: <$1.

## 11. Out of scope

- Memory pruning UI (humans use a text editor)
- Cross-project memory sharing (each project has its own)
- ML-based pattern recognition (rules are derived literally from incident descriptions)
- Forgetting / retention policies (humans curate manually)
