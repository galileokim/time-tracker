import Foundation

public enum AnalyticsDurationFormatter {
    public static func format(_ seconds: Int, includesDays: Bool) -> String {
        let remaining = max(0, seconds)
        let days = remaining / 86_400
        let hours = includesDays ? (remaining % 86_400) / 3_600 : remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        var units: [String] = []

        if includesDays && days > 0 {
            units.append("\(days) \(days == 1 ? "day" : "days")")
        }
        if hours > 0 || (includesDays && days > 0) {
            units.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 || !units.isEmpty {
            units.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        units.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")

        return units.joined(separator: ", ")
    }
}
