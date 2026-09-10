import Foundation

public struct ProductivitySummaryLog: Equatable, Sendable {
    public let endedAt: Date
    public let durationSeconds: Int
    public let categoryIDs: [UUID]

    public init(endedAt: Date, durationSeconds: Int, categoryIDs: [UUID]) {
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.categoryIDs = categoryIDs
    }
}

public struct ProductivitySummary: Equatable, Sendable {
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let categorySeconds: [UUID: Int]

    public init(logs: [ProductivitySummaryLog], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        var todayTotal = 0
        var weekTotal = 0
        var byCategory: [UUID: Int] = [:]

        for log in logs {
            guard log.durationSeconds >= 0 else { continue }
            if log.endedAt >= today {
                todayTotal += log.durationSeconds
            }
            if log.endedAt >= week {
                weekTotal += log.durationSeconds
                for categoryID in Set(log.categoryIDs) {
                    byCategory[categoryID, default: 0] += log.durationSeconds
                }
            }
        }

        todaySeconds = todayTotal
        weekSeconds = weekTotal
        categorySeconds = byCategory
    }
}
