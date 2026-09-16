import Foundation

@MainActor
public final class AccountScopedTimerStore: TimerStoreProtocol {
    private let store: any TimerStoreProtocol
    private let userID: UUID

    public init(store: any TimerStoreProtocol, userID: UUID) {
        self.store = store
        self.userID = userID
    }

    public func start(
        userID requestedUserID: UUID,
        title: String,
        notes: String?,
        categoryIDs: [UUID],
        visibility: ActivityVisibility,
        startedAt: Date
    ) throws -> RunningTimer {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        return try store.start(
            userID: userID,
            title: title,
            notes: notes,
            categoryIDs: categoryIDs,
            visibility: visibility,
            startedAt: startedAt
        )
    }

    public func stop(timerID: UUID, userID requestedUserID: UUID, endedAt: Date) throws -> LocalActivityLog {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        return try store.stop(timerID: timerID, userID: userID, endedAt: endedAt)
    }

    public func currentTimer(userID requestedUserID: UUID) throws -> RunningTimer? {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        return try store.currentTimer(userID: userID)
    }

    public func pendingLogs(userID requestedUserID: UUID) throws -> [LocalActivityLog] {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        return try store.pendingLogs(userID: userID)
    }

    public func completedLogs(userID requestedUserID: UUID) throws -> [LocalActivityLog] {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        return try store.completedLogs(userID: userID)
    }

    public func markSyncing(idempotencyKey: UUID, userID requestedUserID: UUID) throws {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        try store.markSyncing(idempotencyKey: idempotencyKey, userID: userID)
    }

    public func updatePendingLog(
        idempotencyKey: UUID,
        userID requestedUserID: UUID,
        title: String,
        notes: String?,
        categoryIDs: [UUID],
        visibility: ActivityVisibility
    ) throws {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        try store.updatePendingLog(
            idempotencyKey: idempotencyKey,
            userID: userID,
            title: title,
            notes: notes,
            categoryIDs: categoryIDs,
            visibility: visibility
        )
    }

    public func markSynced(idempotencyKey: UUID, userID requestedUserID: UUID, serverID: UUID) throws {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        try store.markSynced(idempotencyKey: idempotencyKey, userID: userID, serverID: serverID)
    }

    public func recordAttempt(idempotencyKey: UUID, userID requestedUserID: UUID, failure: String) throws {
        guard requestedUserID == userID else { throw TimerStoreError.accountMismatch }
        try store.recordAttempt(idempotencyKey: idempotencyKey, userID: userID, failure: failure)
    }
}
