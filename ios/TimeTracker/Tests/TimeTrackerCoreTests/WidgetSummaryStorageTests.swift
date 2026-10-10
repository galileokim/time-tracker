import Foundation
import Testing
@testable import TimeTrackerCore

struct WidgetSummaryStorageTests {
    @Test func snapshotFollowsActiveAccountAndClearsOnSignOut() {
        let suiteName = "WidgetSummaryStorageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUser = UUID()
        let secondUser = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_800_000_100)

        WidgetSummaryStorage.publish(summary(today: 600, week: 1200, now: firstDate), for: firstUser, to: defaults, updatedAt: firstDate)
        #expect(WidgetSummaryStorage.activeSnapshot(from: defaults)?.todaySeconds == 600)

        WidgetSummaryStorage.publish(summary(today: 60, week: 300, now: secondDate), for: secondUser, to: defaults, updatedAt: secondDate)
        let current = WidgetSummaryStorage.activeSnapshot(from: defaults)
        #expect(current?.todaySeconds == 60)
        #expect(current?.weekSeconds == 300)
        #expect(current?.updatedAt == secondDate)

        WidgetSummaryStorage.clearActiveUser(from: defaults)
        #expect(WidgetSummaryStorage.activeSnapshot(from: defaults) == nil)
    }

    @Test func summaryKeysAreDifferentForDifferentAccounts() {
        let first = WidgetSummaryStorage.storageKeys(for: UUID())
        let second = WidgetSummaryStorage.storageKeys(for: UUID())
        #expect(first.today != second.today)
        #expect(first.week != second.week)
    }

    private func summary(today: Int, week: Int, now: Date) -> ProductivitySummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        return ProductivitySummary(logs: [
            ProductivitySummaryLog(startedAt: now.addingTimeInterval(-Double(today)), endedAt: now, categoryIDs: []),
            ProductivitySummaryLog(startedAt: yesterday.addingTimeInterval(-Double(week - today)), endedAt: yesterday, categoryIDs: []),
        ], now: now, calendar: calendar)
    }
}
