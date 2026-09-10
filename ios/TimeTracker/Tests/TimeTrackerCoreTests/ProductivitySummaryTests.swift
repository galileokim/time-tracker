import Foundation
import Testing
@testable import TimeTrackerCore

struct ProductivitySummaryTests {
    @Test func sharedSummaryModelCalculatesCalendarTotals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-02-11T12:00:00Z")
        let categoryID = UUID()
        let summary = ProductivitySummary(logs: [
            ProductivitySummaryLog(endedAt: date("2026-02-11T10:00:00Z"), durationSeconds: 3_600, categoryIDs: [categoryID]),
            ProductivitySummaryLog(endedAt: date("2026-02-09T10:30:00Z"), durationSeconds: 5_400, categoryIDs: [categoryID]),
        ], now: now, calendar: calendar)

        #expect(summary.todaySeconds == 3_600)
        #expect(summary.weekSeconds == 9_000)
        #expect(summary.categorySeconds[categoryID] == 9_000)
    }

    @Test func totalsIncludeOnlySyncedLogsWithinCalendarPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-02-11T12:00:00Z")
        let categoryA = UUID()
        let categoryB = UUID()
        let logs = [
            summaryLog(start: "2026-02-11T09:00:00Z", end: "2026-02-11T10:00:00Z", categories: [categoryA, categoryB]),
            summaryLog(start: "2026-02-09T09:00:00Z", end: "2026-02-09T10:30:00Z", categories: [categoryA]),
            summaryLog(start: "2026-02-01T09:00:00Z", end: "2026-02-01T10:00:00Z", categories: [categoryB]),
        ]

        let summary = ProductivitySummary(logs: logs, now: now, calendar: calendar)

        #expect(summary.todaySeconds == 3_600)
        #expect(summary.weekSeconds == 9_000)
        #expect(summary.categorySeconds[categoryA] == 9_000)
        #expect(summary.categorySeconds[categoryB] == 3_600)
    }

    private func summaryLog(start: String, end: String, categories: [UUID]) -> ProductivitySummaryLog {
        let startedAt = date(start)
        let endedAt = date(end)
        return ProductivitySummaryLog(
            endedAt: endedAt,
            durationSeconds: Int(endedAt.timeIntervalSince(startedAt)),
            categoryIDs: categories
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
