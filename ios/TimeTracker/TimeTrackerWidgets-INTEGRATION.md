# Widget extension integration

`TimeTrackerWidgets.xcodeproj` builds the WidgetKit extension independently. It is not embedded in `TimeTracker.xcodeproj`, so the widget is not available to add on a device yet.

To embed it when consolidating the Xcode projects:

- Add the `TimeTrackerWidgets` app-extension target to the host project and make the app target depend on it.
- Embed `TimeTrackerWidgets.appex` in the host app's `PlugIns` directory with `CodeSignOnCopy` and `RemoveHeadersOnCopy`.
- Keep the host and extension App Group entitlement set to `group.com.timetracker.shared`.
- Keep the extension bundle identifier under the host app identifier, currently `com.timetracker.app.widgets`.
- Build/archive the host app and verify the extension exists at `TimeTracker.app/PlugIns/TimeTrackerWidgets.appex` before claiming device availability.

The independent widget target and host app currently compile; those builds do not verify embedding or device installation of the widget.
