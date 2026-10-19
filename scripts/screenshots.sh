#!/bin/bash
#
# Captures the screens an App Store listing needs, from the Simulator.
#
# The Simulator has almost no sensors, so every number in these comes from
# MockSensorSource (R-71). They are good enough to lay out a listing and to review a
# change, but the screenshots that actually ship should be retaken on a physical iPhone
# with real readings — see docs/RELEASE.md.
#
# Usage: scripts/screenshots.sh [device name]

set -euo pipefail

DEVICE="${1:-Readout iPhone}"
OUTPUT="${OUTPUT:-build/screenshots}"
BUNDLE_ID="com.leeyenkai.Readout"
DERIVED="${DERIVED:-build/screenshots-dd}"

mkdir -p "$OUTPUT"

echo "==> Building"
xcodebuild \
  -project Readout.xcodeproj \
  -scheme Readout \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -configuration Release \
  build >/dev/null

APP="$DERIVED/Build/Products/Release-iphonesimulator/Readout.app"
[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 1; }

echo "==> Booting $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE"

echo "==> Installing"
xcrun simctl install "$DEVICE" "$APP"

shot() {
  sleep "${2:-2}"
  xcrun simctl io "$DEVICE" screenshot "$OUTPUT/$1.png" >/dev/null
  echo "    $1.png"
}

echo "==> Home Screen, light and dark"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl ui "$DEVICE" appearance light
shot icon-light 1
xcrun simctl ui "$DEVICE" appearance dark
shot icon-dark 1
xcrun simctl ui "$DEVICE" appearance light

echo "==> App"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null
shot readings 4

echo
echo "Saved to $OUTPUT."
echo "The remaining screens — a detail view, each tool, a recording — need taps;"
echo "drive them in the Simulator and run: xcrun simctl io '$DEVICE' screenshot <file>.png"
