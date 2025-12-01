# Well-formed commit messages

Each example shows the subject line and, where applicable, the body and footer.

## Features

```
feat: add user authentication endpoint

POST /auth/login accepts email and password, returns a signed JWT.
The token is valid for 24 hours and must be sent as a Bearer token
on subsequent requests.
```

```
feat(api): add pagination to list-users endpoint

Supports limit and offset query parameters. Defaults to limit=20,
offset=0 when not provided.
```

## Fixes

```
fix: resolve race condition in cache invalidation

Concurrent writes to the session cache could leave stale entries
when two requests invalidated the same key. The fix introduces a
write lock scoped to the cache key.
```

```
fix(db): handle connection timeout during failover

Previously the driver would hang indefinitely. Now it retries up
to 3 times with a 5-second cap per attempt.
```

## Documentation

```
docs: document authentication flow in README

Adds a sequence diagram and step-by-step instructions for setting
up OAuth2 with the portal.
```

## Refactoring

```
refactor: extract token validation into TokenService

No behavioural changes. The validation logic that was duplicated
across three controllers now lives in a single service.
```

## Performance

```
perf: add index on users(email)

Reduces the email-lookup query from ~200ms to ~2ms on the staging
dataset (1.2M rows).
```

## Breaking changes

```
feat!: drop support for API v1

All v1 endpoints return 410 Gone. Clients must upgrade to v2.

BREAKING CHANGE: v1 endpoints removed. See migration guide at /docs/v1-to-v2.
```

```
feat(auth)!: require email verification before first login

BREAKING CHANGE: unverified accounts can no longer obtain a session token
```

## Revert

```
revert: "feat: add experimental search index"

This reverts commit abc123def. The index caused a 40% increase in
write latency under load and needs further optimization.
```

## Tests

```
test: add integration tests for token refresh flow

Covers happy path, expired token, and revoked token scenarios.
```

## CI / Build

```
ci: run smoke tests against staging after deploy

Adds a new workflow step that hits the /health and /auth/login
endpoints and fails the pipeline if either returns an error.
```
