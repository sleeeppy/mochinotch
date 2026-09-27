#!/bin/bash
# 떠 있는 Mochinotch를 완전히 끈 뒤 빌드하고 새로 띄운다.
# 이전 앱이 살아 있는 동안 open 하면 macOS가 그 앱을 다시 앞으로 가져올 뿐이라 옛 버전이 남는다.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Mochinotch.app"
cd "$ROOT"

xcodegen generate --quiet
xcodebuild -project Mochinotch.xcodeproj -scheme Mochinotch -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet

pkill -x Mochinotch || true
for _ in $(seq 1 25); do
  pgrep -x Mochinotch >/dev/null || break
  sleep 0.2
done

# 같은 번들 ID가 다른 곳(Xcode DerivedData 등)에도 등록돼 있으면 open 이 그쪽 옛 빌드를 띄운다.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
while IFS= read -r other; do
  [[ -n "$other" && "$other" != "$APP" ]] && "$LSREG" -u "$other" || true
done < <(mdfind "kMDItemCFBundleIdentifier == 'dev.sleeeppy.mochinotch'")
"$LSREG" -f "$APP"

open "$APP"
sleep 1
RUNNING="$(ps -axo command | grep -m1 '[M]ochinotch.app/Contents/MacOS/Mochinotch' || true)"
if [[ "$RUNNING" == "$APP/Contents/MacOS/Mochinotch"* ]]; then
  echo "실행함: $APP"
else
  echo "다른 복사본이 떴어요: ${RUNNING:-없음}" >&2
  exit 1
fi
