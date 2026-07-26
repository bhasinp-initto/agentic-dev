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
