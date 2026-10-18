#!/usr/bin/env bash
# builds Lamport Build for release and packs a dmg. ad-hoc signed unless a Developer ID is given:
#   SIGN_ID="Developer ID Application: Lamport Robotics (TEAMID)" APPLE_ID=… APPLE_TEAM_ID=… APPLE_PASSWORD=… scripts/release.sh
# the apple password is an app-specific password; keep these in a local env file, never in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project LamportBuild.xcodeproj -scheme LamportBuild -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | grep -E "error:|\*\* BUILD" || true
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
mkdir "$STAGE/.background"; cp scripts/dmg/background.tiff "$STAGE/.background/background.tiff"
# lay the window out on a writable copy, then compress it
RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname "Lamport Build" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ -quiet "$RW"; rm -rf "$STAGE"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -o '/Volumes/.*$')
osascript <<EOF
tell application "Finder"
  tell disk "$(basename "$MOUNT")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 800, 528}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "Lamport Build.app" of container window to {170, 190}
    set position of item "Applications" of container window to {430, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# finder drops a volume icon set before it lays the window out, so it goes on last
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"; SetFile -a C "$MOUNT"
sync; hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$OUT"; rm -f "$RW"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
  if [ -n "${APPLE_ID:-}" ]; then
    xcrun notarytool submit "$OUT" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_PASSWORD" --wait
    xcrun stapler staple "$OUT"
  fi
fi
ls -la "$OUT"
