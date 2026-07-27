#!/usr/bin/env python3
"""Pure translation between Codex review-output and agentic-dev reviewer-verdict.

Stdlib only. Two entry points: adapt() and merge() (merge added in Task 3).
"""
import argparse
import json

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
    if verdict == "concern" and not concerns:
        raise ValueError("concern verdict with no concerns")
    if verdict == "concern" and any(c.get("severity") == "blocking" for c in concerns):
        raise ValueError("concern verdict with a blocking-severity concern")
    if verdict == "blocking" and not any_blocking:
        raise ValueError("blocking verdict with no blocking reason")

    return {"verdict": verdict, "concerns": concerns}


def _cmd_merge(args):
    claude = json.loads(open(args.claude).read())
    codex = json.loads(open(args.codex).read())
    print(json.dumps(merge(claude, codex)))


def main(argv=None):
    p = argparse.ArgumentParser(prog="codex_adapter")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("adapt")
    a.add_argument("review_output")
    a.add_argument("--goal-id", required=True)
    a.add_argument("--reviewed-at", required=True)
    a.set_defaults(func=_cmd_adapt)

    m = sub.add_parser("merge")
    m.add_argument("claude")
    m.add_argument("codex")
    m.set_defaults(func=_cmd_merge)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
