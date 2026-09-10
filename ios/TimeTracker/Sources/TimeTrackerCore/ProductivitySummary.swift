import Foundation

public extension LocalActivityLog {
    var productivitySummaryLog: ProductivitySummaryLog {
        ProductivitySummaryLog(endedAt: endedAt, durationSeconds: durationSeconds, categoryIDs: categoryIDs)
    }
}
