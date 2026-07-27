# Codex-backed adversary review pass

**Date:** 2026-07-22
**Status:** Approved design — ready for implementation plan
**Provenance:** Design was adversarially reviewed in-session by Codex (openai-codex
plugin, `codex-companion.mjs` v1.0.6). Codex raised 7 material findings against the
first draft; all 7 were accepted and folded into this design. Each is cited below where
it applies.

## Problem

The agentic-dev P5 review gate (`agentic-dev/skills/_run-reviewer/SKILL.md`) uses a single
model — Claude — for both the primary review (`hardened-reviewer`) and the adversarial
second pass (`reviewer-adversary`). Same model, same blind spots. Cross-model review is the
standard way to catch what one model systematically misses, and the `codex@openai-codex`
plugin already ships a structured, schema-validated adversarial reviewer we can drive
(`codex-companion.mjs adversarial-review`).

But Codex is a **separate plugin** that a given agentic-dev user may not have installed,
may have installed without the CLI, or may not have authenticated. The integration must be
pure upside: when Codex is present it strengthens the review; when it is absent or unhealthy
the pipeline behaves exactly as it does today.

## Goal

Add Codex as a second, independent-model adversary at P5. When Codex is available and
enabled, it runs **alongside** the Claude `reviewer-adversary` (augment, not replace) and
its concerns are unioned into the existing routing. When Codex is absent, disabled,
not-ready, errored, or times out, P5 falls back to Claude-only and records why. Codex
failure never blocks the pipeline.

## Non-goals

- **`agentic-dev:config` reconfigure command** — a real gap (today init settings can only be
  changed by re-running init or hand-editing config). Tracked as a **separate follow-on spec
  (Spec 2)**; this design only defines the config *field*.
- **Codex review of the intent/spec/plan** before the user answers questions — a distinct
  Codex touchpoint (reviews a *document*, not a git diff). Tracked as **Spec 3**; it will
  reuse the bridge built here.
- The codex plugin's optional **stop-gate hook**.
- **Replacing** the Claude adversary. Augment only.
- **Auto-installing** the codex plugin. Init detects and recommends; installing a plugin is
  a user `/plugin` action.

## Load-bearing decision: Codex is a strict, opt-in enhancement

Two rules keep existing installs safe (the same normalization ethos as multi-component
support):

1. **Absent config ⇒ Codex off.** [Codex finding #7] An optional `review.codex_adversary`
   field defaults to `off`. A project whose config has no `review` block is byte-for-byte
   unchanged on upgrade — no new latency, cost, verdicts, or escalations. `init` writes
   `auto` for **newly** initialized projects; existing projects opt in by re-running init or
   (later) the Spec-2 config command.
2. **Any Codex unavailability ⇒ silent, logged fallback to Claude-only.** Not-installed,
   CLI-missing, unauthenticated, subprocess error, timeout, unparseable output, or
   schema-invalid output all resolve to the same outcome: log the reason, note it in the P5
   summary, proceed on the Claude adversary result. Codex never blocks.

## Design

### 1. Config field (additive, backward-compatible)

Add an **optional** `review` object to `agentic-dev/schemas/config.schema.json` — NOT added
to the top-level `required` array, so every existing config stays schema-valid:

```json
"review": {
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "codex_adversary": { "type": "string", "enum": ["auto", "off"], "default": "off" }
  }
}
```

- `off` (and **absent** `review` block) — never call Codex; today's exact behavior.
- `auto` — augment the adversary pass with Codex **when the bridge reports ready**; fall
  back silently otherwise.

`init` writes `review: { codex_adversary: "auto" }` for new projects (§5).

### 2. The Codex bridge (new, reusable)

Two new files under `agentic-dev/bin/`. This is the reusable investment Specs 2 and 3 build
on. It is the **only** place that knows how to reach Codex.

- `bin/codex-bridge.sh` — a bash entry point with three subcommands.
- `bin/codex_adapter.py` — stdlib-only Python; the schema translation (§3), unit-testable in
  isolation.

**`discover`** — locate the codex plugin without hardcoding a version. [Codex finding #3]
1. If env `AGENTIC_CODEX_COMPANION` is set to an absolute path to a `codex-companion.mjs`,
   use it (test/runtime override).
2. Else require `enabledPlugins["codex@openai-codex"] == true` in `~/.claude/settings.json`.
3. Enumerate `~/.claude/plugins/cache/openai-codex/codex/*/`; keep only dirs containing all
   of `scripts/codex-companion.mjs`, `schemas/review-output.schema.json`,
   `.claude-plugin/plugin.json`.
4. **Semantic** version sort of the survivors (parse `major.minor.patch` numerically so
   `1.10.0 > 1.9.0`; prereleases sort below stable). Pick the highest valid stable.
5. Emit structured JSON: `{ready, reason_code, detail, companion_path, schema_path}`.
   `reason_code ∈ {ok, plugin_disabled, no_valid_version, missing_files}`.

**`preflight`** — run `node <companion_path> setup --json`, parse `ready`, merge with the
`discover` result. Adds `reason_code ∈ {cli_missing, not_authenticated, setup_failed}`.

**`review <base_sha> <worktree_path> [focus...]`** — [Codex findings #1, #2, #6]
- Invoke **with `--json`**: `node <companion_path> adversarial-review --json --wait --base
  <base_sha> --scope branch [focus...]`, run with `cwd = <worktree_path>`.
- `--wait` is inert for reviews (the companion always runs `adversarial-review`
  synchronously via `runForegroundCommand`), so the **bridge enforces its own hard timeout**
  by killing the subprocess after a bound (default 300s). Timeout ⇒ soft-skip
  `reason_code: timeout`.
- Parse stdout as a **single JSON object**; read the **top-level `.result`** (the structured
  payload matching `review-output.schema.json`). Missing `.result` or present `.parseError`
  ⇒ soft-skip `reason_code: parse_error`.
- Validate `.result` against `schema_path` (from `discover`) before adapting. Invalid ⇒
  soft-skip `reason_code: schema_invalid`.
- `focus` is passed as separate argv elements — never shell-interpolated.

### 3. Adapter: `review-output` → `reviewer-verdict`

Maps Codex's output into the **existing** `agentic-dev/schemas/reviewer-verdict.schema.json`
(no change to that schema). [Codex finding #5]

| Codex `review-output` | agentic-dev `reviewer-verdict` |
| --- | --- |
| `verdict: approve` | `verdict: clean` |
| `verdict: needs-attention` | `blocking` if any finding is `critical` or `high`, else `concern` |
| finding `severity: critical` \| `high` | concern `severity: blocking` |
| finding `severity: medium` \| `low` | concern `severity: concern` |
| every finding `category` | `uncategorized` (honest — mechanical vs judgment is not inferable from Codex's schema) |
| finding `file`, `line_start` | `file`, `line` |
| `title` + `body` + `recommendation` + `confidence` | folded into `description`, prefixed `[codex-adversary] ` |

Output carries `reviewer_role: "adversary"`, `schema_version: "0.1"`, a fresh `reviewed_at`,
`goal_id` from the manifest, and one synthesized `checks_run` entry
(`name: "codex_adversarial_review"`).

### 4. P5 flow change (`_run-reviewer`, augment mode)

Only the `primary verdict == "clean"` → adversary branch changes.

1. Dispatch the Claude `reviewer-adversary` as today → `<goal>.adversary.json`. Prefix its
   concern descriptions `[claude-adversary] ` for provenance.
2. If `review.codex_adversary != "off"` **and** `bin/codex-bridge.sh preflight` is `ready`:
   run the §5 preconditions, then `bin/codex-bridge.sh review …` → write adapted
   `<goal>.codex.json` and raw `<goal>.codex.raw.json`.
3. **Merge with an explicit aggregate verdict** [Codex finding #4] — routing keys off the
   top-level verdict today, so compute it once before routing (do **not** route each array
   separately):

   ```
   aggregate =
     "blocking"  if claude_adv.verdict == "blocking"
                 or codex.verdict == "blocking"
                 or any merged concern.severity == "blocking"
     else "concern"  if merged concerns non-empty
                     or any source verdict == "concern"
     else "clean"
   ```

   `concerns[]` is the **union** of both sources (provenance preserved by the description
   prefixes; no silent dedup). Route the aggregate through the **existing** rules
   (clean → done; concern → auto-fix queue; blocking → escalate). Assert post-merge
   invariants: `clean` ⇒ 0 concerns; `concern` ⇒ ≥1 concern and no blocking-severity;
   `blocking` ⇒ ≥1 blocking reason.
4. **Failure isolation:** any soft-skip / timeout / parse_error / schema_invalid / not-ready
   ⇒ append to `.claude/agentic/validation-log.txt`, note `codex adversary: skipped
   (<reason_code>)` in the P5 summary, and proceed on the Claude adversary result alone.

### 5. P5 preconditions for the Codex call [Codex finding #6]

Before invoking `bin/codex-bridge.sh review`, from the manifest:

- Use `manifest.worktree_path` as the authoritative worktree (not an invented argument).
- Assert it is a git worktree; assert `git -C <worktree> rev-parse HEAD == manifest.head_ref`
  (the committed head the diff envelope captured); assert the base commit exists.
- Any assertion fails (dirty / detached / branch mismatch) ⇒ soft-skip Codex with that exact
  reason; the Claude adversary still covers the pass. Committed `base..head` is already a P5
  precondition since the diff envelope is captured post-gates.

### 6. Init onboarding (`skills/init/SKILL.md`)

- Run `bin/codex-bridge.sh preflight`. If not ready, print a targeted recommendation keyed on
  `reason_code` (install the codex plugin / run `/codex:setup` / `codex login`) and note the
  adversary is Claude-only until Codex is enabled.
- Write `review: { codex_adversary: "auto" }` regardless, so it activates automatically once
  Codex becomes available.
- Init **detects and recommends** — it cannot install another plugin for the user.

## Testing strategy

Deterministic, headless. No live Codex call in the suite (the bridge is stubbed / fixtures
drive the adapter).

- **Adapter** (`codex_adapter.py`) — pure function over fixtures: `approve`→clean;
  `needs-attention`+critical→blocking; `needs-attention`+high→blocking;
  `needs-attention`+medium→concern; empty findings; missing `.result`; schema-invalid
  `.result`.
- **Discover** — semantic sort (`1.10.0` beats `1.9.0`), prerelease excluded,
  missing-files dir skipped, `AGENTIC_CODEX_COMPANION` override honored, `plugin_disabled`
  path — against fixture directory trees.
- **Merge / aggregate verdict** — unit-test the aggregate function: blocking dominance,
  concern union, both-clean, provenance prefixes, invariant assertions.
- **Init** — headless: config gains `review.codex_adversary: auto`; recommendation prints
  when preflight (stubbed) is not-ready.
- **Backward compatibility** — a config without a `review` block validates; with
  `codex_adversary` `off`/absent, P5 attempts **no** Codex call and is byte-for-byte today's
  behavior.

## Files touched

- `agentic-dev/schemas/config.schema.json` — add optional `review` object.
- `agentic-dev/bin/codex-bridge.sh` — **new** (discover / preflight / review).
- `agentic-dev/bin/codex_adapter.py` — **new** (schema translation).
- `agentic-dev/skills/_run-reviewer/SKILL.md` — augment-mode adversary branch + aggregate
  verdict + preconditions + failure isolation.
- `agentic-dev/skills/init/SKILL.md` — preflight detection, recommendation, write
  `codex_adversary: auto`.
- Tests under `agentic-dev/tests/…` (adapter, discover, merge, init, backward-compat).
- `agentic-dev/CHANGELOG.md` + `agentic-dev/.claude-plugin/plugin.json` version bump
  (→ 1.7.0) at the end.
- `agentic-dev/schemas/reviewer-verdict.schema.json` — **unchanged** (Codex maps into it).
