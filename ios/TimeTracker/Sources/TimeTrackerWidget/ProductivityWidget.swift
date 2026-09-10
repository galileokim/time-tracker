import SwiftUI
import WidgetKit

struct ProductivityWidgetEntry: TimelineEntry {
    let date: Date
    let todaySeconds: Int
    let weekSeconds: Int
    let updatedAt: Date?
}

struct ProductivityWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProductivityWidgetEntry {
        ProductivityWidgetEntry(date: .now, todaySeconds: 0, weekSeconds: 0, updatedAt: nil)
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
        let defaults = UserDefaults(suiteName: "group.com.timetracker.shared")
        return ProductivityWidgetEntry(
            date: .now,
            todaySeconds: defaults?.integer(forKey: "productivity.todaySeconds") ?? 0,
            weekSeconds: defaults?.integer(forKey: "productivity.weekSeconds") ?? 0,
            updatedAt: (defaults?.object(forKey: "productivity.updatedAt") as? Double).map { Date(timeIntervalSince1970: $0) }
        )
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
                    total(title: "Today", seconds: entry.todaySeconds)
                    total(title: "This week", seconds: entry.weekSeconds)
                }
                Spacer(minLength: 0)
                if let updatedAt = entry.updatedAt {
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
            Text(Duration.seconds(seconds), format: .time(pattern: .hourMinute))
                .font(.title3.weight(.semibold).monospacedDigit())
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
