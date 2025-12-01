# Worked Example: Add user authentication

This example shows all three templates filled in for a fictional "add user authentication to the portal API" feature. Use it as a reference when filling in the templates for a real project.

---

## Milestone Outline (filled in)

# Milestone Outline: Add user authentication

| # | Phase | Goal | Files to touch | Depends on |
|---|-------|------|----------------|------------|
| 1 | Cognito infrastructure | Provision a user pool and API Gateway authorizer via Terraform. | `env/portal/cognito.tf`, `env/portal/api-gateway.tf` | — |
| 2 | JWT validation middleware | Validate Cognito tokens on incoming requests and extract user claims. | `src/Portal/Portal.Api/Middleware/JwtAuthMiddleware.cs`, `src/Portal/Portal.Api/Extensions/ServiceCollectionExtensions.cs` | Phase 1 |
| 3 | Protect existing endpoints | Add `[RequireAuth]` to the user and project endpoints. | `src/Portal/Portal.Api/Endpoints/Users/`, `src/Portal/Portal.Api/Endpoints/Projects/` | Phase 2 |
| 4 | Login UI | Add a login form to the portal frontend that exchanges credentials for a JWT. | `app/portal/src/components/LoginForm.vue`, `app/portal/src/stores/auth.ts` | Phase 1 |
| 5 | Token persistence and refresh | Store the token, attach it to API requests, and refresh before expiry. | `app/portal/src/api/client.ts`, `app/portal/src/stores/auth.ts` | Phase 4 |

## Phase details

### Phase 1: Cognito infrastructure

**Goal:** Provision a Cognito User Pool with email-as-username, a User Pool Client for the SPA, and an API Gateway authorizer that validates tokens. Deploy to staging and confirm the authorizer rejects unauthenticated requests.

**Exit criteria:**
- `terraform apply` succeeds against the staging account.
- An unauthenticated request to any endpoint returns 401.
- The user pool ID and client ID are available as Terraform outputs.

### Phase 2: JWT validation middleware

**Goal:** Add middleware that reads the `Authorization: Bearer <token>` header, validates it against the Cognito well-known JWKS endpoint, and populates `HttpContext.User` with the resulting claims. Unauthenticated requests receive 401; invalid tokens receive 403.

**Exit criteria:**
- Unit tests cover valid token, expired token, missing header, and tampered payload.
- Integration test against staging Cognito verifies a real token is accepted.

### Phase 3: Protect existing endpoints

**Goal:** Apply the auth middleware to all endpoints under `/users` and `/projects`. Verify that unauthenticated callers receive 401 and authenticated callers receive the same responses as before.

**Exit criteria:**
- Existing integration tests continue to pass (test harness sends a valid test token).
- Manual smoke test with a staging token confirms end-to-end access.

### Phase 4: Login UI

**Goal:** Build a login form (email + password) that calls the Cognito `InitiateAuth` endpoint and stores the resulting JWT in the Pinia auth store.

**Exit criteria:**
- Unauthenticated user visiting the portal is redirected to `/login`.
- Valid credentials store a JWT and redirect to the home page.
- Invalid credentials show an inline error without a page reload.

### Phase 5: Token persistence and refresh

**Goal:** Attach the stored JWT to every API request via an Axios interceptor. When a token is within 5 minutes of expiry, call the Cognito `InitiateAuth` refresh flow silently and update the store.

**Exit criteria:**
- API requests include the `Authorization` header automatically.
- Expired tokens are refreshed without the user re-entering credentials.
- If refresh fails (e.g. network error), the user is redirected to `/login`.

---

## Issue Template (filled in, Phase 2 shown)

# Add JWT validation middleware

## Context

The portal API currently accepts unauthenticated requests. Once the Cognito user pool is provisioned (Phase 1), we need middleware that validates the JWT on every incoming request so that downstream endpoints can trust the caller's identity. Without this middleware, every endpoint would need to duplicate token validation logic.

## Approach

1. Add `JwtAuthMiddleware.cs` under `src/Portal/Portal.Api/Middleware/`. The middleware reads the `Authorization` header, extracts the Bearer token, and validates it against the Cognito JWKS endpoint (`https://cognito-idp.{region}.amazonaws.com/{pool-id}/.well-known/jwks.json`).
2. Register the middleware in `Program.cs` via an `UseJwtAuth()` extension method on `IApplicationBuilder`.
3. Add configuration keys (`COGNITO_AUTHORITY`, `COGNITO_CLIENT_ID`) read from environment variables.
4. On validation failure return 401 (missing/empty header) or 403 (invalid/expired token). On success, populate `HttpContext.User` and call `next(context)`.

## Acceptance criteria

- [ ] Requests without an `Authorization` header receive 401 with a `WWW-Authenticate: Bearer` response header.
- [ ] Requests with an expired or tampered token receive 403.
- [ ] Requests with a valid token reach the downstream endpoint with `HttpContext.User.Identity.IsAuthenticated == true`.
- [ ] The middleware logs a warning on validation failure and debug on success.

## Dependencies

- Blocks: Phase 3 (Protect existing endpoints)
- Blocked by: Phase 1 (Cognito infrastructure)

## Definition of done

- [ ] Implementation matches the approach described above.
- [ ] Unit tests cover valid token, expired token, missing header, tampered payload, and JWKS fetch failure.
- [ ] Integration test verifies a real Cognito token from the staging pool is accepted.
- [ ] `CODEMAP.md` is updated to list the new middleware in the architecture patterns section.

---

## Dependency Map (filled in)

# Dependency Map: Add user authentication

```
Phase 1: Cognito infrastructure
  ├─► Phase 2: JWT validation middleware
  │     └─► Phase 3: Protect existing endpoints
  └─► Phase 4: Login UI
        └─► Phase 5: Token persistence and refresh
```

## Blocking relationships

| Phase | Blocks | Blocked by |
|-------|--------|------------|
| Phase 1: Cognito infrastructure | Phase 2, Phase 4 | — |
| Phase 2: JWT validation middleware | Phase 3 | Phase 1 |
| Phase 3: Protect existing endpoints | — | Phase 2 |
| Phase 4: Login UI | Phase 5 | Phase 1 |
| Phase 5: Token persistence and refresh | — | Phase 4 |

## Parallelism

- **Wave 1:** Phase 1 (Cognito infrastructure) — no blockers.
- **Wave 2:** Phase 2 (JWT middleware) and Phase 4 (Login UI) — both depend only on Phase 1 and can proceed in parallel.
- **Wave 3:** Phase 3 (Protect endpoints), Phase 5 (Token persistence) — each depends on a different Wave 2 phase and can proceed in parallel.
