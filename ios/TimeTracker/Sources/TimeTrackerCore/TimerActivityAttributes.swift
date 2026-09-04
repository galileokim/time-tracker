import ActivityKit
import Foundation

public struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date
        public var activityTitle: String

        public init(startedAt: Date, activityTitle: String) {
            self.startedAt = startedAt
            self.activityTitle = activityTitle
        }
    }

    public var timerID: UUID

    public init(timerID: UUID) {
        self.timerID = timerID
    }
}
