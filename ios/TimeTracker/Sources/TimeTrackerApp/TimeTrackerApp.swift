import SwiftData
import SwiftUI

@main
struct TimeTrackerApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([StoredTimer.self, StoredActivityLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
            TimerHomeView()
                .modelContainer(container)
        }
    }
}

@MainActor
@Observable
final class TimerHomeModel {
    private let modelContext: ModelContext
    private let engine = TimerEngine()
    private(set) var runningTimer: RunningTimer?
    private(set) var pendingLogCount = 0
    var title = ""
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    func start(at date: Date = .now) {
        do {
            let timer = try engine.start(existing: runningTimer, title: title, notes: nil, categoryIDs: [], visibility: .public, at: date)
            modelContext.insert(try StoredTimer(timer: timer))
            try modelContext.save()
            runningTimer = timer
            title = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(at date: Date = .now) {
        guard let runningTimer else { return }
        do {
            let timerID = runningTimer.id
            let log = try engine.stop(timer: runningTimer, at: date)
            let descriptor = FetchDescriptor<StoredTimer>(predicate: #Predicate { $0.id == timerID })
            if let storedTimer = try modelContext.fetch(descriptor).first {
                modelContext.delete(storedTimer)
            }
            modelContext.insert(try StoredActivityLog(log: log))
            try modelContext.save()
            refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        do {
            runningTimer = try modelContext.fetch(FetchDescriptor<StoredTimer>(sortBy: [SortDescriptor(\.startedAt)])).first?.runningTimer
            pendingLogCount = try modelContext.fetchCount(FetchDescriptor<StoredActivityLog>(predicate: #Predicate { $0.syncStateRawValue == "pending" }))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TimerHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: TimerHomeModel?
    @State private var now = Date.now

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView("Opening your timer")
                    .task { model = TimerHomeModel(modelContext: modelContext) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TimerHomeModel) -> some View {
        VStack(spacing: 24) {
            Text("Time Tracker")
                .font(.largeTitle.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let timer = model.runningTimer {
                VStack(alignment: .leading, spacing: 12) {
                    Text(timer.title)
                        .font(.title2.weight(.medium))
                    Text(Duration.seconds(timer.elapsedSeconds(at: now)), format: .time(pattern: .hourMinuteSecond))
                        .font(.system(size: 48, weight: .regular, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { model.stop() }) {
                    Text("Stop timer")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                TextField("What are you working on?", text: Binding(
                    get: { model.title },
                    set: { model.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.sentences)

                Button(action: { model.start() }) {
                    Text("Start timer")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.pendingLogCount > 0 {
                Text("\(model.pendingLogCount) logs waiting to sync")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
}
