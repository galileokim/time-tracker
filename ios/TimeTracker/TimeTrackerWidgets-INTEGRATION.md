# Widget extension integration

`TimeTracker.xcodeproj` builds the `TimeTrackerWidgets` WidgetKit extension and embeds it in the app's `PlugIns` directory. The `TimeTrackerWidgets` scheme builds the extension on its own.

Keep these in sync when changing the targets:

- The host and extension App Group entitlement stays `group.com.galileotimetracker.app` (`WidgetSummaryStorage.sharedGroupID`).
- The extension bundle identifier stays under the host app identifier, currently `com.galileotimetracker.app.widgets`.
- Core files the widget reads (`ProductivitySummary.swift`, `WidgetSummaryStorage.swift`, `WidgetTimelineEntry.swift`, `AnalyticsDurationFormatter.swift`) are members of both targets.

`scripts/verify-simulator-integration.sh` builds the app, verifies the embedded extension and matching App Group entitlements, installs the app, and launches it. Simulator runs do not verify physical-device signing, provisioning, or ActivityKit presentation.
