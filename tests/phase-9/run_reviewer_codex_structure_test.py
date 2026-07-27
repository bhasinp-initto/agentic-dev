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
