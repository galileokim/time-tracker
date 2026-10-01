import Foundation
import Testing
@testable import TimeTrackerCore

struct WidgetTimelineEntryTests {
    @Test func populatedSnapshotProvidesTotalsAndTimestamp() {
        let date = Date(timeIntervalSince1970: 100)
        let snapshot = WidgetSummarySnapshot(todaySeconds: 3_600, weekSeconds: 10_800, updatedAt: date)

        let entry = WidgetTimelineEntry(date: date.addingTimeInterval(60), snapshot: snapshot)

        #expect(entry.todaySeconds == 3_600)
        #expect(entry.weekSeconds == 10_800)
        #expect(entry.updatedAt == date)
        #expect(!entry.promptsToOpenApp)
    }

    @Test func missingSnapshotProducesHonestEmptyState() {
        let entry = WidgetTimelineEntry(date: Date(timeIntervalSince1970: 100), snapshot: nil)

        #expect(entry.todaySeconds == 0)
        #expect(entry.weekSeconds == 0)
        #expect(entry.updatedAt == nil)
        #expect(entry.promptsToOpenApp)
    }
}
