import ActivityKit
import Foundation

@MainActor
@Observable
final class LiveActivityController {
    private(set) var activeActivityID: String?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(for timer: RunningTimer) async {
        guard LiveActivityCapability.shouldRequestActivity(activitiesEnabled: isSupported) else { return }
        await endExistingActivity()

        let attributes = TimerActivityAttributes(timerID: timer.id)
        let state = TimerActivityAttributes.ContentState(
            startedAt: timer.startedAt,
            activityTitle: timer.title
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            let activity = try Activity<TimerActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activeActivityID = activity.id
        } catch {
            activeActivityID = nil
        }
    }

    func end(timerID: UUID) async {
        let activityIDs = Activity<TimerActivityAttributes>.activities
            .filter { $0.attributes.timerID == timerID }
            .map(\.id)
        await endActivities(withIDs: activityIDs)
        if activityIDs.contains(activeActivityID ?? "") {
            activeActivityID = nil
        }
    }

    func currentActivityState() -> TimerActivityAttributes.ContentState? {
        guard let activeActivityID,
              let activity = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == activeActivityID }) else {
            return nil
        }
        return activity.content.state
    }

    func endAll() async {
        await endExistingActivity()
    }

    func restoreRunningTimer(_ timer: RunningTimer?) async {
        guard let timer else {
            await endExistingActivity()
            return
        }
        if let existing = Activity<TimerActivityAttributes>.activities.first(where: { $0.attributes.timerID == timer.id }) {
            activeActivityID = existing.id
            return
        }
        await start(for: timer)
    }

    private func endExistingActivity() async {
        let activityIDs = Activity<TimerActivityAttributes>.activities.map(\.id)
        await endActivities(withIDs: activityIDs)
        activeActivityID = nil
    }

    nonisolated private func endActivities(withIDs ids: [String]) async {
        for activityID in ids {
            guard let activity = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == activityID }) else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
