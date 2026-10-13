import SwiftUI
import WidgetKit

struct ProductivityWidgetEntry: TimelineEntry {
    let summary: WidgetTimelineEntry
    var date: Date { summary.date }
}

struct ProductivityWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProductivityWidgetEntry {
        ProductivityWidgetEntry(summary: WidgetTimelineEntry(date: .now, snapshot: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProductivityWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductivityWidgetEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func readEntry() -> ProductivityWidgetEntry {
        let snapshot = WidgetSummaryStorage.activeSnapshot(from: UserDefaults(suiteName: WidgetSummaryStorage.sharedGroupID))
        return ProductivityWidgetEntry(summary: WidgetTimelineEntry(date: .now, snapshot: snapshot))
    }
}

struct ProductivityWidget: Widget {
    let kind = "ProductivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityWidgetProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                Text("Time Tracker")
                    .font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    total(title: "Today", seconds: entry.summary.todaySeconds)
                    total(title: "This week", seconds: entry.summary.weekSeconds)
                }
                Spacer(minLength: 0)
                if let updatedAt = entry.summary.updatedAt {
                    Text("Updated \(updatedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open the app to record time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Time recorded")
        .description("See your recorded time for today and this week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private func total(title: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AnalyticsDurationFormatter.format(seconds, includesDays: false))
                .font(.caption.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
    }
}

@main
struct TimeTrackerWidgets: WidgetBundle {
    var body: some Widget {
        ProductivityWidget()
    }
}
