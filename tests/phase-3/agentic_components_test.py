"""Unit tests for the shared component helper."""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "agentic-dev" / "bin"))
import agentic_components as ac  # noqa: E402

PASS = FAIL = 0
def check(name, cond):
    global PASS, FAIL
    if cond:
        print(f"PASS {name}"); PASS += 1
    else:
        print(f"FAIL {name}"); FAIL += 1

# normalize: single-component fallback
single = {"project": {"name": "p", "primary_language": "go"},
          "commands": {"test": "go test ./...", "lint": "golangci-lint run"}}
n = ac.normalize(single)
check("single-count", len(n) == 1)
check("single-path", n[0]["path"] == ".")
check("single-cmd", n[0]["commands"]["test"] == "go test ./...")
check("single-typecheck-none", n[0]["commands"]["typecheck"] is None)

# normalize: explicit components
multi = {"project": {"name": "p"},
         "commands": {"test": "x", "lint": "y"},
         "components": [
             {"name": "backend", "path": "backend",
              "commands": {"test": "pytest", "lint": "ruff check ."}},
             {"name": "frontend", "path": "frontend",
              "commands": {"test": "npm test", "lint": "eslint ."}}]}
m = ac.normalize(multi)
check("multi-count", len(m) == 2)
check("multi-names", [c["name"] for c in m] == ["backend", "frontend"])

# owner: prefix & specificity
check("owner-basic", ac.owner(m, "backend/app.py")["name"] == "backend")
check("owner-none", ac.owner(m, "docs/readme.md") is None)
# 'front' must NOT match 'frontend'
check("owner-segment", ac.owner(m, "frontendish/x.ts") is None)
# longest path wins
nested = ac.normalize({"components": [
    {"name": "all", "path": ".", "commands": {"test": "a", "lint": "b"}},
    {"name": "api", "path": "services/api", "commands": {"test": "c", "lint": "d"}}]})
check("owner-specific", ac.owner(nested, "services/api/main.py")["name"] == "api")
check("owner-dot-fallback", ac.owner(nested, "README.md")["name"] == "all")

# select_touched
sel, unmatched = ac.select_touched(m, ["backend/a.py", "backend/b.py", "docs/x.md"])
check("select-names", [c["name"] for c in sel] == ["backend"])
check("select-unmatched", unmatched == ["docs/x.md"])

# parse_test_counts
check("parse-pytest", ac.parse_test_counts("=== 5 passed, 1 failed ===") == {"passed": 5, "failed": 1, "skipped": 0})
check("parse-none", ac.parse_test_counts("no counts here") is None)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
