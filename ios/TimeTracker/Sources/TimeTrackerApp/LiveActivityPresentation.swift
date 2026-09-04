import ActivityKit
import SwiftUI

struct LiveTimerLockScreenView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.activityTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("Timer running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(state.startedAt, style: .timer)
                .font(.title3.monospacedDigit().weight(.medium))
                .accessibilityLabel("Elapsed time")
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
