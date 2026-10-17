import Foundation

public extension LocalActivityLog {
    var productivitySummaryLog: ProductivitySummaryLog {
        ProductivitySummaryLog(startedAt: startedAt, endedAt: endedAt, categoryIDs: categoryIDs)
    }
}
