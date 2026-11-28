#!/bin/sh
# Release로 빌드한 Mochinotch.app을 설치용 DMG로 만든다.
# 창을 열면 앱과 Applications 폴더가 화살표를 사이에 두고 나란히 있어서, 끌어다 놓으면 설치된다.
#
#   ./scripts/make-dmg.sh build/release/Build/Products/Release/Mochinotch.app
#
# 배경 그림은 scripts/make-installer-art.swift로 다시 그린다.
set -e

app="${1:-}"
if [ -z "$app" ] || [ ! -d "$app/Contents/MacOS" ]; then
  echo "usage: $0 path/to/Mochinotch.app" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
volume="Mochinotch $version"
out="$root/build/Mochinotch-$version.dmg"
stage="$(mktemp -d /tmp/mochinotch-dmg.XXXXXX)"
mount=""
cleanup() {
  [ -n "$mount" ] && hdiutil detach "$mount" -force >/dev/null 2>&1 || true
  rm -rf "$stage"
}
trap cleanup EXIT

# 같은 이름의 볼륨이 이미 붙어 있으면 Finder가 엉뚱한 창을 꾸민다.
for old in "/Volumes/$volume" /Volumes/"$volume "*; do
  [ -d "$old" ] && hdiutil detach "$old" -force >/dev/null 2>&1 || true
done

mkdir "$stage/stage"
ditto "$app" "$stage/stage/Mochinotch.app"
ln -s /Applications "$stage/stage/Applications"
mkdir "$stage/stage/.background"
# 1x와 2x를 한 tiff에 넣어 레티나에서도 배경이 흐리지 않게 한다.
tiffutil -cathidpicheck "$root/docs/images/dmg-background.png" "$root/docs/images/dmg-background@2x.png" \
  -out "$stage/stage/.background/background.tiff" >/dev/null

mkdir -p "$root/build"
rm -f "$out"
hdiutil create -volname "$volume" -srcfolder "$stage/stage" -fs HFS+ -format UDRW -ov "$stage/rw.dmg" >/dev/null

mount="$(hdiutil attach -readwrite -noverify -noautoopen "$stage/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
SetFile -a V "$mount/.background"

# 배경이 600x360이다. bounds는 제목 막대까지 포함하므로 높이에 32를 더한다.
# 아이콘 위치는 배경의 화살표 양 끝(160, 178), (440, 178)과 맞춘다.
osascript <<EOF
tell application "Finder"
  tell disk "$(basename "$mount")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set bounds of container window to {200, 120, 800, 512}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to false
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Mochinotch.app" to {160, 178}
    set position of item "Applications" to {440, 178}
    set extension hidden of item "Mochinotch.app" to true
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

# 디스크 아이콘은 Finder가 창을 꾸민 뒤에 넣어야 지워지지 않는다.
icon="$app/Contents/Resources/AppIcon.icns"
if [ -f "$icon" ]; then
  cp "$icon" "$mount/.VolumeIcon.icns"
  SetFile -a V "$mount/.VolumeIcon.icns"
  SetFile -a C "$mount"
fi

# Finder가 남긴 흔적은 지우고, .DS_Store(창 모양)만 남긴다.
rm -rf "$mount/.fseventsd" "$mount/.Trashes"
chmod -Rf go-w "$mount" 2>/dev/null || true
sync
hdiutil detach "$mount" >/dev/null || hdiutil detach "$mount" -force >/dev/null
mount=""
hdiutil convert "$stage/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null

# 서명 인증서가 있으면 DMG에도 서명한다. 공증은 xcrun notarytool로 따로 한다.
if [ -n "${MOCHINOTCH_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$MOCHINOTCH_SIGN_IDENTITY" --timestamp "$out"
fi
echo "$out"
