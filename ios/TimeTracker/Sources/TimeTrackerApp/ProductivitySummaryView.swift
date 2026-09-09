import SwiftUI

struct ProductivitySummaryView: View {
    let summary: ProductivitySummary
    let categories: [APICategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time recorded")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                total(title: "Today", seconds: summary.todaySeconds)
                total(title: "This week", seconds: summary.weekSeconds)
            }
            if !summary.categorySeconds.isEmpty {
                Divider()
                ForEach(summary.categorySeconds.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { categoryID in
                    HStack {
                        Text(categoryName(for: categoryID))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Duration.seconds(summary.categorySeconds[categoryID] ?? 0), format: .time(pattern: .hourMinute))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func total(title: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Duration.seconds(seconds), format: .time(pattern: .hourMinute))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }
}