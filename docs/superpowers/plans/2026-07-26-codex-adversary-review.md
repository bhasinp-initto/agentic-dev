# Codex-backed Adversary Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Codex as an optional, independent-model adversary at the P5 review gate, running alongside the Claude `reviewer-adversary` and unioned into the existing routing, with silent fallback whenever Codex is unavailable.

**Architecture:** A reusable "Codex bridge" (`bin/codex-bridge.sh` + two stdlib-only Python helpers) is the only code that reaches the codex plugin. The P5 skill (`_run-reviewer`) calls the bridge in its clean→adversary branch, translates Codex's output into the existing `reviewer-verdict` schema, computes an explicit aggregate verdict across both adversaries, and routes once. Everything degrades to Claude-only when Codex is absent/disabled/unhealthy.

**Tech Stack:** Bash, Python 3 stdlib (`json`, `pathlib`, no third-party imports in shipped code), Node (only invoked, never imported), the `codex@openai-codex` plugin's `codex-companion.mjs`. Tests use `jsonschema` (already in `tests/requirements.txt`).

Design spec: `docs/superpowers/specs/2026-07-22-codex-adversary-review-design.md`.

## Global Constraints

Copied verbatim from the spec. Every task's requirements implicitly include these.

- **Config field:** `review.codex_adversary` — enum `["auto","off"]`, default `"off"`. The `review` object is **optional** (NOT added to config schema's top-level `required`). **Absent `review` block ⇒ treated as `off`.** `init` writes `"auto"` for new projects only.
- **Adapter — per-finding severity:** `critical`→`"blocking"`, `high`→`"blocking"`, `medium`→`"concern"`, `low`→`"concern"`.
- **Adapter — per-finding category:** always `"uncategorized"`.
- **Adapter — Codex verdict:** `approve`→`"clean"` (concerns empty); `needs-attention`→`"blocking"` if any finding is `critical` or `high`, else `"concern"`.
- **Adapter — field mapping:** `file`→`file`, `line_start`→`line`; description = `"[codex-adversary] " + title + " — " + body + " | fix: " + recommendation + " (confidence " + confidence + ")"`.
- **Claude adversary concerns** get their description prefixed `"[claude-adversary] "` (done in `merge`).
- **Aggregate verdict (route once on this):**
  `"blocking"` if `claude.verdict=="blocking"` OR `codex.verdict=="blocking"` OR any merged concern `severity=="blocking"`; else `"concern"` if merged concerns non-empty OR any source verdict `=="concern"`; else `"clean"`. Invariants: clean⇒0 concerns; concern⇒≥1 concern & no blocking severity; blocking⇒≥1 blocking reason.
- **Bridge review invocation:** `node <companion> adversarial-review --json --wait --base <base_sha> --scope branch [focus...]`, run with `cwd=<worktree_path>`, `focus` as separate argv (never shell-interpolated). Read the **top-level `.result`** of stdout JSON. `--wait` is inert → the bridge enforces its **own** hard timeout (default `300`s) by killing the subprocess.
- **Discovery:** honor env `AGENTIC_CODEX_COMPANION`; else require `enabledPlugins["codex@openai-codex"]==true`; enumerate version dirs, keep only those containing `scripts/codex-companion.mjs` + `schemas/review-output.schema.json` + `.claude-plugin/plugin.json`; **semantic** version sort (so `1.10.0 > 1.9.0`, prereleases below stable); emit `{ready, reason_code, detail, companion_path, schema_path}`.
- **Failure isolation:** any Codex unavailability (not-installed / disabled / cli_missing / not_authenticated / setup_failed / not_a_worktree / head_mismatch / base_missing / timeout / parse_error / schema_invalid) ⇒ append to `.claude/agentic/validation-log.txt`, note `codex adversary: skipped (<reason_code>)` in the P5 summary, proceed on the Claude adversary alone. **Codex failure never blocks.**
- **No change** to `agentic-dev/schemas/reviewer-verdict.schema.json`. Python in shipped `bin/` is **stdlib-only**.
- **Test-injection envs** (read by discovery, honored so tests need no real plugin): `AGENTIC_CODEX_COMPANION`, `AGENTIC_CODEX_SETTINGS` (default `~/.claude/settings.json`), `AGENTIC_CODEX_CACHE_ROOT` (default `~/.claude/plugins/cache/openai-codex/codex`).

---

## File Structure

**New:**
- `agentic-dev/bin/codex_adapter.py` — pure schema translation: `adapt()` + `merge()` (+ CLI). Stdlib only.
- `agentic-dev/bin/codex_discovery.py` — plugin discovery + semantic version selection (+ CLI). Stdlib only.
- `agentic-dev/bin/codex-bridge.sh` — orchestrator: `discover` / `preflight` / `review`.
- `tests/phase-9/` — all tests + fixtures + `run_all.sh`.

**Modified:**
- `agentic-dev/schemas/config.schema.json` — optional `review` object.
- `agentic-dev/skills/_run-reviewer/SKILL.md` — augment-mode adversary branch.
- `agentic-dev/skills/init/SKILL.md` — preflight detection + recommendation + write `codex_adversary: auto`.
- `agentic-dev/.claude-plugin/plugin.json` + `agentic-dev/CHANGELOG.md` — version bump (final task).

**Unchanged:** `agentic-dev/schemas/reviewer-verdict.schema.json`.

---

## Task 1: Config schema — optional `review` block

**Files:**
- Modify: `agentic-dev/schemas/config.schema.json`
- Test: `tests/phase-9/config_review_schema_test.py`
- Fixtures: `tests/phase-9/fixtures/config-review-auto.yaml`, `tests/phase-9/fixtures/config-no-review.yaml`

**Interfaces:**
- Consumes: existing `config.schema.json`.
- Produces: config docs may now carry `review.codex_adversary ∈ {auto, off}`; absence is valid.

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/config_review_schema_test.py`:

```python
"""Config schema accepts optional review.codex_adversary; rejects bad values."""
import json
import sys
from pathlib import Path

import jsonschema
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = REPO_ROOT / "agentic-dev" / "schemas" / "config.schema.json"


def base_config():
    return {
        "schema_version": "0.1",
        "project": {"name": "demo", "primary_language": "python"},
        "commands": {"test": "pytest", "lint": "ruff check ."},
        "budgets": {
            "wall_clock_minutes_per_goal": 30,
            "diff_lines_per_goal": 400,
            "files_touched_per_goal": 20,
        },
        "sensitive_paths": [],
        "push_policy": "hold",
    }


def check(name, cfg, should_pass):
    schema = json.loads(SCHEMA.read_text())
    try:
        jsonschema.validate(cfg, schema)
        ok = True
    except jsonschema.ValidationError:
        ok = False
    passed = ok == should_pass
    print(f"{'PASS' if passed else 'FAIL'} {name}")
    return passed


def main():
    results = []

    cfg = base_config()  # no review block at all
    results.append(check("no-review-block-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "auto"}
    results.append(check("review-auto-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "off"}
    results.append(check("review-off-valid", cfg, True))

    cfg = base_config()
    cfg["review"] = {"codex_adversary": "sometimes"}
    results.append(check("review-bad-enum-rejected", cfg, False))

    cfg = base_config()
    cfg["review"] = {"unknown_key": True}
    results.append(check("review-unknown-key-rejected", cfg, False))

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/config_review_schema_test.py`
Expected: FAIL — `review-bad-enum-rejected` and `review-unknown-key-rejected` FAIL (schema currently ignores unknown `review` at top level? No — top-level `additionalProperties:false` rejects `review` entirely, so `review-auto-valid` FAILs). Net: non-zero exit.

- [ ] **Step 3: Add the `review` block to the schema**

In `agentic-dev/schemas/config.schema.json`, add this property inside `properties` (e.g. after the `"telegram"` block, before `"push_policy"`). Do NOT add `"review"` to the top-level `required` array:

```json
    "review": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "codex_adversary": {
          "type": "string",
          "enum": ["auto", "off"],
          "default": "off",
          "description": "auto = augment the adversary pass with Codex when the bridge reports ready; off (and absent) = never call Codex."
        }
      }
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/config_review_schema_test.py`
Expected: all 5 lines `PASS`, exit 0.

- [ ] **Step 5: Create the two YAML fixtures** (used by later init test)

`tests/phase-9/fixtures/config-review-auto.yaml`:

```yaml
schema_version: "0.1"
project:
  name: demo
  primary_language: python
commands:
  test: pytest
  lint: ruff check .
budgets:
  wall_clock_minutes_per_goal: 30
  diff_lines_per_goal: 400
  files_touched_per_goal: 20
sensitive_paths: []
push_policy: hold
review:
  codex_adversary: auto
```

`tests/phase-9/fixtures/config-no-review.yaml`: same as above but delete the trailing `review:` block.

- [ ] **Step 6: Commit**

```bash
git add agentic-dev/schemas/config.schema.json tests/phase-9/config_review_schema_test.py tests/phase-9/fixtures/config-review-auto.yaml tests/phase-9/fixtures/config-no-review.yaml
git commit -m "feat(config): optional review.codex_adversary field (default off)"
```

---

## Task 2: Adapter `adapt()` — Codex review-output → reviewer-verdict

**Files:**
- Create: `agentic-dev/bin/codex_adapter.py`
- Test: `tests/phase-9/codex_adapter_test.py`

**Interfaces:**
- Consumes: a Codex `review-output` dict (keys: `verdict`, `summary`, `findings[]`, `next_steps[]`; each finding: `severity`, `title`, `body`, `file`, `line_start`, `line_end`, `confidence`, `recommendation`).
- Produces:
  - `adapt(review_output: dict, goal_id: str, reviewed_at: str) -> dict` — a dict valid against `reviewer-verdict.schema.json`, `reviewer_role="adversary"`.
  - CLI: `python3 codex_adapter.py adapt <review-output.json> --goal-id <id> --reviewed-at <iso>` prints that dict as JSON.

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/codex_adapter_test.py`:

```python
"""Unit tests for codex_adapter.adapt() — severity/verdict/field mapping."""
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import codex_adapter as ca  # noqa: E402

import jsonschema  # noqa: E402

VERDICT_SCHEMA = json.loads(
    (REPO_ROOT / "agentic-dev" / "schemas" / "reviewer-verdict.schema.json").read_text()
)

GID = "2026-07-26-demo-goal"
TS = "2026-07-26T12:00:00Z"


def finding(sev, **kw):
    base = dict(severity=sev, title="T", body="B", file="src/a.py",
               line_start=10, line_end=12, confidence=0.8, recommendation="do X")
    base.update(kw)
    return base


def results():
    out = []

    # approve => clean, empty concerns
    v = ca.adapt({"verdict": "approve", "summary": "ok", "findings": [], "next_steps": []}, GID, TS)
    out.append(("approve->clean", v["verdict"] == "clean" and v["concerns"] == []))

    # needs-attention + critical => blocking
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("critical")], "next_steps": []}, GID, TS)
    out.append(("critical->blocking-verdict", v["verdict"] == "blocking"))
    out.append(("critical->blocking-severity", v["concerns"][0]["severity"] == "blocking"))

    # high => blocking
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("high")], "next_steps": []}, GID, TS)
    out.append(("high->blocking", v["verdict"] == "blocking"))

    # medium => concern
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("medium")], "next_steps": []}, GID, TS)
    out.append(("medium->concern-verdict", v["verdict"] == "concern"))
    out.append(("medium->concern-severity", v["concerns"][0]["severity"] == "concern"))

    # low => concern
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("low")], "next_steps": []}, GID, TS)
    out.append(("low->concern", v["concerns"][0]["severity"] == "concern"))

    # field mapping + prefix + category
    v = ca.adapt({"verdict": "needs-attention", "summary": "x",
                  "findings": [finding("high", file="src/z.py", line_start=42,
                                       title="Race", body="TOCTOU", recommendation="lock")],
                  "next_steps": []}, GID, TS)
    c = v["concerns"][0]
    out.append(("map-file", c["file"] == "src/z.py"))
    out.append(("map-line", c["line"] == 42))
    out.append(("category-uncategorized", c["category"] == "uncategorized"))
    out.append(("desc-prefix", c["description"].startswith("[codex-adversary] Race")))
    out.append(("desc-has-fix", "fix: lock" in c["description"]))

    # role + schema validity
    out.append(("role-adversary", v["reviewer_role"] == "adversary"))
    try:
        jsonschema.validate(v, VERDICT_SCHEMA, format_checker=jsonschema.FormatChecker())
        out.append(("schema-valid", True))
    except jsonschema.ValidationError as e:
        out.append((f"schema-valid ({e.message})", False))

    return out


def main():
    ok = True
    for name, passed in results():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/codex_adapter_test.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'codex_adapter'`.

- [ ] **Step 3: Write `codex_adapter.py` with `adapt()` + CLI skeleton**

Create `agentic-dev/bin/codex_adapter.py`:

```python
#!/usr/bin/env python3
"""Pure translation between Codex review-output and agentic-dev reviewer-verdict.

Stdlib only. Two entry points: adapt() and merge() (merge added in Task 3).
"""
import argparse
import json
import sys

SCHEMA_VERSION = "0.1"

_SEVERITY = {"critical": "blocking", "high": "blocking",
             "medium": "concern", "low": "concern"}


def _concern_from_finding(f):
    conf = f.get("confidence")
    desc = (
        f"[codex-adversary] {f.get('title', '')} — {f.get('body', '')}"
        f" | fix: {f.get('recommendation', '')} (confidence {conf})"
    )
    return {
        "file": f.get("file", "_unknown"),
        "line": int(f.get("line_start", 0) or 0),
        "severity": _SEVERITY.get(f.get("severity", "low"), "concern"),
        "category": "uncategorized",
        "description": desc,
    }


def adapt(review_output, goal_id, reviewed_at):
    """Codex review-output dict -> reviewer-verdict dict (reviewer_role=adversary)."""
    codex_verdict = review_output.get("verdict")
    findings = review_output.get("findings") or []

    if codex_verdict == "approve" or not findings:
        verdict = "clean"
        concerns = []
    else:
        concerns = [_concern_from_finding(f) for f in findings]
        verdict = "blocking" if any(c["severity"] == "blocking" for c in concerns) else "concern"

    return {
        "schema_version": SCHEMA_VERSION,
        "goal_id": goal_id,
        "reviewer_role": "adversary",
        "reviewed_at": reviewed_at,
        "verdict": verdict,
        "concerns": concerns,
        "checks_run": [{
            "name": "codex_adversarial_review",
            "outcome": "pass" if verdict == "clean" else "fail",
            "evidence": (review_output.get("summary") or "")[:500],
        }],
    }


def _cmd_adapt(args):
    review_output = json.loads(open(args.review_output).read())
    print(json.dumps(adapt(review_output, args.goal_id, args.reviewed_at)))


def main(argv=None):
    p = argparse.ArgumentParser(prog="codex_adapter")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("adapt")
    a.add_argument("review_output")
    a.add_argument("--goal-id", required=True)
    a.add_argument("--reviewed-at", required=True)
    a.set_defaults(func=_cmd_adapt)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/codex_adapter_test.py`
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/codex_adapter.py tests/phase-9/codex_adapter_test.py
git commit -m "feat(codex): adapt() maps Codex review-output to reviewer-verdict"
```

---

## Task 3: Adapter `merge()` — aggregate verdict + provenance

**Files:**
- Modify: `agentic-dev/bin/codex_adapter.py`
- Test: `tests/phase-9/codex_merge_test.py`

**Interfaces:**
- Consumes: two reviewer-verdict dicts (`claude` = Claude adversary output; `codex` = `adapt()` output).
- Produces:
  - `merge(claude: dict, codex: dict) -> dict` returning `{"verdict": <aggregate>, "concerns": [...]}`. Claude concerns get `"[claude-adversary] "` prepended to their description if not already prefixed. Raises `ValueError` if a post-merge invariant is violated.
  - CLI: `python3 codex_adapter.py merge <claude.json> <codex.json>` prints that dict.

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/codex_merge_test.py`:

```python
"""Unit tests for codex_adapter.merge() — aggregate verdict + provenance."""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import codex_adapter as ca  # noqa: E402


def rv(verdict, concerns):
    return {"schema_version": "0.1", "goal_id": "g", "reviewer_role": "adversary",
            "reviewed_at": "2026-07-26T00:00:00Z", "verdict": verdict,
            "concerns": concerns, "checks_run": []}


def concern(sev, desc="issue"):
    return {"file": "a.py", "line": 1, "severity": sev,
            "category": "uncategorized", "description": desc}


def main():
    out = []

    # both clean -> clean, no concerns
    m = ca.merge(rv("clean", []), rv("clean", []))
    out.append(("both-clean", m["verdict"] == "clean" and m["concerns"] == []))

    # codex blocking dominates even if claude clean
    m = ca.merge(rv("clean", []), rv("blocking", [concern("blocking")]))
    out.append(("codex-blocking-dominates", m["verdict"] == "blocking"))

    # claude concern + codex clean -> concern, union size 1
    m = ca.merge(rv("concern", [concern("concern", "c1")]), rv("clean", []))
    out.append(("claude-concern", m["verdict"] == "concern" and len(m["concerns"]) == 1))

    # union of concerns from both
    m = ca.merge(rv("concern", [concern("concern", "c1")]),
                 rv("concern", [concern("concern", "[codex-adversary] c2")]))
    out.append(("union", len(m["concerns"]) == 2))

    # claude provenance prefix applied
    descs = [c["description"] for c in m["concerns"]]
    out.append(("claude-prefixed", any(d.startswith("[claude-adversary] c1") for d in descs)))
    out.append(("codex-prefix-preserved", any(d == "[codex-adversary] c2" for d in descs)))

    # invariant: blocking severity forces blocking verdict even if source verdicts say concern
    m = ca.merge(rv("concern", [concern("blocking")]), rv("clean", []))
    out.append(("blocking-severity-forces-blocking", m["verdict"] == "blocking"))

    ok = True
    for name, passed in out:
        print(f"{'PASS' if passed else 'FAIL'} {name}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/codex_merge_test.py`
Expected: FAIL — `AttributeError: module 'codex_adapter' has no attribute 'merge'`.

- [ ] **Step 3: Add `merge()` and its CLI wiring to `codex_adapter.py`**

Add to `agentic-dev/bin/codex_adapter.py` (function near `adapt`, CLI parser in `main`):

```python
_CLAUDE_PREFIX = "[claude-adversary] "


def _prefix_claude(concerns):
    out = []
    for c in concerns:
        d = c.get("description", "")
        if not d.startswith(_CLAUDE_PREFIX) and not d.startswith("[codex-adversary] "):
            c = {**c, "description": _CLAUDE_PREFIX + d}
        out.append(c)
    return out


def merge(claude, codex):
    """Aggregate a Claude-adversary verdict and a Codex verdict into one."""
    claude_concerns = _prefix_claude(claude.get("concerns") or [])
    codex_concerns = list(codex.get("concerns") or [])
    concerns = claude_concerns + codex_concerns

    any_blocking = (
        claude.get("verdict") == "blocking"
        or codex.get("verdict") == "blocking"
        or any(c.get("severity") == "blocking" for c in concerns)
    )
    if any_blocking:
        verdict = "blocking"
    elif concerns or claude.get("verdict") == "concern" or codex.get("verdict") == "concern":
        verdict = "concern"
    else:
        verdict = "clean"

    # Post-merge invariants.
    if verdict == "clean" and concerns:
        raise ValueError("clean verdict with non-empty concerns")
    if verdict == "concern" and any(c.get("severity") == "blocking" for c in concerns):
        raise ValueError("concern verdict with a blocking-severity concern")
    if verdict == "blocking" and not any_blocking:
        raise ValueError("blocking verdict with no blocking reason")

    return {"verdict": verdict, "concerns": concerns}


def _cmd_merge(args):
    claude = json.loads(open(args.claude).read())
    codex = json.loads(open(args.codex).read())
    print(json.dumps(merge(claude, codex)))
```

And register the subcommand inside `main()` (after the `adapt` parser):

```python
    m = sub.add_parser("merge")
    m.add_argument("claude")
    m.add_argument("codex")
    m.set_defaults(func=_cmd_merge)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/codex_merge_test.py`
Expected: every line `PASS`, exit 0. Also re-run Task 2's test to confirm no regression: `python3 tests/phase-9/codex_adapter_test.py` → all PASS.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/codex_adapter.py tests/phase-9/codex_merge_test.py
git commit -m "feat(codex): merge() computes aggregate verdict with provenance"
```

---

## Task 4: Discovery — `codex_discovery.py`

**Files:**
- Create: `agentic-dev/bin/codex_discovery.py`
- Test: `tests/phase-9/codex_discovery_test.py`

**Interfaces:**
- Consumes: env `AGENTIC_CODEX_COMPANION`, `AGENTIC_CODEX_SETTINGS`, `AGENTIC_CODEX_CACHE_ROOT`; filesystem.
- Produces:
  - `discover(env: dict) -> dict` returning `{ready, reason_code, detail, companion_path, schema_path}`. `reason_code ∈ {ok, plugin_disabled, no_valid_version, missing_files}`.
  - CLI: `python3 codex_discovery.py` prints that dict (reads real `os.environ`).

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/codex_discovery_test.py`:

```python
"""Unit tests for codex_discovery.discover() using fixture cache trees."""
import json
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import codex_discovery as cd  # noqa: E402


def make_version(cache_root, version, complete=True):
    d = cache_root / version
    (d / "scripts").mkdir(parents=True, exist_ok=True)
    (d / "schemas").mkdir(parents=True, exist_ok=True)
    (d / ".claude-plugin").mkdir(parents=True, exist_ok=True)
    (d / "scripts" / "codex-companion.mjs").write_text("// stub")
    (d / ".claude-plugin" / "plugin.json").write_text("{}")
    if complete:
        (d / "schemas" / "review-output.schema.json").write_text("{}")
    return d


def settings_file(tmp, enabled=True):
    p = tmp / "settings.json"
    p.write_text(json.dumps({"enabledPlugins": {"codex@openai-codex": enabled}}))
    return p


def env(cache_root, settings, companion=None):
    e = {"AGENTIC_CODEX_CACHE_ROOT": str(cache_root), "AGENTIC_CODEX_SETTINGS": str(settings)}
    if companion:
        e["AGENTIC_CODEX_COMPANION"] = str(companion)
    return e


def main():
    out = []
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        cache = tmp / "cache"
        cache.mkdir()
        make_version(cache, "1.9.0")
        make_version(cache, "1.10.0")            # must win over 1.9.0 (semantic, not lexical)
        make_version(cache, "1.11.0-beta")       # prerelease, must be skipped for stable pick
        st = settings_file(tmp, enabled=True)

        r = cd.discover(env(cache, st))
        out.append(("ready", r["ready"] is True))
        out.append(("picks-1.10.0-not-1.9.0", r["companion_path"].endswith("1.10.0/scripts/codex-companion.mjs")))
        out.append(("schema-path-set", r["schema_path"].endswith("1.10.0/schemas/review-output.schema.json")))

        # plugin disabled
        st_off = settings_file(tmp, enabled=False)
        r = cd.discover(env(cache, st_off))
        out.append(("plugin-disabled", r["ready"] is False and r["reason_code"] == "plugin_disabled"))

        # incomplete-only version dir -> missing_files
        cache2 = tmp / "cache2"
        cache2.mkdir()
        make_version(cache2, "2.0.0", complete=False)
        r = cd.discover(env(cache2, st))
        out.append(("missing-files", r["ready"] is False and r["reason_code"] == "missing_files"))

        # empty cache -> no_valid_version
        cache3 = tmp / "cache3"
        cache3.mkdir()
        r = cd.discover(env(cache3, st))
        out.append(("no-valid-version", r["ready"] is False and r["reason_code"] == "no_valid_version"))

        # env override wins regardless of settings/cache
        comp = make_version(tmp / "override", "9.9.9") / "scripts" / "codex-companion.mjs"
        r = cd.discover(env(cache3, st_off, companion=comp))
        out.append(("env-override", r["ready"] is True and r["companion_path"] == str(comp)))

    ok = True
    for name, passed in out:
        print(f"{'PASS' if passed else 'FAIL'} {name}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/codex_discovery_test.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'codex_discovery'`.

- [ ] **Step 3: Write `codex_discovery.py`**

Create `agentic-dev/bin/codex_discovery.py`:

```python
#!/usr/bin/env python3
"""Locate the codex plugin companion without hardcoding a version. Stdlib only."""
import json
import os
from pathlib import Path


def _result(ready, reason_code, detail="", companion_path=None, schema_path=None):
    return {"ready": ready, "reason_code": reason_code, "detail": detail,
            "companion_path": companion_path, "schema_path": schema_path}


def _parse_version(name):
    """('1.10.0') -> (is_stable, (1,10,0)). Non-numeric parts sort low."""
    is_stable = "-" not in name
    core = name.split("-", 1)[0]
    parts = []
    for p in core.split("."):
        parts.append(int(p) if p.isdigit() else -1)
    return (is_stable, tuple(parts))


def _valid_dir(d):
    return (
        (d / "scripts" / "codex-companion.mjs").is_file()
        and (d / "schemas" / "review-output.schema.json").is_file()
        and (d / ".claude-plugin" / "plugin.json").is_file()
    )


def discover(env):
    # 1. Explicit override.
    override = env.get("AGENTIC_CODEX_COMPANION")
    if override:
        comp = Path(override)
        if comp.is_file():
            root = comp.parent.parent  # <root>/scripts/codex-companion.mjs
            schema = root / "schemas" / "review-output.schema.json"
            return _result(True, "ok", "override", str(comp),
                           str(schema) if schema.is_file() else None)
        return _result(False, "missing_files", f"override not found: {override}")

    # 2. Plugin enabled?
    settings_path = Path(env.get("AGENTIC_CODEX_SETTINGS",
                                 str(Path.home() / ".claude" / "settings.json")))
    enabled = False
    if settings_path.is_file():
        try:
            enabled = bool(json.loads(settings_path.read_text())
                           .get("enabledPlugins", {}).get("codex@openai-codex"))
        except (ValueError, OSError):
            enabled = False
    if not enabled:
        return _result(False, "plugin_disabled", "codex@openai-codex not enabled")

    # 3. Enumerate + validate version dirs.
    cache_root = Path(env.get("AGENTIC_CODEX_CACHE_ROOT",
                              str(Path.home() / ".claude" / "plugins" / "cache"
                                  / "openai-codex" / "codex")))
    if not cache_root.is_dir():
        return _result(False, "no_valid_version", f"cache root absent: {cache_root}")

    subdirs = [d for d in cache_root.iterdir() if d.is_dir()]
    valid = [d for d in subdirs if _valid_dir(d)]
    if not valid:
        code = "missing_files" if subdirs else "no_valid_version"
        return _result(False, code, f"no complete version under {cache_root}")

    # 4. Semantic sort: stable beats prerelease, then higher core version.
    valid.sort(key=lambda d: _parse_version(d.name), reverse=True)
    best = valid[0]
    return _result(True, "ok", best.name,
                   str(best / "scripts" / "codex-companion.mjs"),
                   str(best / "schemas" / "review-output.schema.json"))


if __name__ == "__main__":
    print(json.dumps(discover(dict(os.environ))))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/codex_discovery_test.py`
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/codex_discovery.py tests/phase-9/codex_discovery_test.py
git commit -m "feat(codex): plugin discovery with semantic version selection"
```

---

## Task 5: Bridge `discover` + `preflight`

**Files:**
- Create: `agentic-dev/bin/codex-bridge.sh`
- Test: `tests/phase-9/codex_bridge_preflight_test.sh`

**Interfaces:**
- Consumes: `codex_discovery.py`; the companion's `setup --json`.
- Produces:
  - `codex-bridge.sh discover` → prints `codex_discovery.py`'s JSON.
  - `codex-bridge.sh preflight` → prints `{ready, reason_code, detail, companion_path, schema_path}` merging discovery with the companion's `setup --json` health (`reason_code` may become `cli_missing`, `not_authenticated`, `setup_failed`).

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/codex_bridge_preflight_test.sh`:

```bash
#!/usr/bin/env bash
# Bridge discover/preflight against a fake companion .mjs (no real plugin needed).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$REPO_ROOT/agentic-dev/bin/codex-bridge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got: $2)"; fails=$((fails+1)); fi; }

# Build a fake plugin version dir with a companion that reports healthy setup.
V="$TMP/cache/1.0.0"
mkdir -p "$V/scripts" "$V/schemas" "$V/.claude-plugin"
printf '{}' > "$V/.claude-plugin/plugin.json"
printf '{}' > "$V/schemas/review-output.schema.json"
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready: true, auth: {available: true}, codex: {available: true}})); }
JS
printf '{"enabledPlugins":{"codex@openai-codex":true}}' > "$TMP/settings.json"

export AGENTIC_CODEX_CACHE_ROOT="$TMP/cache"
export AGENTIC_CODEX_SETTINGS="$TMP/settings.json"

# discover
D="$(bash "$BRIDGE" discover)"
check "discover-ready" "$(echo "$D" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')" "True"

# preflight healthy
P="$(bash "$BRIDGE" preflight)"
check "preflight-ready" "$(echo "$P" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')" "True"

# preflight when auth missing => not_authenticated
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready: false, auth: {available: false}, codex: {available: true}})); }
JS
P2="$(bash "$BRIDGE" preflight)"
check "preflight-not-authed" "$(echo "$P2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason_code"])')" "not_authenticated"

# preflight when plugin disabled => short-circuits, no node needed
printf '{"enabledPlugins":{"codex@openai-codex":false}}' > "$TMP/settings.json"
P3="$(bash "$BRIDGE" preflight)"
check "preflight-disabled" "$(echo "$P3" | python3 -c 'import json,sys;print(json.load(sys.stdin)["reason_code"])')" "plugin_disabled"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
```

Make it executable: `chmod +x tests/phase-9/codex_bridge_preflight_test.sh`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-9/codex_bridge_preflight_test.sh`
Expected: FAIL — bridge script does not exist yet (`No such file`).

- [ ] **Step 3: Write `codex-bridge.sh` with `discover` + `preflight`**

Create `agentic-dev/bin/codex-bridge.sh`:

```bash
#!/usr/bin/env bash
# Codex bridge: the only agentic-dev code that reaches the codex plugin.
# Subcommands: discover | preflight | review
# All failures are SOFT — callers fall back to Claude-only. Never exits non-zero
# for a Codex-unavailable condition; prints a JSON object describing it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECS="${AGENTIC_CODEX_TIMEOUT:-300}"

discover() { python3 "$SCRIPT_DIR/codex_discovery.py"; }

# Map the companion's setup --json to a reason_code. Args: <setup-json>
_setup_reason() {
  python3 - "$1" <<'PY'
import json, sys
try:
    s = json.loads(sys.argv[1])
except ValueError:
    print("setup_failed"); sys.exit()
if s.get("ready") is True:
    print("ok")
elif s.get("auth", {}).get("available") is False:
    print("not_authenticated")
elif s.get("codex", {}).get("available") is False:
    print("cli_missing")
else:
    print("setup_failed")
PY
}

preflight() {
  local disc; disc="$(discover)"
  local ready; ready="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')"
  if [ "$ready" != "True" ]; then echo "$disc"; return 0; fi

  local companion; companion="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["companion_path"])')"
  local setup_json reason
  setup_json="$(node "$companion" setup --json 2>/dev/null)" || setup_json='{}'
  reason="$(_setup_reason "$setup_json")"

  echo "$disc" | python3 -c '
import json, sys
disc = json.load(sys.stdin)
reason = sys.argv[1]
disc["ready"] = (reason == "ok")
disc["reason_code"] = reason
print(json.dumps(disc))
' "$reason"
}

case "${1:-}" in
  discover) discover ;;
  preflight) preflight ;;
  review) shift; review "$@" ;;   # defined in Task 6
  *) echo '{"ready":false,"reason_code":"bad_usage","detail":"discover|preflight|review"}'; exit 0 ;;
esac
```

> Note: the `review)` case references `review` added in Task 6. Until then, calling `review` errors harmlessly; the preflight test does not exercise it.

Make executable: `chmod +x agentic-dev/bin/codex-bridge.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/phase-9/codex_bridge_preflight_test.sh`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/codex-bridge.sh tests/phase-9/codex_bridge_preflight_test.sh
git commit -m "feat(codex): bridge discover + preflight subcommands"
```

---

## Task 6: Bridge `review` — preconditions, timeout, adapt

**Files:**
- Modify: `agentic-dev/bin/codex-bridge.sh`
- Test: `tests/phase-9/codex_bridge_review_test.sh`

**Interfaces:**
- Consumes: `codex_discovery.py`, `codex_adapter.py adapt`, a git worktree, the companion's `adversarial-review --json`.
- Produces:
  - `codex-bridge.sh review <goal_id> <base_sha> <worktree_path> <expected_head> [focus...]` → prints EITHER an adapted reviewer-verdict JSON (success) OR `{"skipped":true,"reason_code":...,"detail":...}` (any soft-skip). Always exit 0.
  - Soft-skip `reason_code ∈ {not_a_worktree, head_mismatch, base_missing, timeout, parse_error, schema_invalid}` plus any discovery/preflight reason.

- [ ] **Step 1: Write the failing test**

Create `tests/phase-9/codex_bridge_review_test.sh`:

```bash
#!/usr/bin/env bash
# review: success path + soft-skips, using a fake companion + a real temp git worktree.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$REPO_ROOT/agentic-dev/bin/codex-bridge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got: $2)"; fails=$((fails+1)); fi; }
field() { echo "$1" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$2'))"; }

# Fake plugin whose adversarial-review prints a canned payload with .result.
V="$TMP/cache/1.0.0"; mkdir -p "$V/scripts" "$V/schemas" "$V/.claude-plugin"
printf '{}' > "$V/.claude-plugin/plugin.json"
# Real review-output schema so schema validation passes:
cp "/Users/pankajbhasin/.claude/plugins/cache/openai-codex/codex/1.0.6/schemas/review-output.schema.json" "$V/schemas/review-output.schema.json" 2>/dev/null || printf '{"type":"object"}' > "$V/schemas/review-output.schema.json"
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "setup") { console.log(JSON.stringify({ready:true,auth:{available:true},codex:{available:true}})); process.exit(0); }
if (arg === "adversarial-review") {
  console.log(JSON.stringify({ result: {
    verdict: "needs-attention", summary: "risky",
    findings: [{severity:"high",title:"Race",body:"TOCTOU",file:"a.py",line_start:5,line_end:6,confidence:0.9,recommendation:"lock"}],
    next_steps: ["add lock"]
  }}));
  process.exit(0);
}
JS
printf '{"enabledPlugins":{"codex@openai-codex":true}}' > "$TMP/settings.json"
export AGENTIC_CODEX_CACHE_ROOT="$TMP/cache"
export AGENTIC_CODEX_SETTINGS="$TMP/settings.json"

# A real git worktree with a base commit and a head commit.
WT="$TMP/wt"; mkdir -p "$WT"; git -C "$WT" init -q
git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
BASE="$(git -C "$WT" rev-parse HEAD)"
git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m head
HEAD_SHA="$(git -C "$WT" rev-parse HEAD)"

# Success path
R="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "success-verdict" "$(field "$R" verdict)" "blocking"
check "success-role" "$(field "$R" reviewer_role)" "adversary"
check "success-not-skipped" "$(field "$R" skipped)" "None"

# head_mismatch
R2="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "deadbeef")"
check "head-mismatch" "$(field "$R2" reason_code)" "head_mismatch"

# base_missing
R3="$(bash "$BRIDGE" review 2026-07-26-demo "0000000000000000000000000000000000000000" "$WT" "$HEAD_SHA")"
check "base-missing" "$(field "$R3" reason_code)" "base_missing"

# not_a_worktree
R4="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$TMP/not-git" "$HEAD_SHA")"
check "not-a-worktree" "$(field "$R4" reason_code)" "not_a_worktree"

# timeout: companion sleeps beyond a 2s bridge timeout
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "adversarial-review") { setTimeout(()=>{}, 60000); }
JS
R5="$(AGENTIC_CODEX_TIMEOUT=2 bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "timeout" "$(field "$R5" reason_code)" "timeout"

# parse_error: companion prints junk
cat > "$V/scripts/codex-companion.mjs" <<'JS'
const arg = process.argv[2];
if (arg === "adversarial-review") { console.log("not json at all"); }
JS
R6="$(bash "$BRIDGE" review 2026-07-26-demo "$BASE" "$WT" "$HEAD_SHA")"
check "parse-error" "$(field "$R6" reason_code)" "parse_error"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
```

Make executable: `chmod +x tests/phase-9/codex_bridge_review_test.sh`.

> Note: the test copies the real `review-output.schema.json` if present, else falls back to a permissive `{"type":"object"}` so it runs anywhere.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/phase-9/codex_bridge_review_test.sh`
Expected: FAIL — `review` subcommand not implemented (bridge prints bad_usage / errors).

- [ ] **Step 3: Add `review()` to `codex-bridge.sh`**

Insert this function into `agentic-dev/bin/codex-bridge.sh` above the `case` block:

```bash
_skip() { printf '{"skipped":true,"reason_code":"%s","detail":"%s"}\n' "$1" "${2:-}"; exit 0; }

review() {
  local goal_id="${1:-}" base_sha="${2:-}" worktree="${3:-}" expected_head="${4:-}"
  shift 4 2>/dev/null || true
  # remaining args = focus text (safe as argv)

  # Discover/preflight first.
  local disc ready companion schema
  disc="$(preflight)"
  ready="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ready"])')"
  if [ "$ready" != "True" ]; then echo "$disc"; return 0; fi
  companion="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["companion_path"])')"
  schema="$(echo "$disc" | python3 -c 'import json,sys;print(json.load(sys.stdin)["schema_path"])')"

  # Preconditions on the worktree.
  git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 || _skip not_a_worktree "$worktree"
  local head_now; head_now="$(git -C "$worktree" rev-parse HEAD 2>/dev/null)"
  [ "$head_now" = "$expected_head" ] || _skip head_mismatch "HEAD=$head_now expected=$expected_head"
  git -C "$worktree" cat-file -e "${base_sha}^{commit}" 2>/dev/null || _skip base_missing "$base_sha"

  # Run the companion with a bridge-enforced timeout (--wait is inert).
  local out="$(mktemp)" err="$(mktemp)"
  ( cd "$worktree" && node "$companion" adversarial-review --json --wait \
      --base "$base_sha" --scope branch "$@" ) >"$out" 2>"$err" &
  local pid=$! elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$TIMEOUT_SECS" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      rm -f "$out" "$err"; _skip timeout "${TIMEOUT_SECS}s"
    fi
    sleep 1; elapsed=$((elapsed+1))
  done
  wait "$pid" 2>/dev/null

  # Extract top-level .result.
  local result="$(mktemp)"
  if ! python3 -c '
import json, sys
raw = open(sys.argv[1]).read()
obj = json.loads(raw)               # raises on junk -> parse_error
res = obj.get("result")
if res is None: raise SystemExit(3)
open(sys.argv[2], "w").write(json.dumps(res))
' "$out" "$result" 2>/dev/null; then
    rm -f "$out" "$err" "$result"; _skip parse_error "no .result / bad json"
  fi

  # Validate .result against the selected companion's schema (best-effort; jsonschema
  # is a test dep, not guaranteed in prod — skip validation if unavailable).
  if python3 -c 'import jsonschema' 2>/dev/null && [ -f "$schema" ]; then
    python3 -c '
import json, sys, jsonschema
jsonschema.validate(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))
' "$result" "$schema" 2>/dev/null || { rm -f "$out" "$err" "$result"; _skip schema_invalid ""; }
  fi

  # Adapt to reviewer-verdict.
  local reviewed_at; reviewed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 "$SCRIPT_DIR/codex_adapter.py" adapt "$result" \
    --goal-id "$goal_id" --reviewed-at "$reviewed_at"
  rm -f "$out" "$err" "$result"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/phase-9/codex_bridge_review_test.sh`
Expected: `ALL PASS`, exit 0. Re-run Task 5's test to confirm no regression: `bash tests/phase-9/codex_bridge_preflight_test.sh` → `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/bin/codex-bridge.sh tests/phase-9/codex_bridge_review_test.sh
git commit -m "feat(codex): bridge review with preconditions, timeout, adapt"
```

---

## Task 7: Wire P5 `_run-reviewer` to augment with Codex

**Files:**
- Modify: `agentic-dev/skills/_run-reviewer/SKILL.md`
- Test: `tests/phase-9/run_reviewer_codex_structure_test.py`

**Interfaces:**
- Consumes: `bin/codex-bridge.sh` (preflight, review), `bin/codex_adapter.py merge`, `config.yaml` `review.codex_adversary`, the manifest's `worktree_path`/`head_ref`, the diff envelope's base ref.
- Produces: updated adversary branch behavior; new artifacts `<goal>.codex.json` + `<goal>.codex.raw.json`; aggregate-verdict routing.

This task edits an LLM-run skill (Markdown prose). It is verified by a structure test asserting the required instructions are present, mirroring `tests/phase-5/run_reviewer_skill_structure_test.py`.

- [ ] **Step 1: Write the failing structure test**

Create `tests/phase-9/run_reviewer_codex_structure_test.py`:

```python
"""Assert _run-reviewer SKILL.md contains the Codex-augment adversary instructions."""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "_run-reviewer" / "SKILL.md"


REQUIRED = [
    # Reads the config toggle and honors off/absent.
    "review.codex_adversary",
    "off",
    # Calls the bridge preflight and review.
    "codex-bridge.sh preflight",
    "codex-bridge.sh review",
    # Uses the manifest worktree + head for preconditions.
    "worktree_path",
    "head_ref",
    # Merges via the adapter and routes once on the aggregate.
    "codex_adapter.py merge",
    "aggregate",
    # Provenance + artifacts.
    "[claude-adversary]",
    ".codex.json",
    ".codex.raw.json",
    # Failure isolation.
    "validation-log.txt",
    "codex adversary: skipped",
    "never blocks",
]


def main():
    text = SKILL.read_text()
    ok = True
    for token in REQUIRED:
        present = token in text
        print(f"{'PASS' if present else 'FAIL'} contains: {token!r}")
        ok = ok and present
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/run_reviewer_codex_structure_test.py`
Expected: FAIL — the tokens are not in `SKILL.md` yet.

- [ ] **Step 3: Edit `_run-reviewer/SKILL.md`**

Replace the section `### \`verdict: "clean"\` → dispatch reviewer-adversary` so that, AFTER capturing and validating the Claude adversary verdict (written to `<goal>.adversary.json`) and BEFORE the "If the adversary verdict is also clean" decision, it inserts the Codex-augment block below. Keep all existing Claude-adversary dispatch text intact; add:

````markdown
#### Augment with Codex (2.0.0+)

After the Claude adversary verdict is captured, optionally augment it with a
second, independent-model adversary (Codex). This is **pure upside** — any
failure falls back to the Claude adversary result and **never blocks**.

1. **Read the toggle.** From `.claude/agentic/config.yaml`, read
   `review.codex_adversary`. If the `review` block is **absent** or the value is
   `off`, skip this entire subsection and proceed with the Claude adversary
   verdict unchanged (today's behavior).

2. **Preflight.** Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex-bridge.sh preflight
   ```
   Parse the JSON. If `ready` is not `true`, log
   `codex adversary: skipped (<reason_code>)` to
   `.claude/agentic/validation-log.txt`, note it in the final summary, and
   proceed with the Claude adversary verdict unchanged.

3. **Gather preconditions** from the manifest (`.claude/agentic/manifests/<goal-id>.json`)
   and diff envelope (`.claude/agentic/diffs/<goal-id>.json`):
   - `worktree_path` — the manifest's `worktree_path` (authoritative worktree).
   - `expected_head` — the manifest's `head_ref`.
   - `base_sha` — the diff envelope's base ref.

4. **Run the Codex adversary:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex-bridge.sh review \
     "<goal-id>" "<base_sha>" "<worktree_path>" "<expected_head>"
   ```
   The bridge always exits 0 and prints EITHER an adapted reviewer-verdict OR a
   `{"skipped":true,"reason_code":...}` object. If `skipped` is present: log
   `codex adversary: skipped (<reason_code>)` to `validation-log.txt`, note it in
   the summary, and proceed with the Claude adversary verdict unchanged.
   Otherwise write the adapted verdict to
   `.claude/agentic/reviewer-verdicts/<goal-id>.codex.json` and the raw companion
   `.result` (if you captured it) to `<goal-id>.codex.raw.json`.

5. **Merge into one aggregate verdict** (route ONCE on the aggregate — do not
   route each source separately):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex_adapter.py merge \
     ".claude/agentic/reviewer-verdicts/<goal-id>.adversary.json" \
     ".claude/agentic/reviewer-verdicts/<goal-id>.codex.json"
   ```
   This prints `{"verdict": <aggregate>, "concerns": [...]}`. The `merge` helper
   prefixes Claude concerns with `[claude-adversary]` and preserves the
   `[codex-adversary]` prefixes for provenance. Use the returned `verdict` as the
   effective adversary verdict and the returned `concerns` as the concern set:
   - aggregate `clean` → treat as the both-clean case (primary + Claude + Codex).
   - aggregate `concern` → route the concerns to the auto-fix queue (existing rules).
   - aggregate `blocking` → immediate escalation (existing rules).

Codex failure **never blocks** the pipeline: on any skip/error the Claude
adversary verdict stands and routing proceeds exactly as it does without Codex.
````

Also update the final summary block in the skill to add a line:
```
  codex adversary:   <ran (verdict) | skipped (reason_code) | disabled>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/run_reviewer_codex_structure_test.py`
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/skills/_run-reviewer/SKILL.md tests/phase-9/run_reviewer_codex_structure_test.py
git commit -m "feat(reviewer): augment clean-verdict adversary pass with Codex"
```

---

## Task 8: Init onboarding for Codex

**Files:**
- Modify: `agentic-dev/skills/init/SKILL.md`
- Test: `tests/phase-9/init_codex_structure_test.py`

**Interfaces:**
- Consumes: `bin/codex-bridge.sh preflight`.
- Produces: init writes `review: { codex_adversary: auto }` to `config.yaml` for new projects; prints a reason-coded recommendation when Codex is not ready.

Verified by a structure test (init is an LLM-run skill), mirroring the pattern used for other skill-md changes.

- [ ] **Step 1: Write the failing structure test**

Create `tests/phase-9/init_codex_structure_test.py`:

```python
"""Assert init SKILL.md wires Codex preflight + writes review.codex_adversary: auto."""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL = REPO_ROOT / "agentic-dev" / "skills" / "init" / "SKILL.md"

REQUIRED = [
    "codex-bridge.sh preflight",
    "codex_adversary: auto",
    "reason_code",
    "/codex:setup",
    "Claude-only",
]


def main():
    text = SKILL.read_text()
    ok = True
    for token in REQUIRED:
        present = token in text
        print(f"{'PASS' if present else 'FAIL'} contains: {token!r}")
        ok = ok and present
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/phase-9/init_codex_structure_test.py`
Expected: FAIL — tokens absent.

- [ ] **Step 3: Edit `init/SKILL.md`**

In the config-writing section of `init/SKILL.md`, (a) always include a `review` block in the generated `config.yaml`, and (b) add a Codex-detection step. Add this subsection where the skill assembles config and prints next steps:

````markdown
## Codex adversary onboarding

agentic-dev can use Codex (the `codex@openai-codex` plugin) as a second,
independent-model adversary during review. It is optional and degrades to
Claude-only when Codex is absent.

1. Detect Codex readiness:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/codex-bridge.sh preflight
   ```
2. Always write this into the generated `config.yaml` (new projects opt in):
   ```yaml
   review:
     codex_adversary: auto
   ```
3. If preflight `ready` is not `true`, print a recommendation keyed on
   `reason_code` and note the adversary runs **Claude-only** until Codex is enabled:
   - `plugin_disabled` / `no_valid_version` / `missing_files` → "Install the Codex
     plugin (openai-codex) to enable cross-model adversarial review."
   - `cli_missing` → "Run `/codex:setup` to install the Codex CLI."
   - `not_authenticated` → "Run `!codex login` to authenticate Codex."
   `init` only detects and recommends — it cannot install another plugin for you.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tests/phase-9/init_codex_structure_test.py`
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add agentic-dev/skills/init/SKILL.md tests/phase-9/init_codex_structure_test.py
git commit -m "feat(init): detect Codex, recommend setup, write codex_adversary: auto"
```

---

## Task 9: Phase-9 runner, version bump, full-suite verification

**Files:**
- Create: `tests/phase-9/run_all.sh`
- Modify: `agentic-dev/.claude-plugin/plugin.json`, `agentic-dev/CHANGELOG.md`

**Interfaces:**
- Consumes: all phase-9 tests.
- Produces: a single runner; a released version (1.7.0).

- [ ] **Step 1: Write `tests/phase-9/run_all.sh`**

Create `tests/phase-9/run_all.sh` (mirrors other phases' runners):

```bash
#!/usr/bin/env bash
# Run all phase-9 (Codex adversary) tests. Exit non-zero if any fail.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
fails=0

for t in \
  "python3 $DIR/config_review_schema_test.py" \
  "python3 $DIR/codex_adapter_test.py" \
  "python3 $DIR/codex_merge_test.py" \
  "python3 $DIR/codex_discovery_test.py" \
  "bash $DIR/codex_bridge_preflight_test.sh" \
  "bash $DIR/codex_bridge_review_test.sh" \
  "python3 $DIR/run_reviewer_codex_structure_test.py" \
  "python3 $DIR/init_codex_structure_test.py" \
; do
  echo "── $t"
  if ! $t; then echo "   ^ FAILED"; fails=$((fails+1)); fi
done

if [ "$fails" -eq 0 ]; then echo "phase-9: ALL PASS"; exit 0; else echo "phase-9: $fails FAILED"; exit 1; fi
```

Make executable: `chmod +x tests/phase-9/run_all.sh`.

- [ ] **Step 2: Run the whole phase-9 suite**

Run: `bash tests/phase-9/run_all.sh`
Expected: each named test prints its PASS lines; final line `phase-9: ALL PASS`, exit 0.

- [ ] **Step 3: Run the pre-existing suites to prove no regression**

Run (backward-compat is the key claim — phase-5 reviewer + phase-1 config must stay green):
```bash
python3 tests/phase-1/schema_test.py
bash tests/phase-5/run_all.sh
python3 tests/phase-3/agentic_components_test.py
```
Expected: all pass. (Existing configs without a `review` block still validate; the reviewer skill's non-Codex path is unchanged.)

- [ ] **Step 4: Bump version + CHANGELOG**

In `agentic-dev/.claude-plugin/plugin.json`, change `"version": "1.6.0"` → `"version": "1.7.0"`.

Prepend to `agentic-dev/CHANGELOG.md` (below the title, above `[1.6.0]`):

```markdown
## [1.7.0] — 2026-07-26

### Added
- Optional Codex-backed adversary at the P5 review gate. When enabled and the
  Codex plugin (`codex@openai-codex`) is ready, Codex runs as a second,
  independent-model adversary alongside the Claude `reviewer-adversary`; their
  concerns are unioned and routed once via an explicit aggregate verdict.
- Reusable Codex bridge: `bin/codex-bridge.sh` (discover / preflight / review),
  `bin/codex_discovery.py` (semantic version selection), `bin/codex_adapter.py`
  (review-output → reviewer-verdict translation + merge).
- `review.codex_adversary` config field (enum `auto`|`off`). `init` writes `auto`
  for new projects and prints a setup recommendation when Codex is not ready.

### Changed
- `_run-reviewer` clean-verdict adversary branch augments with Codex when enabled.

### Backward compatibility
- The `review` block is optional; **absent ⇒ `off`**, so existing projects are
  byte-for-byte unchanged on upgrade. Codex is strictly opt-in (re-run `init` or
  set `review.codex_adversary: auto`). Any Codex unavailability degrades silently
  to Claude-only and never blocks the pipeline.
```

- [ ] **Step 5: Commit**

```bash
git add tests/phase-9/run_all.sh agentic-dev/.claude-plugin/plugin.json agentic-dev/CHANGELOG.md
git commit -m "chore(release): 1.7.0 — Codex-backed adversary review"
```

---

## Final Verification

- [ ] `bash tests/phase-9/run_all.sh` → `phase-9: ALL PASS`.
- [ ] `python3 tests/phase-1/schema_test.py` and `bash tests/phase-5/run_all.sh` → green (backward-compat).
- [ ] `git grep -n "1.7.0" agentic-dev/.claude-plugin/plugin.json` shows the bump.
- [ ] Whole-branch review (hardened-reviewer, opus) before merge, per subagent-driven-development.

## Self-Review notes (author)

- **Spec coverage:** config field (T1), bridge discover/preflight/review (T4–T6), adapter+merge (T2–T3), P5 augment + aggregate + failure isolation (T7), init onboarding (T8), backward-compat tests (T1/T9), version bump (T9). All spec sections mapped.
- **Deferred to Spec 2/3:** config reconfigure command; intent-phase Codex review. Explicit non-goals.
- **Type consistency:** `adapt(review_output, goal_id, reviewed_at)` and `merge(claude, codex)` signatures are used identically in tests and the bridge/skill. Bridge `review <goal_id> <base_sha> <worktree_path> <expected_head> [focus...]` signature is consistent across T6 test, T6 impl, and T7 skill call. Discovery keys `{ready, reason_code, detail, companion_path, schema_path}` are consistent across T4/T5/T6.
