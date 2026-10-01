import Foundation

public struct WidgetTimelineEntry: Equatable, Sendable {
    public let date: Date
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let updatedAt: Date?

    public init(date: Date, snapshot: WidgetSummarySnapshot?) {
        self.date = date
        todaySeconds = snapshot?.todaySeconds ?? 0
        weekSeconds = snapshot?.weekSeconds ?? 0
        updatedAt = snapshot?.updatedAt
    }

    public var promptsToOpenApp: Bool {
        updatedAt == nil
    }
}
