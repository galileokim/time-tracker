import Foundation
import Testing
@testable import TimeTrackerCore

@Suite(.serialized)
@MainActor
struct SyncWorkerTests {
    @Test func acknowledgementPersistenceFailureRecordsRetryAndContinues() async {
        let logs = [makeLog(title: "first"), makeLog(title: "second")]
        let api = StubLogSyncAPI(failingKey: nil)
        let acknowledged = LockedValues<UUID>()
        let failures = LockedValues<UUID>()
        let report = await LogSyncCoordinator().synchronize(
            logs: logs,
            api: api,
            acknowledge: { key, _ in
                if key == logs[0].idempotencyKey { throw APIClientError.invalidResponse }
                acknowledged.append(key)
            },
            recordFailure: { key, _ in failures.append(key) }
        )

        #expect(report.failedKeys == [logs[0].idempotencyKey])
        #expect(report.syncedKeys == [logs[1].idempotencyKey])
        #expect(failures.values == [logs[0].idempotencyKey])
        #expect(acknowledged.values == [logs[1].idempotencyKey])
    }

    @Test func syncContinuesAfterFailureAndPreservesIdempotencyKeys() async {
        let logs = [
            makeLog(title: "first"),
            makeLog(title: "second"),
            makeLog(title: "third"),
        ]
        let failingKey = logs[1].idempotencyKey
        let api = StubLogSyncAPI(failingKey: failingKey)
        let acknowledged = LockedValues<(UUID, UUID)>()
        let failures = LockedValues<(UUID, String)>()
        let coordinator = LogSyncCoordinator()

        let report = await coordinator.synchronize(
            logs: logs,
            api: api,
            acknowledge: { key, serverID in acknowledged.append((key, serverID)) },
            recordFailure: { key, message in failures.append((key, message)) }
        )

        #expect(report.syncedKeys == [logs[0].idempotencyKey, logs[2].idempotencyKey])
        #expect(report.failedKeys == [failingKey])
        #expect(acknowledged.values.map(\.0) == report.syncedKeys)
        #expect(failures.values.map(\.0) == [failingKey])
        #expect(api.receivedKeys == logs.map(\.idempotencyKey))
    }

    private func makeLog(title: String) -> LocalActivityLog {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return LocalActivityLog(
            idempotencyKey: UUID(),
            title: title,
            notes: nil,
            startedAt: start,
            endedAt: start.addingTimeInterval(30),
            categoryIDs: [],
            visibility: .public
        )
    }
}

private struct StubLogSyncAPI: LogSyncAPI {
    let failingKey: UUID?
    private let received = LockedValues<UUID>()

    var receivedKeys: [UUID] { received.values }

    func createLog(_ log: LocalActivityLog) async throws -> UUID {
        received.append(log.idempotencyKey)
        if log.idempotencyKey == failingKey {
            throw APIClientError.server(statusCode: 503, code: "SERVICE_UNAVAILABLE")
        }
        return UUID()
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
