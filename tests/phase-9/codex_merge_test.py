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

    # invariant: concern verdict must have at least one concern
    passed_concern_empty_raises = False
    try:
        ca.merge(rv("concern", []), rv("clean", []))
    except ValueError:
        passed_concern_empty_raises = True
    out.append(("concern-empty-raises", passed_concern_empty_raises))

    ok = True
    for name, passed in out:
        print(f"{'PASS' if passed else 'FAIL'} {name}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
