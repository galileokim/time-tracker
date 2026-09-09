import Foundation
import Testing
@testable import TimeTrackerCore

struct ProductivitySummaryTests {
    @Test func totalsIncludeOnlySyncedLogsWithinCalendarPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-02-11T12:00:00Z")
        let categoryA = UUID()
        let categoryB = UUID()
        let logs = [
            log(start: "2026-02-11T09:00:00Z", end: "2026-02-11T10:00:00Z", categories: [categoryA, categoryB]),
            log(start: "2026-02-09T09:00:00Z", end: "2026-02-09T10:30:00Z", categories: [categoryA]),
            log(start: "2026-02-01T09:00:00Z", end: "2026-02-01T10:00:00Z", categories: [categoryB]),
            log(start: "2026-02-11T10:00:00Z", end: "2026-02-11T11:00:00Z", categories: [], syncState: .pending),
        ]

        let summary = ProductivitySummary(logs: logs, now: now, calendar: calendar)

        #expect(summary.todaySeconds == 3_600)
        #expect(summary.weekSeconds == 9_000)
        #expect(summary.categorySeconds[categoryA] == 9_000)
        #expect(summary.categorySeconds[categoryB] == 3_600)
    }

    private func log(
        start: String,
        end: String,
        categories: [UUID],
        syncState: LocalSyncState = .synced
    ) -> LocalActivityLog {
        LocalActivityLog(
            title: "Activity",
            notes: nil,
            startedAt: date(start),
            endedAt: date(end),
            categoryIDs: categories,
            visibility: .private,
            syncState: syncState
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
