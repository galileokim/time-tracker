import Foundation

public struct ProductivitySummary: Equatable, Sendable {
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let categorySeconds: [UUID: Int]

    public init(logs: [LocalActivityLog], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        var todayTotal = 0
        var weekTotal = 0
        var byCategory: [UUID: Int] = [:]

        for log in logs where log.syncState == .synced {
            let seconds = log.durationSeconds
            if log.endedAt >= today {
                todayTotal += seconds
            }
            if log.endedAt >= week {
                weekTotal += seconds
                for categoryID in Set(log.categoryIDs) {
                    byCategory[categoryID, default: 0] += seconds
                }
            }
        }

        todaySeconds = todayTotal
        weekSeconds = weekTotal
        categorySeconds = byCategory
    }
}
