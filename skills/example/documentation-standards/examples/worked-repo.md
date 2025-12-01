# Worked Example: notification-service

This example shows all four templates filled in for a fictional `notification-service` repository — a service that sends email and push notifications for an e-commerce platform. Use it as a reference when filling in the templates for a real project.

---

## README.md (filled in)

# notification-service

Sends transactional email and push notifications for the ShopRight e-commerce platform.

## What is notification-service?

The notification service dispatches transactional messages — order confirmations, shipping updates, password resets — through pluggable channels (email via SES, push via FCM). It exposes an asynchronous HTTP API that downstream services call with a template key and recipient, and it handles batching, retry, and delivery tracking.

The service does not manage notification templates (those live in a separate template service) and does not handle marketing campaigns (that is the campaign service's responsibility).

## Quickstart

**Prerequisites:** Node.js 20+, Docker (for LocalStack SES in development)

```bash
git clone <repo-url> && cd notification-service
npm install
cp .env.example .env
docker compose up -d localstack  # Start local SES emulator
npm run dev
```

The API listens on `http://localhost:3001`. The health check is at `/health`.

## Usage

```bash
# Send an order confirmation
curl -X POST http://localhost:3001/notifications \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "template": "order-confirmation",
    "recipient": {"email": "customer@example.com", "userId": "usr_abc"},
    "data": {"orderId": "ord_123", "total": 49.99}
  }'
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_SES_ENDPOINT` | `http://localhost:4566` | SES-compatible endpoint (LocalStack in dev) |
| `FCM_CREDENTIALS_PATH` | `./fcm-credentials.json` | Path to Firebase Cloud Messaging service account key |
| `MAX_RETRIES` | `3` | Maximum delivery attempts per notification |
| `LOG_LEVEL` | `info` | One of `debug`, `info`, `warn`, `error` |

## Further reading

- [CODEMAP](CODEMAP.md) — repository structure, technology stack, and implementation patterns.
- [ADR 0001](docs/decisions/0001-use-ses-for-email.md) — why SES was chosen over SendGrid for email delivery.
- [Notification API spec](docs/api/notifications.md) — full endpoint reference.

---

## CODEMAP.md (filled in)

# CODEMAP — notification-service

Repository-specific structure, technology stack, and implementation patterns.

## Purpose

The notification service dispatches transactional email and push notifications for the ShopRight e-commerce platform. It provides an asynchronous HTTP API consumed by the order service, user service, and shipping service.

## Top-level layout

```
notification-service/
├── src/
│   ├── api/             # Express HTTP server, routes, middleware
│   ├── channels/        # Delivery channel implementations (email, push)
│   ├── dispatcher/      # Core dispatch logic: batching, retry, routing
│   └── tracking/        # Delivery status tracking and webhook handlers
├── tests/               # Test suites (mirrors src/ structure)
├── docs/                # Specifications, ADRs, API documentation
├── .github/             # CI workflows
├── CODEMAP.md           # This file
└── README.md            # Project overview
```

## Technology stack

| Layer | Technology in use | Notes |
|-------|------------------|-------|
| Runtime | Node.js 20 LTS | Long-term support through 2026-04 |
| HTTP framework | Express 4.x | Minimal, well-understood; no plans to migrate |
| Email channel | AWS SES via `@aws-sdk/client-ses` | Lowest cost per email, already in AWS ecosystem |
| Push channel | Firebase Cloud Messaging via `firebase-admin` | Required for Android push; web push uses the same SDK |
| Queue | SQS via `@aws-sdk/client-sqs` | Decouples API from dispatch; enables batching |
| Testing | Vitest | Fast, Jest-compatible, native ESM support |
| CI | GitHub Actions | `.github/workflows/ci.yaml` |

### Deviations from technology preferences

#### Express instead of Vue.js for the HTTP layer

**Deviation from Preference:** Repository preferences default to Vue.js for frontends. This repository uses Express because it is a backend API, not a user-facing application.

**Rationale:** The notification service has no UI. It exposes a machine-to-machine REST API. Express is the established backend HTTP framework for the Node.js ecosystem at ShopRight.

**Trade-offs Accepted:** None — this is not a frontend repository, so the Vue.js preference does not apply.

**Mitigation:** Not applicable. If the repository later adds an admin dashboard, that would live under `app/notification-admin/` using Vue.js.

## Build and test

**Build:** `npm run build` (TypeScript compilation). No runtime build step needed.

**Test:** `npm test` runs the full Vitest suite (unit + integration).

**CI:** `.github/workflows/ci.yaml` runs on push/PR to `main` — lint, type-check, unit tests, integration tests against LocalStack.

**Local validation:**
```bash
npm run lint && npm run type-check && npm test
```

## Architecture decisions

| ADR | Decision |
|-----|----------|
| [0001-use-ses-for-email.md](docs/decisions/0001-use-ses-for-email.md) | Use AWS SES instead of SendGrid for transactional email delivery |
| [0002-sqs-queue-decoupling.md](docs/decisions/0002-sqs-queue-decoupling.md) | Insert an SQS queue between the API and the dispatcher for batching and resilience |

## Architecture patterns

- **Channel abstraction:** Each delivery channel (email, push) implements the same `Channel` interface. Adding a new channel (SMS, Slack) means creating one new file, not modifying existing code.
- **Async request/response:** The API accepts a notification request, enqueues it, and returns a tracking ID immediately. Consumers poll or subscribe to a webhook for delivery status.
- **Idempotency keys:** Every notification carries a client-generated idempotency key. The dispatcher deduplicates on this key so a retried HTTP request does not double-send.

## Key invariants

- A notification must never be silently dropped. If all delivery attempts fail, the failure is logged and surfaced via the tracking endpoint.
- Idempotency keys are required on every request. The API returns 400 if one is missing.
- Channel implementations must not import from `src/api/` (dependency direction: api → dispatcher → channels).
- All environment-specific configuration comes from environment variables. No hardcoded endpoints or credentials.

---

## ADR (filled in)

# ADR 0001: Use AWS SES for Transactional Email

## Status

Accepted (2026-03-15)

## Context

The notification service needs an email delivery channel for transactional messages — order confirmations, shipping updates, and password resets. These are time-sensitive (must arrive within 60 seconds of the triggering event) and must handle approximately 50,000 emails per day at peak.

Two providers were evaluated:
- **AWS SES** — already available in our AWS account, pay-per-email pricing ($0.10/1,000 emails).
- **SendGrid** — established third-party API, richer analytics dashboard, slightly higher per-email cost.

Both meet the throughput and latency requirements. The decision comes down to operational simplicity and cost.

## Decision

**Use AWS SES for transactional email delivery.** The channel implementation lives at `src/channels/email/` with the `@aws-sdk/client-ses` SDK. In development, LocalStack emulates the SES API so contributors do not need AWS credentials.

## Rationale

- **Zero new vendor.** SES is already provisioned in our AWS account (verified domain, production access granted). SendGrid would require a new vendor relationship, a new bill to manage, and a new API key rotation procedure.
- **Cost at scale.** At 50,000 emails/day (~1.5M/month), SES costs approximately $150/month. SendGrid's equivalent tier is $250/month. The $100/month difference is small in absolute terms but the SES cost stays linear while SendGrid pricing tiers introduce step changes as volume grows.
- **Single AWS bill.** All infrastructure costs (Lambda, SQS, DynamoDB, SES) appear on one invoice with unified usage tracking. Adding SendGrid creates a separate billing relationship.
- **IAM-based auth.** SES authentication uses IAM roles (no long-lived API keys). The notification service's ECS task role already has the required `ses:SendEmail` permission. SendGrid would add a secret to rotate.

## Trade-offs

| Trade-off | Mitigation |
|-----------|-----------|
| SES has a less polished analytics dashboard than SendGrid (no out-of-the-box open/click tracking for transactional emails). | We only need delivery confirmation, not engagement analytics. SES sends delivery/SQS events to an SNS topic; the tracking module in `src/tracking/` subscribes to these. |
| SES requires a "warm-up" period for new sending domains before full throughput is available. | Our domain has been verified and warmed up for 6+ months (used by the legacy monolith). |
| SES sending limits (50,000/day by default, adjustable via support ticket). | Our peak volume is within the default limit. If we approach it, a service quota increase is a one-time support ticket. |
| Tighter AWS coupling. Switching email providers later means replacing the SES SDK with a different one. | The `Channel` interface in `src/channels/` abstracts the SDK. A future SendGrid channel would implement the same interface without changing the dispatcher. |

## Consequences

- We can send email from any service that has IAM credentials with the `ses:SendEmail` permission.
- We must stay within the SES sending limits for our region (`us-east-1`). The tracking module monitors the daily send count and alerts at 80% of quota.
- The development environment depends on LocalStack for SES emulation. Contributors must run `docker compose up -d localstack` before running integration tests.
- If we later need rich email analytics (open tracking, click maps), we will evaluate whether to add SendGrid as a second channel or enhance the tracking module with CloudFront pixel tracking.

---

## CHANGELOG.md (filled in)

# Changelog

All notable changes to notification-service are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Webhook endpoint for Firebase Cloud Messaging bounce callbacks.

## [1.2.0] — 2026-05-20

### Added
- Push notification channel via Firebase Cloud Messaging.
- `GET /notifications/:trackingId` endpoint for delivery status polling.

### Changed
- Dispatcher now batches up to 50 emails per SES `SendBulkEmail` call (was sending individually).

### Fixed
- Retry count was not reset when a notification was requeued after a transient SES failure.

## [1.1.0] — 2026-04-02

### Added
- Idempotency key support. Duplicate requests with the same key return the original tracking ID.
- SQS queue between the API and dispatcher for asynchronous processing.

### Changed
- `/notifications` endpoint now returns `202 Accepted` with a tracking ID instead of blocking until delivery completes.

## [1.0.0] — 2026-03-20

### Added
- Initial release: email delivery channel via AWS SES.
- Order confirmation, shipping update, and password reset templates.
- Delivery status webhook for SES bounce and complaint notifications.

[1.2.0]: https://github.com/shopright/notification-service/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/shopright/notification-service/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/shopright/notification-service/releases/tag/v1.0.0
