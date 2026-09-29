import Foundation
import SwiftData
import Testing
@testable import TimeTrackerCore

@Suite(.serialized)
@MainActor
struct SwiftDataTimerStoreTests {
    @Test func restoresTimersAndScopesPersistedLogsByAccount() throws {
        let userA = UUID()
        let userB = UUID()
        let container = try makeContainer()
        let contextA = ModelContext(container)
        let storeA = SwiftDataTimerStore(modelContext: contextA)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let categoryID = UUID()

        let timer = try storeA.start(
            userID: userA,
            title: "Deep work",
            notes: "Offline",
            categoryIDs: [categoryID],
            visibility: .friendsOnly,
            startedAt: startedAt
        )
        let restored = try SwiftDataTimerStore(modelContext: ModelContext(container)).currentTimer(userID: userA)
        #expect(restored == timer)
        #expect(try storeA.currentTimer(userID: userB) == nil)

        let log = try storeA.stop(timerID: timer.id, userID: userA, endedAt: startedAt.addingTimeInterval(600))
        #expect(log.userID == userA)
        #expect(log.categoryIDs == [categoryID])
        #expect(log.visibility == .friendsOnly)
        #expect(try storeA.pendingLogs(userID: userA).map(\.id) == [log.id])
        #expect(try storeA.pendingLogs(userID: userB).isEmpty)
        #expect(try storeA.completedLogs(userID: userA).isEmpty)
    }

    @Test func pendingLogSurvivesPersistentStoreReopen() throws {
        let userID = UUID()
        let storeURL = FileManager.default.temporaryDirectory.appending(path: "timer-store-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(atPath: storeURL.path + "-shm")
            try? FileManager.default.removeItem(atPath: storeURL.path + "-wal")
        }
        let idempotencyKey = try createPendingLogInPersistentStore(userID: userID, storeURL: storeURL)
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        let reopenedStore = SwiftDataTimerStore(modelContext: ModelContext(reopened))
        let pending = try reopenedStore.pendingLogs(userID: userID)

        #expect(pending.map(\.idempotencyKey) == [idempotencyKey])
        #expect(pending[0].userID == userID)
        #expect(pending[0].title == "Durable")
        #expect(pending[0].retryCount == 0)
    }

    @Test func legacyUnownedTimerBlocksStartingAnotherAccountTimer() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let legacyTimer = RunningTimer(title: "Legacy", startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        context.insert(try StoredTimer(timer: legacyTimer))
        try context.save()

        let store = SwiftDataTimerStore(modelContext: context)
        #expect(throws: TimerStoreError.legacyTimerNeedsReview) {
            try store.start(userID: UUID(), title: "New account", notes: nil, categoryIDs: [], visibility: .private, startedAt: .now)
        }
    }

    private func createPendingLogInPersistentStore(userID: UUID, storeURL: URL) throws -> UUID {
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        let store = SwiftDataTimerStore(modelContext: ModelContext(container))
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = try store.start(userID: userID, title: "Durable", notes: "Restart", categoryIDs: [], visibility: .private, startedAt: startedAt)
        let log = try store.stop(timerID: timer.id, userID: userID, endedAt: startedAt.addingTimeInterval(90))
        return log.idempotencyKey
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
