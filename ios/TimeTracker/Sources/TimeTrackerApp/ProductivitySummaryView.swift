import SwiftUI

struct ProductivitySummaryView: View {
    let summary: ProductivitySummary
    let hasRecordedLogs: Bool
    let categories: [APICategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded time")
                .font(.headline)
            if !hasRecordedLogs {
                Text("Completed timers will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    total(title: "All time", seconds: summary.allTimeSeconds, includesDays: true)
                    total(title: "Today", seconds: summary.todaySeconds, includesDays: false)
                    total(title: "This week", seconds: summary.weekSeconds, includesDays: false)
                }
                if !summary.categorySeconds.isEmpty {
                    Divider()
                    ForEach(summary.categorySeconds.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { categoryID in
                        HStack {
                            Text(categoryName(for: categoryID))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(AnalyticsDurationFormatter.format(summary.categorySeconds[categoryID] ?? 0, includesDays: false))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func total(title: String, seconds: Int, includesDays: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AnalyticsDurationFormatter.format(seconds, includesDays: includesDays))
                .font(.body.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
        }
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }
}