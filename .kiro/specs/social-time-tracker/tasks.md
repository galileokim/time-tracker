# Implementation Plan: Social Time Tracker

## Overview

Build the full product in coordinated backend and iOS slices. Begin with reproducible local infrastructure and shared API contracts, implement secure account and data services, then deliver local timer and synchronization flows before completing social feed distribution and native system surfaces. Keep PostgreSQL authoritative, use Redis only as a rebuildable feed cache, and preserve client idempotency keys across retries.

## Tasks

- [x] 1. Establish backend foundation and local services
  - [x] 1.1 Configure TypeScript build, test scripts, and Fastify app factory
    - Add strict TypeScript configuration and a test runner compatible with the current ESM project.
    - Refactor server startup so tests can create an app without binding a fixed port.
    - _Requirements: 9.1, 9.2, 9.3_
  - [x] 1.2 Add Docker Compose services and environment configuration
    - Add PostgreSQL and Redis services, validated environment parsing, and safe startup diagnostics.
    - _Requirements: 9.4, 9.5_
  - [x]* 1.3 Add startup and configuration tests
    - Test valid configuration and missing required settings without printing secret values.
    - _Requirements: 9.4, 9.5_

- [x] 2. Implement relational schema and data access
  - [x] 2.1 Add relational schema, migrations, and database access
    - Define users, categories, logs, log_categories, and follows with foreign keys, uniqueness, cascades, and indexes.
    - Derive duration in PostgreSQL from timestamps.
    - _Requirements: 2.2, 2.3, 2.4, 5.2, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  - [x] 2.2 Add database integration test setup
    - Provide disposable PostgreSQL setup for migration, transaction, constraint, and cascade tests.
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6_

- [x] 3. Implement account registration, login, and profile APIs
  - [x] 3.1 Add Zod schemas and password/JWT authentication service
    - Hash passwords, register unique accounts, verify credentials, issue expiring JWTs, and derive request identity.
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_
  - [x]* 3.2 Add authentication property and route tests
    - Test public response omission of secrets, credential failures, token validation, and username/email uniqueness.
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1_
  - [x] 3.3 Add profile and category endpoints
    - Implement profile reads and permitted updates, plus category creation and owner-scoped listing.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - [x]* 3.4 Add profile and category integration tests
    - Verify ownership isolation, duplicate category conflicts, and profile response fields.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 4. Implement activity log validation and idempotent ingestion
  - [x] 4.1 Add activity log request schemas and pure domain validation
    - Enforce required fields, bounded lengths, UUID formats, visibility values, and valid timestamp ordering.
    - _Requirements: 5.7, 5.8_
  - [x]* 4.2 Add Property 1 and Property 2 tests (150 deterministic generated cases per property; Node test runner, no fast-check)
    - **Property 1: Activity Log Input Validation**
    - **Property 2: Duration Matches Timestamp Difference**
    - Generate at least 100 cases per property with fast-check.
    - **Validates: Requirements 5.7, 5.8, 8.5**
  - [x] 4.3 Implement transactional log creation and duplicate resolution
    - Verify category ownership, insert log and links atomically, and resolve uniqueness races by returning the existing log.
    - _Requirements: 5.2, 5.3, 5.4, 8.6_
  - [x]* 4.4 Add log ingestion database and API tests (implemented; DB-backed run requires Docker services)
    - Verify successful inserts, category rollback on failure, duplicate retries, and concurrent idempotency submissions.
    - _Requirements: 5.2, 5.3, 5.4, 8.6_

- [x] 5. Implement follow graph and social feed
  - [x] 5.1 Add follow management endpoints and ownership rules
    - Implement follow, unfollow, and following-list operations, including self-follow rejection.
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 5.2 Add pure feed visibility and cursor pagination functions
    - Define friends-only access as visible to the log author and users whom the author follows, consistent with the directed follow model; implement compound timestamp-and-ID cursor ordering.
    - _Requirements: 6.5, 6.6, 7.1, 7.2, 7.3, 7.5_
  - [ ]* 5.3 Add Property 4 and Property 5 tests
    - **Property 4: Visibility Filter Excludes Unauthorized Logs**
    - **Property 5: Cursor Pagination Is Ordered and Bounded**
    - Generate at least 100 cases per property, including equal timestamps and varied follow/visibility combinations.
    - **Validates: Requirements 6.5, 6.6, 7.1, 7.2, 7.3**
  - [x] 5.4 Add Redis feed indexing with database fallback
    - Fan out public log IDs after database commit, hydrate candidates in batches, and fall back to PostgreSQL when cache entries are missing or stale.
    - _Requirements: 5.2, 7.3, 7.4, 7.6_
  - [x]* 5.5 Add feed and follow integration tests
    - Verify feed visibility, pagination boundaries, empty pages, fan-out, and Redis outage fallback.
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

- [x] 6. Build native iOS timer and offline persistence
  - [x] 6.1 Create SwiftUI application structure and SwiftData models
    - Add local user/session representation, running timer records, completed logs, categories, and synchronization state.
    - _Requirements: 3.1, 3.3, 3.5, 3.6, 10.5_
  - [x] 6.2 Implement timer state and restoration
    - Persist start time and activity fields, derive elapsed display from dates, and restore an active timer after relaunch.
    - _Requirements: 3.1, 3.2, 3.4_
  - [x]* 6.3 Add timer and persistence tests (Swift Testing with in-memory SwiftData; XCTest target not wired)
    - Test start/stop, time calculations, relaunch restoration, and local edit behavior using an in-memory SwiftData store.
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.6, 10.5_

- [x] 7. Implement iOS authentication and API client
  - [x] 7.1 Add typed API client and login/registration flows
    - Encode versioned API requests, persist session tokens securely in Keychain, and handle unauthorized responses.
    - _Requirements: 1.1, 1.3, 1.4, 1.5, 1.6, 9.1_
  - [x] 7.2 Add client-side category and profile screens
    - Connect profile and category views to protected API operations and reflect server errors.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - [x]* 7.3 Add iOS API client tests
    - Test request encoding, response decoding, token attachment, and structured error handling with a URL protocol stub.
    - _Requirements: 1.3, 1.5, 1.6, 2.1, 2.4, 9.1, 9.2_

- [x] 8. Implement durable offline synchronization
  - [x] 8.1 Add sync queue worker and connectivity scheduling
    - Submit pending records with stable idempotency keys, process records independently, and preserve failures for retry.
    - _Requirements: 5.1, 5.5, 5.6, 10.1, 10.2, 10.3, 10.4_
  - [x]* 8.2 Add Property 3 and Property 6 tests (100 deterministic generated rounds; Swift Testing, no fast-check)
    - **Property 3: Idempotency-Key Retry Stability**
    - **Property 6: Sync Queue Acknowledgement Transitions**
    - Generate at least 100 cases per property for retry and success/failure transitions.
    - **Validates: Requirements 5.3, 5.5, 5.6, 10.2, 10.3, 10.4**
  - [ ]* 8.3 Add offline synchronization integration tests
    - Test successful queue drain, intermittent failure, retry after uncertain server response, and preservation across app relaunch.
    - _Requirements: 5.1, 5.3, 5.5, 5.6, 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ] 9. Add Live Activities, widgets, and feed client
  - [x] 9.1 Implement ActivityKit timer lifecycle
    - Start and end Live Activities with timer state and display the activity title and elapsed-time context.
    - _Requirements: 4.1, 4.2, 4.3_
  - [ ] 9.2 Implement WidgetKit productivity summaries (extension builds separately; not embedded in host app)
    - Calculate daily and weekly totals from local logs and refresh timelines after data changes.
    - _Requirements: 4.4, 4.5_
  - [x] 9.3 Implement paginated social feed client views
    - Load cursor pages from the API and present author, log, and category data returned under visibility rules.
    - _Requirements: 7.1, 7.2, 7.3, 7.5_
  - [ ]* 9.4 Add system surface and feed client tests (feed/API and Live Activity capability fallback covered; device-level ActivityKit/WidgetKit surface tests remain)
    - Test widget aggregation, timer capability fallback, feed decoding, cursor continuation, and empty/error states.
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 7.1, 7.2, 7.3, 7.5_

- [ ] 10. Wire and verify full product flows
  - [x] 10.1 Wire Fastify routes, services, repositories, Redis, and configuration
    - Ensure all `/api/v1` route groups use shared authentication, validation, error mapping, and service dependencies.
    - _Requirements: 1.1, 1.3, 1.5, 2.1, 2.2, 5.2, 5.3, 6.1, 7.1, 9.1, 9.2, 9.3, 9.4, 9.5_
  - [ ] 10.2 Wire iOS timer, local persistence, sync worker, and system surfaces (host app verified; widget extension embedding and device-level Live Activity remain)
    - Ensure timer completion feeds local persistence and synchronization, and local changes refresh ActivityKit and WidgetKit outputs.
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.3, 4.4, 4.5, 5.1, 5.5, 10.1, 10.5_
  - [ ]* 10.3 Add end-to-end contract tests and run full automated suites (full backend integration run requires Docker services)
    - Exercise registration, login, offline log creation, idempotent sync, follow creation, visibility-filtered feed retrieval, and cache fallback across the client/API contract.
    - _Requirements: 1.1, 1.3, 1.5, 3.3, 5.2, 5.3, 5.5, 6.1, 6.5, 6.6, 7.1, 7.2, 7.3, 7.4, 7.6, 10.2, 10.3_

## Notes

- Tasks marked with `*` are optional test tasks and can be deferred, but automated coverage is recommended before release.
- The task list is intentionally full-platform. The current repository contains only a TypeScript Fastify starter; the Swift iOS target and Xcode project will need to be created.
- Friends-only access is defined here as the log author and accounts followed by the author. This explicit rule resolves the directional ambiguity in the requirements and should be confirmed before shipping social visibility behavior.
- Backend tests use fast-check for pure logic and PostgreSQL/Redis integration tests for persistence and cache behavior. Swift logic uses XCTest unless a suitable property-testing dependency is selected.
- Property-based tests should run at least 100 generated cases and identify the matching design property in the test name or metadata.
- Feed cursor values must include both timestamp and log ID to remain stable when multiple logs share a timestamp.
- The background sync worker cannot assume iOS grants a particular execution window. Durable local queue state and idempotent retries provide recovery.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "2.1", "6.1"] },
    { "id": 1, "tasks": ["1.3", "2.2", "3.1", "6.2"] },
    { "id": 2, "tasks": ["3.2", "3.3", "4.1", "6.3", "7.1"] },
    { "id": 3, "tasks": ["3.4", "4.2", "4.3", "7.2", "7.3"] },
    { "id": 4, "tasks": ["4.4", "5.1", "5.2", "8.1"] },
    { "id": 5, "tasks": ["5.3", "5.4", "8.2", "9.1", "9.2", "9.3"] },
    { "id": 6, "tasks": ["5.5", "8.3", "9.4"] },
    { "id": 7, "tasks": ["10.1", "10.2"] },
    { "id": 8, "tasks": ["10.3"] }
  ]
}
```
