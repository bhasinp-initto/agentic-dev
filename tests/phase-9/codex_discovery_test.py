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
    suffix = "enabled" if enabled else "disabled"
    p = tmp / f"settings_{suffix}.json"
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
