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
