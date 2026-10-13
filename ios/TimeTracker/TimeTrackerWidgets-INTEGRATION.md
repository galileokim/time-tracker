# Widget extension integration

The host `TimeTracker.xcodeproj` builds and embeds the `TimeTrackerWidgets` WidgetKit extension in the app. `TimeTrackerWidgets.xcodeproj` is a standalone development project.

To embed it when consolidating the Xcode projects:

- Add the `TimeTrackerWidgets` app-extension target to the host project and make the app target depend on it.
- Embed `TimeTrackerWidgets.appex` in the host app's `PlugIns` directory with `CodeSignOnCopy` and `RemoveHeadersOnCopy`.
- Keep the host and extension App Group entitlement set to `group.com.galileotimetracker.app`.
- Keep the extension bundle identifier under the host app identifier, currently `com.galileotimetracker.app.widgets`.
- Build/archive the host app and verify the extension exists at `TimeTracker.app/PlugIns/TimeTrackerWidgets.appex` before claiming device availability.

The simulator integration script builds the combined host/extension scheme, verifies the embedded extension and matching App Group entitlements, installs the app, and launches it. Simulator tests do not verify physical-device signing, provisioning, or ActivityKit presentation.
