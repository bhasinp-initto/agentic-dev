# Tests

Phase-scoped tests for the `agentic-dev` plugin. Each phase has its own subdirectory; tests are independent and can be run individually or via the phase's `run_all.sh`.

## Prerequisites

### Python dependencies

```bash
python3 -m pip install -r tests/requirements.txt
```

This installs `pyyaml` and `jsonschema[format-nongpl]` (the latter brings in `rfc3339-validator`, which is required for `format_checker=jsonschema.FormatChecker()` to actually enforce `date-time` formats).

If you're on Homebrew-managed Python (macOS), pip will refuse to install into the system environment by default. Either use a virtualenv:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tests/requirements.txt
```

or, for a one-off install, add `--break-system-packages` (informally noted by T2 implementer):

```bash
python3 -m pip install --break-system-packages -r tests/requirements.txt
```

### Claude Code

Claude Code must be installed and `claude --version` must work. The shell-driven tests invoke `claude -p` (headless mode) to exercise the plugin's skills end-to-end.

### API authentication for headless mode

Headless `claude -p` is blocked from Max subscription auth until **June 15, 2026**. Until then (and afterwards if you want to test outside the Agent SDK credit pool), point Claude Code at an Anthropic API key.

Convention used by the tests in this repo:

1. Create `~/.claude/agentic-dev-test.env` with:
   ```bash
   export ANTHROPIC_API_KEY='sk-ant-...'
   ```
2. Set permissions: `chmod 600 ~/.claude/agentic-dev-test.env`
3. Each test script sources this file at the top if it exists. The file lives at `~/.claude/` which is **outside this repository** — git never sees it. As defense in depth, `*.env` is also globbed by the repo's `.gitignore`, so even if someone copied the file into the repo by mistake it would not be tracked. Do NOT commit any env file.

If `~/.claude/agentic-dev-test.env` is absent, the tests still run but the headless invocations may fail with auth errors.

## Running Phase 1

```bash
bash tests/phase-1/run_all.sh
```

Individual tests:
```bash
python3 tests/phase-1/schema_test.py
bash tests/phase-1/init_test.sh
bash tests/phase-1/status_test.sh
bash tests/phase-1/smoke_test.sh
```

## What each test covers

| Test | Validates |
|------|-----------|
| `schema_test.py` | Sample fixtures conform to state/queue/config JSON Schemas; a known-bad state and a known-bad halted state are explicitly rejected. |
| `init_test.sh` | `/agentic-dev:init` creates the full `.claude/agentic/` tree (incl. `.gitkeep` files) with schema-valid state/queue/config; idempotent on re-run (state, config, queue all unchanged). |
| `status_test.sh` | `/agentic-dev:status` reads known state and reports correct counts, current goal, config summary; handles not-initialized projects with a clear message. |
| `smoke_test.sh` | Init followed by status produces consistent state — `circuit breaker: idle`, `queue is empty`, project name reflected. |

## Debugging

When a shell test fails and you want to inspect what was actually written to disk before cleanup:

```bash
KEEP_TMP=1 bash tests/phase-1/init_test.sh
```

The test will print `Preserved tmp project at: /tmp/agentic-init-XXXXXX` on exit instead of deleting it. Inspect with `ls /tmp/agentic-*/.claude/agentic/` etc. Remember to `rm -rf` it manually when done.

## Cost / billing note

The shell tests invoke `claude -p` which counts as **programmatic billing** per Anthropic's June 15, 2026 policy split. Until that date, headless mode requires an API key (pay-per-token). Each Phase 1 test run consumes a few cents in API tokens; the full `run_all.sh` is well under a dollar in typical usage.

Production use of the `agentic-dev` plugin remains interactive (human-launched Claude Code sessions), billing against your Max plan — see the design spec, §5 and Appendix B.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Credit balance is too low` | API account out of credits | Top up at https://console.anthropic.com/settings/billing |
| `Unknown command: /agentic-dev:...` | Plugin didn't load | Check `--plugin-dir` path; verify `agentic-dev/.claude-plugin/plugin.json` exists |
| `FileNotFoundError` for a schema file | Schema file missing | Verify the schema files exist at `agentic-dev/schemas/*.schema.json`. Tests resolve paths from `$0`/`__file__`, not CWD, so running from any directory is fine. |
| Python heredoc fails with `ImportError` | Missing dependency | Run `pip install -r tests/requirements.txt` |
| `claude -p` hangs >60s | Network / API issue | Cancel; re-run; check Anthropic status page |
