#!/usr/bin/env bash
# builds Lamport Build for release and packs a dmg. ad-hoc signed unless a Developer ID is given:
#   SIGN_ID="Developer ID Application: Lamport Robotics (TEAMID)" APPLE_ID=… APPLE_TEAM_ID=… APPLE_PASSWORD=… scripts/release.sh
# the apple password is an app-specific password; keep these in a local env file, never in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project LamportBuild.xcodeproj -scheme LamportBuild -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD" || true
APP="build/Build/Products/Release/Lamport Build.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
OUT="build/Lamport Build $VERSION.dmg"; rm -f "$OUT"
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lamport Build" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"; rm -rf "$STAGE"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
  if [ -n "${APPLE_ID:-}" ]; then
    xcrun notarytool submit "$OUT" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_PASSWORD" --wait
    xcrun stapler staple "$OUT"
  fi
fi
ls -la "$OUT"
