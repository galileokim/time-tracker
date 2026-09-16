import Foundation

public struct TimerEngine: Sendable {
    public init() {}

    public func start(
        existing: RunningTimer?,
        title: String,
        notes: String? = nil,
        categoryIDs: [UUID] = [],
        visibility: ActivityVisibility = .public,
        at startedAt: Date
    ) throws -> RunningTimer {
        guard existing == nil else { throw TimerStoreError.timerAlreadyRunning }
        return RunningTimer(
            id: UUID(),
            userID: nil,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            categoryIDs: categoryIDs,
            visibility: visibility,
            startedAt: startedAt
        )
    }

    public func stop(timer: RunningTimer?, at endedAt: Date) throws -> LocalActivityLog {
        guard let timer else { throw TimerStoreError.noRunningTimer }
        guard endedAt >= timer.startedAt else { throw TimerStoreError.invalidTimeRange }

        return LocalActivityLog(
            idempotencyKey: UUID(),
            userID: timer.userID,
            title: timer.title,
            notes: timer.notes,
            startedAt: timer.startedAt,
            endedAt: endedAt,
            categoryIDs: timer.categoryIDs,
            visibility: timer.visibility
        )
    }
}
