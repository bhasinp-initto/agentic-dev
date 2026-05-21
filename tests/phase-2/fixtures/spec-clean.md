---
id: 2026-05-20-clean-fixture
schema_version: "0.1"
intent_path: .claude/agentic/intents/2026-05-20-clean-fixture.md
approved: false
created_at: "2026-05-20T15:30:00Z"
---

# Intent

Add a /health endpoint to the API that returns 200 OK with build version.

# Scope — In

- Add a new HTTP endpoint at GET /health that returns 200 OK.

# Scope — Out (deferrals)

- Deep health checks (database connectivity, external service pings) are out of scope.

# Files in scope

- src/routes/health.ts
- tests/routes/health.test.ts

# Architectural decisions

- Response body shape: `{ "status": "ok", "version": "<build-sha>" }`.

# ADR candidates

None.

# Test strategy

Add tests for new behaviors (200 OK response, correct body shape). Existing tests must continue to pass.

# Completion criteria

- Tests in tests/routes/health.test.ts pass
- GET /health returns HTTP 200 with body matching the agreed shape
- Existing test suite passes without modification

# Diff budget

- Wall clock: 30 minutes
- Diff lines: 100
- Files touched: 3

# Sensitive paths

(inherits from config.yaml)
