#!/bin/sh
# Release로 빌드한 Mochinotch.app을 설치용 DMG로 만든다.
# 창을 열면 앱과 Applications 폴더가 나란히 있어서, 끌어다 놓으면 설치된다.
#
#   ./scripts/make-dmg.sh build/release/Build/Products/Release/Mochinotch.app
set -e

app="${1:-}"
if [ -z "$app" ] || [ ! -d "$app/Contents/MacOS" ]; then
  echo "usage: $0 path/to/Mochinotch.app" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
out="$root/build/Mochinotch-$version.dmg"
stage="$(mktemp -d /tmp/mochinotch-dmg.XXXXXX)"
trap 'rm -rf "$stage"; hdiutil detach /Volumes/Mochinotch >/dev/null 2>&1 || true' EXIT

mkdir "$stage/stage"
cp -R "$app" "$stage/stage/Mochinotch.app"
# macOS 26은 일반 icns 뒤에 밝은 판을 깐다. 같은 그림을 Finder 아이콘으로 지정하면 판이 빠진다.
swift -e "import AppKit
let app = \"$stage/stage/Mochinotch.app\"
guard let image = NSImage(contentsOfFile: app + \"/Contents/Resources/AppIcon.icns\") else {
    fputs(\"icon missing\\n\", stderr); exit(1)
}
if !NSWorkspace.shared.setIcon(image, forFile: app, options: []) {
    fputs(\"icon stamp failed\\n\", stderr); exit(1)
}
"
ln -s /Applications "$stage/stage/Applications"
mkdir "$stage/stage/.background"
cp "$root/docs/images/dmg-background.png" "$stage/stage/.background/background.png"

mkdir -p "$root/build"
rm -f "$out"
hdiutil create -volname "Mochinotch $version" -srcfolder "$stage/stage" -format UDRW -ov "$stage/rw.dmg" >/dev/null

mount="$(hdiutil attach -readwrite -noverify "$stage/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
osascript <<EOF
tell application "Finder"
  tell disk "$(basename "$mount")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Mochinotch.app" to {150, 200}
    set position of item "Applications" to {510, 200}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
# 아이콘 위치를 창이 기억하게 한 뒤 뺀다.
sync
hdiutil detach "$mount" >/dev/null
hdiutil convert "$stage/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null
echo "$out"
