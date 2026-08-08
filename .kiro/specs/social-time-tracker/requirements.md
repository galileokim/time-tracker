# Requirements Document

## Introduction

The Social Time Tracker is a social productivity platform with a native iOS client and a TypeScript/Fastify backend. The iOS app records activities locally, supports timer use without network access, and synchronizes completed logs when connectivity returns. The backend provides username/password authentication, durable log storage, and a paginated social feed. PostgreSQL stores relational records and Redis supports feed distribution. Native iOS features include Live Activities, Dynamic Island, and productivity widgets.

The existing workspace contains a minimal TypeScript Fastify service. The requirements cover the full product described in the architecture brief, including mobile and backend components that do not yet exist in the repository.

## Glossary

- **Social_Time_Tracker**: The complete iOS and backend application.
- **iOS_Client**: The native SwiftUI application and its local persistence and operating-system integrations.
- **Backend_API**: The TypeScript and Fastify service that provides authenticated application endpoints.
- **User**: An account with a unique identifier, username, display name, email, and password credential.
- **Activity_Log**: A completed timed activity with a title, optional notes, start and end timestamps, visibility, categories, and an idempotency key.
- **Category**: A user-owned label that can be associated with activity logs.
- **Idempotency_Key**: A client-generated UUID that identifies one activity log across repeated synchronization attempts.
- **Offline_Queue**: Locally persisted activity logs that have not yet synchronized with the Backend_API.
- **Visibility**: An activity log access setting with the values public, private, or friends-only.
- **Follow**: A directed relationship in which one User follows another User.
- **Social_Feed**: A paginated list of activity logs visible to the authenticated User from followed accounts.
- **JWT**: A signed JSON Web Token used by the Backend_API to authenticate requests after login.
- **Live_Activity**: An iOS ActivityKit presentation of the currently running timer on the Lock Screen and Dynamic Island.
- **Productivity_Widget**: A WidgetKit view of daily or weekly activity totals derived from local activity logs.

## Requirements

### Requirement 1: Account Registration and Authentication

**User Story:** As a person using the Social_Time_Tracker, I want to create an account and sign in with a username and password, so that my activity data belongs to my account.

#### Acceptance Criteria

1. WHEN a person submits valid registration details, THE Backend_API SHALL create a User with a unique username and email.
2. IF a registration request contains a username or email already assigned to another User, THEN THE Backend_API SHALL reject the request with an input conflict response.
3. WHEN a person submits valid username and password credentials, THE Backend_API SHALL issue a signed JWT associated with the authenticated User.
4. IF a person submits invalid credentials, THEN THE Backend_API SHALL return an authentication error without issuing a JWT.
5. WHEN an authenticated request reaches a protected endpoint, THE Backend_API SHALL identify the User from a valid, unexpired JWT.
6. IF a protected request contains a missing, invalid, or expired JWT, THEN THE Backend_API SHALL return an unauthorized response.
7. THE Backend_API SHALL store password credentials using a salted, computationally expensive password hash and SHALL NOT store plaintext passwords.

### Requirement 2: User Profiles and Categories

**User Story:** As an authenticated User, I want a profile and personal activity categories, so that I can organize and identify my work.

#### Acceptance Criteria

1. WHEN an authenticated User requests their profile, THE Backend_API SHALL return that User's public profile fields and omit password credentials.
2. WHEN an authenticated User creates a Category, THE Backend_API SHALL associate the Category with that User.
3. IF a User creates a Category with a name already used by that User, THEN THE Backend_API SHALL reject the request with a conflict response.
4. WHEN a User requests categories, THE Backend_API SHALL return only categories owned by that User.
5. WHEN an authenticated User updates permitted profile fields, THE Backend_API SHALL persist and return the updated profile.

### Requirement 3: Activity Timer and Local Persistence

**User Story:** As an iOS user, I want to start and stop an activity timer without relying on a network connection, so that tracking continues wherever I work.

#### Acceptance Criteria

1. WHEN a User starts a timer, THE iOS_Client SHALL persist the timer start time and activity details locally.
2. WHILE an activity timer is running, THE iOS_Client SHALL calculate elapsed duration from persisted start-time data rather than relying on continuous foreground execution.
3. WHEN a User stops a timer, THE iOS_Client SHALL create and persist a completed Activity_Log with a client-generated Idempotency_Key.
4. IF the iOS_Client process is suspended or terminated while a timer is running, THEN THE iOS_Client SHALL restore the running timer state from local persistence when the application next launches.
5. IF the device has no network connection when a User completes a timer, THEN THE iOS_Client SHALL retain the Activity_Log in the Offline_Queue.
6. WHEN a User edits an unsynchronized Activity_Log, THE iOS_Client SHALL persist the edit locally and submit the latest saved values during synchronization.

### Requirement 4: Live Activities and Productivity Widgets

**User Story:** As an iOS user, I want to see a running timer and activity summaries in system surfaces, so that I can check progress without opening the application.

#### Acceptance Criteria

1. WHEN a User starts a timer and the device permits Live_Activities, THE iOS_Client SHALL present the running timer through ActivityKit.
2. WHILE a timer is running, THE iOS_Client SHALL display the timer's activity title and elapsed-time context in supported Lock Screen and Dynamic Island presentations.
3. WHEN a User stops a timer, THE iOS_Client SHALL end the corresponding Live_Activity.
4. WHEN a Productivity_Widget is displayed, THE iOS_Client SHALL show daily and weekly activity totals calculated from locally persisted Activity_Logs.
5. WHEN local Activity_Logs change, THE iOS_Client SHALL refresh affected Productivity_Widgets.

### Requirement 5: Activity Log Ingestion and Idempotent Synchronization

**User Story:** As an iOS user, I want completed logs to synchronize safely after connectivity returns, so that retries do not create duplicate records.

#### Acceptance Criteria

1. WHEN the iOS_Client has connectivity and unsynchronized Activity_Logs, THE iOS_Client SHALL submit queued logs to the Backend_API.
2. WHEN the Backend_API receives a valid Activity_Log with a new Idempotency_Key, THE Backend_API SHALL persist the log and its category associations as one database transaction.
3. WHEN the Backend_API receives an Activity_Log with an Idempotency_Key already stored, THE Backend_API SHALL return the existing log identifier without creating another log.
4. IF a log submission references a Category not owned by the authenticated User, THEN THE Backend_API SHALL reject the submission without persisting the log or category associations.
5. WHEN the Backend_API successfully acknowledges an Activity_Log, THE iOS_Client SHALL mark the corresponding local log as synchronized.
6. IF a synchronization request fails because of a network or server error, THEN THE iOS_Client SHALL retain the log in the Offline_Queue for a later retry.
7. WHEN a User submits an Activity_Log, THE Backend_API SHALL reject an end timestamp earlier than the start timestamp.
8. WHEN a User submits an Activity_Log, THE Backend_API SHALL validate required fields, field length limits, timestamp formats, visibility values, UUID formats, and category identifier formats before persistence.

### Requirement 6: Follow Relationships and Visibility

**User Story:** As a User, I want to follow other Users and control who can see my activity, so that social sharing respects my choices.

#### Acceptance Criteria

1. WHEN an authenticated User follows another User, THE Backend_API SHALL persist a directed Follow relationship.
2. WHEN a User requests the accounts they follow, THE Backend_API SHALL return only relationships for which that User is the follower.
3. WHEN a User requests to unfollow an account, THE Backend_API SHALL remove the matching directed Follow relationship.
4. IF a User attempts to follow their own account, THEN THE Backend_API SHALL reject the request.
5. WHEN the Backend_API returns activity logs to a User, THE Backend_API SHALL include public logs from followed accounts and SHALL exclude private logs owned by other Users.
6. WHEN the Backend_API evaluates a friends-only log, THE Backend_API SHALL return the log only to an audience authorized by the product's friends-only access policy.

### Requirement 7: Paginated Social Feed

**User Story:** As a User, I want a paginated feed of activity from accounts I follow, so that I can review social productivity updates.

#### Acceptance Criteria

1. WHEN an authenticated User requests the Social_Feed without a page size, THE Backend_API SHALL return at most 20 feed entries.
2. WHEN an authenticated User requests the Social_Feed with a valid cursor and page size, THE Backend_API SHALL return entries older than the cursor and SHALL return no more than the requested page size.
3. WHEN the Backend_API returns a Social_Feed page, THE Backend_API SHALL hydrate each entry with its Activity_Log fields, author profile fields, and category summaries permitted by visibility rules.
4. WHEN a public Activity_Log is created, THE Backend_API SHALL make the log eligible for inclusion in the Social_Feed of each follower of its author.
5. IF the Social_Feed contains no eligible entries, THEN THE Backend_API SHALL return an empty page with a valid pagination response.
6. IF a feed cache entry is missing or stale, THEN THE Backend_API SHALL obtain feed results from durable records and return results consistent with visibility rules.

### Requirement 8: Data Integrity and Deletion

**User Story:** As a User, I want my records and relationships to remain consistent when accounts or records are removed, so that deleted data does not leave invalid references.

#### Acceptance Criteria

1. THE Backend_API SHALL assign each User, Activity_Log, Category, and Follow relationship a stable unique identifier or composite key as defined by the data model.
2. WHEN a User account is deleted, THE Backend_API SHALL delete that User's Activity_Logs, Categories, and Follow relationships.
3. WHEN an Activity_Log is deleted, THE Backend_API SHALL delete its category associations.
4. WHEN a Category is deleted, THE Backend_API SHALL remove associations between the Category and Activity_Logs.
5. WHEN the Backend_API stores an Activity_Log duration, THE Backend_API SHALL derive duration from its start and end timestamps.
6. THE Backend_API SHALL enforce uniqueness of usernames, emails, and Idempotency_Keys.

### Requirement 9: API Contract and Service Operation

**User Story:** As an iOS client developer, I want stable, validated API endpoints, so that the application can exchange account, log, and feed data predictably.

#### Acceptance Criteria

1. THE Backend_API SHALL expose versioned endpoints for authentication, profile and category operations, activity log ingestion, follow management, and feed retrieval under `/api/v1`.
2. WHEN the Backend_API receives an invalid request payload or query parameter, THE Backend_API SHALL return a structured client error response identifying the invalid input category.
3. WHEN an unexpected server error occurs, THE Backend_API SHALL log diagnostic details and return a generic server error response that excludes secrets and internal stack traces.
4. THE Backend_API SHALL load database, cache, JWT signing, and service port configuration from environment configuration rather than hard-coded credentials.
5. WHEN the Backend_API starts without required configuration or cannot connect to a required service, THE Backend_API SHALL fail startup with a diagnostic log that identifies the unavailable configuration or dependency without exposing secret values.

### Requirement 10: Offline Synchronization Recovery

**User Story:** As an iOS user, I want queued activity records to sync when connectivity returns, so that temporary offline periods do not lose completed work.

#### Acceptance Criteria

1. WHEN network connectivity becomes available, THE iOS_Client SHALL schedule synchronization of pending Offline_Queue records.
2. WHEN synchronization is interrupted after the Backend_API commits a log but before the iOS_Client receives the response, THE iOS_Client SHALL retry with the same Idempotency_Key.
3. WHEN the Backend_API acknowledges a retried log, THE iOS_Client SHALL reconcile the local record with the existing server log and mark the local record synchronized.
4. IF synchronization of one queued log fails, THEN THE iOS_Client SHALL continue processing other queued logs and retain the failed log for retry.
5. THE iOS_Client SHALL preserve locally stored Activity_Logs across application relaunches and device network state changes.

## Out of Scope

- Supabase Auth. The product uses username/password authentication with JWT in this version.
- Implementing the native iOS application before the user explicitly chooses to begin implementation. These requirements define the full target platform.
- Direct messaging, comments, reactions, teams, and collaborative projects, which are not specified in the architecture brief.
- Analytics dashboards beyond daily and weekly totals in the Productivity_Widget.
