import Foundation

public protocol LogSyncAPI: Sendable {
    func createLog(_ log: LocalActivityLog) async throws -> UUID
}

struct TokenizedLogSyncAPI: LogSyncAPI {
    let client: TrackerAPIClient
    let token: String

    func createLog(_ log: LocalActivityLog) async throws -> UUID {
        try await client.createLog(log, accessToken: token).id
    }
}

public struct SyncReport: Equatable, Sendable {
    public var syncedKeys: [UUID]
    public var failedKeys: [UUID]

    public init(syncedKeys: [UUID] = [], failedKeys: [UUID] = []) {
        self.syncedKeys = syncedKeys
        self.failedKeys = failedKeys
    }
}

@MainActor
public struct LogSyncCoordinator {
    public init() {}

    public func synchronize(
        logs: [LocalActivityLog],
        api: any LogSyncAPI,
        acknowledge: (UUID, UUID) throws -> Void,
        recordFailure: (UUID, String) -> Void
    ) async -> SyncReport {
        var report = SyncReport()

        for log in logs {
            do {
                let serverID = try await api.createLog(log)
                try acknowledge(log.idempotencyKey, serverID)
                report.syncedKeys.append(log.idempotencyKey)
            } catch {
                recordFailure(log.idempotencyKey, error.localizedDescription)
                report.failedKeys.append(log.idempotencyKey)
            }
        }

        return report
    }
}

@MainActor
public final class OfflineSyncWorker {
    private let store: any TimerStoreProtocol
    private let api: TrackerAPIClient
    private let tokenProvider: @Sendable () async -> String?
    private let coordinator = LogSyncCoordinator()

    public init(
        store: any TimerStoreProtocol,
        api: TrackerAPIClient,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.store = store
        self.api = api
        self.tokenProvider = tokenProvider
    }

    public func synchronize() async throws -> SyncReport {
        guard let token = await tokenProvider() else { return SyncReport() }
        let queuedLogs = try store.pendingLogs()
        for log in queuedLogs {
            try store.markSyncing(idempotencyKey: log.idempotencyKey)
        }

        return await coordinator.synchronize(
            logs: queuedLogs,
            api: TokenizedLogSyncAPI(client: api, token: token),
            acknowledge: { idempotencyKey, serverID in
                try store.markSynced(idempotencyKey: idempotencyKey, serverID: serverID)
            },
            recordFailure: { idempotencyKey, message in
                try? store.recordAttempt(idempotencyKey: idempotencyKey, failure: message)
            }
        )
    }
}
