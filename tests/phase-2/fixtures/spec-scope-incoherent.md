---
id: 2026-05-20-incoherent-fixture
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-incoherent-fixture.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Add rate limiting per-tenant to the API.

# Scope — In

- Update the documentation site footer to add a new link.

# Scope — Out (deferrals)

- Rate limiting is out of scope.

# Files in scope

- docs/site/footer.html

# Architectural decisions

- None.

# ADR candidates

None.

# Test strategy

Add tests for new behaviors. Existing tests must continue to pass.

# Completion criteria

- The footer HTML file contains a link element with the new text
- Existing tests pass without modification

# Diff budget

- Wall clock: 15 minutes
- Diff lines: 20
- Files touched: 1

# Sensitive paths

(inherits from config.yaml)
