import Foundation

public struct ProductivitySummaryLog: Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let categoryIDs: [UUID]

    public init(startedAt: Date, endedAt: Date, categoryIDs: [UUID]) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.categoryIDs = categoryIDs
    }

    public var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

public struct ProductivitySummary: Equatable, Sendable {
    public let allTimeSeconds: Int
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let categorySeconds: [UUID: Int]

    public init(logs: [ProductivitySummaryLog], now: Date = .now, calendar: Calendar = .current) {
        let todayInterval = calendar.dateInterval(of: .day, for: now)
        let today = todayInterval?.start ?? calendar.startOfDay(for: now)
        let tomorrow = todayInterval?.end ?? calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let week = weekInterval?.start ?? today
        let nextWeek = weekInterval?.end ?? tomorrow
        var allTimeTotal = 0
        var todayTotal = 0
        var weekTotal = 0
        var byCategory: [UUID: Int] = [:]

        for log in logs {
            guard log.endedAt >= log.startedAt else { continue }
            let duration = log.endedAt.timeIntervalSince(log.startedAt)
            allTimeTotal += Int(duration)

            let todayOverlapStart = max(log.startedAt, today)
            let todayOverlapEnd = min(log.endedAt, tomorrow)
            let todayOverlap = max(0, todayOverlapEnd.timeIntervalSince(todayOverlapStart))
            todayTotal += Int(todayOverlap)

            let weekOverlapStart = max(log.startedAt, week)
            let weekOverlapEnd = min(log.endedAt, nextWeek)
            let weekOverlap = max(0, weekOverlapEnd.timeIntervalSince(weekOverlapStart))
            if weekOverlap > 0 {
                let overlappingSeconds = Int(weekOverlap)
                weekTotal += overlappingSeconds
                for categoryID in Set(log.categoryIDs) {
                    byCategory[categoryID, default: 0] += overlappingSeconds
                }
            }
        }

        allTimeSeconds = allTimeTotal
        todaySeconds = todayTotal
        weekSeconds = weekTotal
        categorySeconds = byCategory
    }
}
