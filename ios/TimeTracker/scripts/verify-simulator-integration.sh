#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/TimeTracker.xcodeproj"
SCHEME="TimeTracker"
DEVICE_ID="${SIMULATOR_UDID:-B6B4EF0A-3778-407C-8C76-536AEEC0BA16}"
DERIVED_DATA="${DERIVED_DATA_PATH:-$PROJECT_DIR/DerivedData}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

export DEVELOPER_DIR

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/TimeTracker.app"
EXTENSION="$APP/PlugIns/TimeTrackerWidgets.appex"

if [[ ! -d "$EXTENSION" ]]; then
  printf 'Missing embedded widget extension: %s\n' "$EXTENSION" >&2
  exit 1
fi

EXTENSION_POINT=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$EXTENSION/Info.plist")
if [[ "$EXTENSION_POINT" != "com.apple.widgetkit-extension" ]]; then
  printf 'Unexpected extension point: %s\n' "$EXTENSION_POINT" >&2
  exit 1
fi

plutil -lint "$PROJECT_DIR/TimeTracker.entitlements" "$PROJECT_DIR/TimeTrackerWidgets.entitlements" >/dev/null
HOST_GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$PROJECT_DIR/TimeTracker.entitlements")
WIDGET_GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$PROJECT_DIR/TimeTrackerWidgets.entitlements")
if [[ "$HOST_GROUP" != "$WIDGET_GROUP" || "$HOST_GROUP" != "group.com.galileotimetracker.app" ]]; then
  printf 'App Group mismatch: host=%s widget=%s\n' "$HOST_GROUP" "$WIDGET_GROUP" >&2
  exit 1
fi

xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" com.timetracker.app
printf 'PASS: host app launches with embedded WidgetKit extension on simulator %s\n' "$DEVICE_ID"
