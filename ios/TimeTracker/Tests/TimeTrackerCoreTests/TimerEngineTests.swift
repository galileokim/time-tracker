import Foundation
import Testing
@testable import TimeTrackerCore

struct TimerEngineTests {
    private let engine = TimerEngine()

    @Test func startsTimerWithPersistedStartDateAndTrimmedTitle() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = try engine.start(
            existing: nil,
            title: "  Deep work  ",
            notes: "Research",
            at: startedAt
        )

        #expect(timer.title == "Deep work")
        #expect(timer.startedAt == startedAt)
        #expect(timer.elapsedSeconds(at: startedAt.addingTimeInterval(90)) == 90)
    }

    @Test func startsTimerWithSelectedCategoriesAndVisibility() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let categoryIDs = [UUID(), UUID()]

        let timer = try engine.start(
            existing: nil,
            title: "Planning",
            notes: nil,
            categoryIDs: categoryIDs,
            visibility: .friendsOnly,
            at: startedAt
        )

        #expect(timer.categoryIDs == categoryIDs)
        #expect(timer.visibility == .friendsOnly)
    }

    @Test func refusesToStartSecondRunningTimer() {
        let timer = RunningTimer(title: "Existing", startedAt: Date(timeIntervalSince1970: 100))

        #expect(throws: TimerStoreError.timerAlreadyRunning) {
            try engine.start(existing: timer, title: "Second", at: Date(timeIntervalSince1970: 200))
        }
    }

    @Test func stoppingTimerCreatesPendingLogWithStableRetryKey() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let endedAt = startedAt.addingTimeInterval(1500)
        let categoryID = UUID()
        let timer = RunningTimer(
            title: "Writing",
            notes: "Draft",
            categoryIDs: [categoryID],
            visibility: .friendsOnly,
            startedAt: startedAt
        )

        let log = try engine.stop(timer: timer, at: endedAt)

        #expect(log.title == "Writing")
        #expect(log.startedAt == startedAt)
        #expect(log.endedAt == endedAt)
        #expect(log.durationSeconds == 1500)
        #expect(log.categoryIDs == [categoryID])
        #expect(log.visibility == .friendsOnly)
        #expect(log.syncState == .pending)
        #expect(log.idempotencyKey != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test func rejectsEndDateBeforeStartDate() {
        let timer = RunningTimer(title: "Writing", startedAt: Date(timeIntervalSince1970: 200))

        #expect(throws: TimerStoreError.invalidTimeRange) {
            try engine.stop(timer: timer, at: Date(timeIntervalSince1970: 100))
        }
    }

    @Test func stoppingWithoutRunningTimerReturnsError() {
        #expect(throws: TimerStoreError.noRunningTimer) {
            try engine.stop(timer: nil, at: Date())
        }
    }
}
