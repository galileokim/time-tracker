import Foundation

public struct WidgetSummarySnapshot: Equatable, Sendable {
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let updatedAt: Date

    public init(todaySeconds: Int, weekSeconds: Int, updatedAt: Date) {
        self.todaySeconds = todaySeconds
        self.weekSeconds = weekSeconds
        self.updatedAt = updatedAt
    }
}

public enum WidgetSummaryStorage {
    public static let activeUserIDKey = "productivity.activeUserID"
    public static let sharedGroupID = "group.com.galileotimetracker.app"

    public static func storageKeys(for userID: UUID) -> (today: String, week: String, updatedAt: String) {
        let prefix = "productivity.\(userID.uuidString)."
        return (prefix + "todaySeconds", prefix + "weekSeconds", prefix + "updatedAt")
    }

    public static func activeSnapshot(from defaults: UserDefaults?) -> WidgetSummarySnapshot? {
        guard let defaults,
              let userIDString = defaults.string(forKey: activeUserIDKey),
              let userID = UUID(uuidString: userIDString) else { return nil }
        let keys = storageKeys(for: userID)
        guard let updatedAt = defaults.object(forKey: keys.updatedAt) as? Double else { return nil }
        return WidgetSummarySnapshot(
            todaySeconds: defaults.integer(forKey: keys.today),
            weekSeconds: defaults.integer(forKey: keys.week),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    public static func publish(_ summary: ProductivitySummary, for userID: UUID, to defaults: UserDefaults?, updatedAt: Date = .now) {
        guard let defaults else { return }
        let keys = storageKeys(for: userID)
        defaults.set(summary.todaySeconds, forKey: keys.today)
        defaults.set(summary.weekSeconds, forKey: keys.week)
        defaults.set(updatedAt.timeIntervalSince1970, forKey: keys.updatedAt)
        defaults.set(userID.uuidString, forKey: activeUserIDKey)
        defaults.synchronize()
    }

    public static func clearActiveUser(from defaults: UserDefaults?) {
        defaults?.removeObject(forKey: activeUserIDKey)
        defaults?.synchronize()
    }
}
