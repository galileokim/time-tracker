import Foundation

public enum ActivityVisibility: String, Codable, CaseIterable, Sendable {
    case `public`
    case `private`
    case friendsOnly = "friends_only"
}

public enum LocalSyncState: String, Codable, Sendable {
    case running
    case pending
    case syncing
    case synced
}

public struct RunningTimer: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var categoryIDs: [UUID]
    public var visibility: ActivityVisibility
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        categoryIDs: [UUID] = [],
        visibility: ActivityVisibility = .public,
        startedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.categoryIDs = categoryIDs
        self.visibility = visibility
        self.startedAt = startedAt
    }

    public func elapsedSeconds(at date: Date = .now) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }
}

public struct LocalActivityLog: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let idempotencyKey: UUID
    public var title: String
    public var notes: String?
    public var startedAt: Date
    public var endedAt: Date
    public var categoryIDs: [UUID]
    public var visibility: ActivityVisibility
    public var syncState: LocalSyncState
    public var serverID: UUID?
    public var retryCount: Int
    public var lastSyncError: String?

    public init(
        id: UUID = UUID(),
        idempotencyKey: UUID = UUID(),
        title: String,
        notes: String?,
        startedAt: Date,
        endedAt: Date,
        categoryIDs: [UUID],
        visibility: ActivityVisibility,
        syncState: LocalSyncState = .pending,
        serverID: UUID? = nil,
        retryCount: Int = 0,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.title = title
        self.notes = notes
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.categoryIDs = categoryIDs
        self.visibility = visibility
        self.syncState = syncState
        self.serverID = serverID
        self.retryCount = retryCount
        self.lastSyncError = lastSyncError
    }

    public var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}
