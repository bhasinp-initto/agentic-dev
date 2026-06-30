"""Shared component model: normalization, ownership, count parsing.

Imported by worktree-init.sh and the gate scripts so the single-vs-multi
component rules live in exactly one place. Stdlib only.
"""
import re


def _cmds(d):
    d = d or {}
    return {
        "test": d.get("test"),
        "lint": d.get("lint"),
        "typecheck": d.get("typecheck"),
        "build": d.get("build"),
    }


def normalize(cfg):
    """Return a list of normalized component dicts from a parsed config.yaml."""
    comps = cfg.get("components") or []
    if comps:
        return [{
            "name": c["name"],
            "path": c["path"],
            "primary_language": c.get("primary_language"),
            "commands": _cmds(c.get("commands")),
        } for c in comps]
    project = cfg.get("project") or {}
    return [{
        "name": project.get("name") or "project",
        "path": ".",
        "primary_language": project.get("primary_language"),
        "commands": _cmds(cfg.get("commands")),
    }]


def _depth(path):
    p = path.strip("/")
    if p in ("", "."):
        return 0
    return p.count("/") + 1


def _owns(component_path, file_path):
    cp = component_path.strip("/")
    fp = file_path.strip("/")
    if cp in ("", "."):
        return True
    return fp == cp or fp.startswith(cp + "/")


def owner(components, file_path):
    """Most-specific component owning file_path, or None."""
    best = None
    best_depth = -1
    for c in components:
        if _owns(c["path"], file_path) and _depth(c["path"]) > best_depth:
            best = c
            best_depth = _depth(c["path"])
    return best


def select_touched(components, files):
    """(selected_components_in_config_order, unmatched_files)."""
    hit = set()
    unmatched = []
    for f in files:
        c = owner(components, f)
        if c is None:
            unmatched.append(f)
        else:
            hit.add(c["name"])
    selected = [c for c in components if c["name"] in hit]
    return selected, unmatched


def parse_test_counts(output):
    """Parse {'passed','failed','skipped'} from test output, or None."""
    passed_n = failed_n = None

    m = re.search(r'Tests?:\s+(\d+)\s+passed', output, re.IGNORECASE)
    if m:
        passed_n = int(m.group(1))
    m2 = re.search(r'Tests?:.*?(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
    if m2:
        failed_n = int(m2.group(1))
    else:
        m2b = re.search(r'(\d+)\s+fail(?:ed|ing)', output, re.IGNORECASE)
        if m2b:
            failed_n = int(m2b.group(1))

    if passed_n is None:
        m = re.search(r'={3,}\s*(\d+)\s+passed', output, re.IGNORECASE)
        if m:
            passed_n = int(m.group(1))
    if failed_n is None:
        m = re.search(r'={3,}.*?(\d+)\s+failed', output, re.IGNORECASE)
        if m:
            failed_n = int(m.group(1))

    if passed_n is None:
        m = re.search(r'(\d+)\s+passed', output, re.IGNORECASE)
        if m:
            passed_n = int(m.group(1))
    if failed_n is None:
        m = re.search(r'(\d+)\s+failed', output, re.IGNORECASE)
        if m:
            failed_n = int(m.group(1))

    if passed_n is None:
        pass_lines = [l for l in output.splitlines() if re.match(r'^(PASS|ok)\b', l.strip())]
        fail_lines = [l for l in output.splitlines() if re.match(r'^FAIL\b', l.strip())]
        if pass_lines or fail_lines:
            passed_n = len(pass_lines)
            failed_n = len(fail_lines)

    if passed_n is None:
        return None

    skipped_n = 0
    m = re.search(r'(\d+)\s+skipped', output, re.IGNORECASE)
    if m:
        skipped_n = int(m.group(1))
    return {
        "passed": passed_n,
        "failed": failed_n if failed_n is not None else 0,
        "skipped": skipped_n,
    }
