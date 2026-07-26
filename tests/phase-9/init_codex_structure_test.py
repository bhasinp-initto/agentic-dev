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
