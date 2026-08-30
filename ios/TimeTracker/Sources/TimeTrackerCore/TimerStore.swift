import Foundation
import SwiftData

@Model
public final class StoredTimer {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String?
    public var categoryIDsData: Data
    public var visibilityRawValue: String
    public var startedAt: Date

    public init(timer: RunningTimer) throws {
        id = timer.id
        title = timer.title
        notes = timer.notes
        categoryIDsData = try JSONEncoder().encode(timer.categoryIDs)
        visibilityRawValue = timer.visibility.rawValue
        startedAt = timer.startedAt
    }

    public var runningTimer: RunningTimer? {
        guard
            let categoryIDs = try? JSONDecoder().decode([UUID].self, from: categoryIDsData),
            let visibility = ActivityVisibility(rawValue: visibilityRawValue)
        else {
            return nil
        }

        return RunningTimer(
            id: id,
            title: title,
            notes: notes,
            categoryIDs: categoryIDs,
            visibility: visibility,
            startedAt: startedAt
        )
    }
}

@Model
public final class StoredActivityLog {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var idempotencyKey: UUID
    public var title: String
    public var notes: String?
    public var startedAt: Date
    public var endedAt: Date
    public var categoryIDsData: Data
    public var visibilityRawValue: String
    public var syncStateRawValue: String
    public var serverID: UUID?
    public var retryCount: Int
    public var lastSyncError: String?

    public init(log: LocalActivityLog) throws {
        id = log.id
        idempotencyKey = log.idempotencyKey
        title = log.title
        notes = log.notes
        startedAt = log.startedAt
        endedAt = log.endedAt
        categoryIDsData = try JSONEncoder().encode(log.categoryIDs)
        visibilityRawValue = log.visibility.rawValue
        syncStateRawValue = log.syncState.rawValue
        serverID = log.serverID
        retryCount = log.retryCount
        lastSyncError = log.lastSyncError
    }

    public var activityLog: LocalActivityLog? {
        guard
            let categoryIDs = try? JSONDecoder().decode([UUID].self, from: categoryIDsData),
            let visibility = ActivityVisibility(rawValue: visibilityRawValue),
            let syncState = LocalSyncState(rawValue: syncStateRawValue)
        else {
            return nil
        }

        return LocalActivityLog(
            id: id,
            idempotencyKey: idempotencyKey,
            title: title,
            notes: notes,
            startedAt: startedAt,
            endedAt: endedAt,
            categoryIDs: categoryIDs,
            visibility: visibility,
            syncState: syncState,
            serverID: serverID,
            retryCount: retryCount,
            lastSyncError: lastSyncError
        )
    }
}

public enum TimerStoreError: Error, Equatable {
    case timerAlreadyRunning
    case noRunningTimer
    case timerNotFound
    case invalidStoredTimer
    case invalidStoredLog
    case invalidTimeRange
}

@MainActor
public protocol TimerStoreProtocol {
    func start(
        title: String,
        notes: String?,
        categoryIDs: [UUID],
        visibility: ActivityVisibility,
        startedAt: Date
    ) throws -> RunningTimer
    func stop(timerID: UUID, endedAt: Date) throws -> LocalActivityLog
    func currentTimer() throws -> RunningTimer?
    func pendingLogs() throws -> [LocalActivityLog]
    func updatePendingLog(idempotencyKey: UUID, title: String, notes: String?, categoryIDs: [UUID], visibility: ActivityVisibility) throws
    func markSynced(idempotencyKey: UUID, serverID: UUID) throws
    func recordAttempt(idempotencyKey: UUID, failure: String) throws
}

@MainActor
public final class SwiftDataTimerStore: TimerStoreProtocol {
    private let modelContext: ModelContext
    private let engine: TimerEngine

    public init(modelContext: ModelContext, engine: TimerEngine = TimerEngine()) {
        self.modelContext = modelContext
        self.engine = engine
    }

    public func start(
        title: String,
        notes: String? = nil,
        categoryIDs: [UUID] = [],
        visibility: ActivityVisibility = .public,
        startedAt: Date = .now
    ) throws -> RunningTimer {
        let timer = try engine.start(
            existing: currentTimer(),
            title: title,
            notes: notes,
            categoryIDs: categoryIDs,
            visibility: visibility,
            at: startedAt
        )
        modelContext.insert(try StoredTimer(timer: timer))
        try modelContext.save()
        return timer
    }

    public func stop(timerID: UUID, endedAt: Date = .now) throws -> LocalActivityLog {
        let descriptor = FetchDescriptor<StoredTimer>(
            predicate: #Predicate { $0.id == timerID }
        )
        guard let storedTimer = try modelContext.fetch(descriptor).first else {
            throw TimerStoreError.timerNotFound
        }
        guard let timer = storedTimer.runningTimer else {
            throw TimerStoreError.invalidStoredTimer
        }
        let log = try engine.stop(timer: timer, at: endedAt)
        modelContext.insert(try StoredActivityLog(log: log))
        modelContext.delete(storedTimer)
        try modelContext.save()
        return log
    }

    public func currentTimer() throws -> RunningTimer? {
        var descriptor = FetchDescriptor<StoredTimer>(sortBy: [SortDescriptor(\.startedAt)] )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return nil }
        guard let timer = stored.runningTimer else { throw TimerStoreError.invalidStoredTimer }
        return timer
    }

    public func pendingLogs() throws -> [LocalActivityLog] {
        let descriptor = FetchDescriptor<StoredActivityLog>(
            predicate: #Predicate { $0.syncStateRawValue == "pending" || $0.syncStateRawValue == "syncing" },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try modelContext.fetch(descriptor).compactMap { stored in
            guard let log = stored.activityLog else { throw TimerStoreError.invalidStoredLog }
            if log.syncState == .syncing {
                var retryable = log
                retryable.syncState = .pending
                return retryable
            }
            return log
        }
    }

    public func updatePendingLog(
        idempotencyKey: UUID,
        title: String,
        notes: String?,
        categoryIDs: [UUID],
        visibility: ActivityVisibility
    ) throws {
        guard let stored = try storedLog(idempotencyKey: idempotencyKey), stored.syncStateRawValue == LocalSyncState.pending.rawValue else {
            throw TimerStoreError.invalidStoredLog
        }
        stored.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        stored.notes = notes
        stored.categoryIDsData = try JSONEncoder().encode(categoryIDs)
        stored.visibilityRawValue = visibility.rawValue
        try modelContext.save()
    }

    public func markSynced(idempotencyKey: UUID, serverID: UUID) throws {
        guard let stored = try storedLog(idempotencyKey: idempotencyKey) else {
            throw TimerStoreError.invalidStoredLog
        }
        stored.syncStateRawValue = LocalSyncState.synced.rawValue
        stored.serverID = serverID
        stored.lastSyncError = nil
        try modelContext.save()
    }

    public func recordAttempt(idempotencyKey: UUID, failure: String) throws {
        guard let stored = try storedLog(idempotencyKey: idempotencyKey) else {
            throw TimerStoreError.invalidStoredLog
        }
        stored.syncStateRawValue = LocalSyncState.pending.rawValue
        stored.retryCount += 1
        stored.lastSyncError = failure
        try modelContext.save()
    }

    private func storedLog(idempotencyKey: UUID) throws -> StoredActivityLog? {
        let descriptor = FetchDescriptor<StoredActivityLog>(
            predicate: #Predicate { $0.idempotencyKey == idempotencyKey }
        )
        return try modelContext.fetch(descriptor).first
    }
}
