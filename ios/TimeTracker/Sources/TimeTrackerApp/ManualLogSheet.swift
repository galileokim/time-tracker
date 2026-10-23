import SwiftUI

/// Records time spent without running a timer, such as a session the user forgot to time.
struct ManualLogSheet: View {
    let model: TimerHomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var categoryID: UUID?
    @State private var startedAt: Date
    @State private var hours = 1
    @State private var minutes = 0
    @State private var visibility: ActivityVisibility
    @State private var notes = ""
    @State private var errorMessage: String?

    init(model: TimerHomeModel) {
        self.model = model
        let categories = model.categories
        _categoryID = State(initialValue: categories.category(withID: model.selectedCategoryID)?.id ?? categories.categories.first?.id)
        // Default to the hour that just ended, so the entry is valid as soon as the sheet opens.
        let now = Date.now
        let startOfMinute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        _startedAt = State(initialValue: startOfMinute.addingTimeInterval(-3_600))
        _visibility = State(initialValue: model.visibility)
    }

    private var duration: TimeInterval {
        TimeInterval(hours * 3_600 + minutes * 60)
    }

    private var endedAt: Date {
        startedAt.addingTimeInterval(duration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $categoryID) {
                        Text("Choose a category").tag(UUID?.none)
                        ForEach(model.categories.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }

                Section("When") {
                    DatePicker("Started", selection: $startedAt, in: ...Date.now)
                    HStack(spacing: 0) {
                        durationWheel("Hours", selection: $hours, range: 0..<24, unit: "hr")
                        durationWheel("Minutes", selection: $minutes, range: 0..<60, unit: "min")
                    }
                    .frame(height: 130)
                    LabeledContent("Ends") {
                        Text(endedAt, format: Calendar.current.isDate(endedAt, inSameDayAs: startedAt)
                            ? .dateTime.hour().minute()
                            : .dateTime.weekday(.abbreviated).hour().minute())
                    }
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach([ActivityVisibility.public, .friendsOnly, .private], id: \.self) { option in
                            Text(option.shortLabel).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log time manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(categoryID == nil || duration == 0)
                }
            }
            .onChange(of: [startedAt, endedAt]) { errorMessage = nil }
        }
    }

    private func durationWheel(_ title: String, selection: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        // Side-by-side wheels otherwise overlap each other's touch areas.
        .clipped()
        .contentShape(Rectangle())
    }

    private func save() {
        guard let categoryID else { return }
        do {
            try model.addManualLog(
                categoryID: categoryID,
                startedAt: startedAt,
                duration: duration,
                visibility: visibility,
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
