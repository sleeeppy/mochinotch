#!/bin/bash
# 앱의 설정 화면에서 "AI 에이전트 연결"을 누른 것과 같다. 앱 실행 파일이 hook을 병합한다.
# 설정 파일은 수정 전에 .mochinotch.bak 으로 복사한다.
#
#   ./scripts/install-hooks.sh
#   ./scripts/install-hooks.sh /path/to/Mochinotch.app

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANDIDATES=(
  "${1:-}"
  "/Applications/Mochinotch.app"
  "$HOME/Applications/Mochinotch.app"
  "$ROOT/build/DerivedData/Build/Products/Debug/Mochinotch.app"
)

for app in "${CANDIDATES[@]}"; do
  if [[ -n "$app" && -x "$app/Contents/MacOS/Mochinotch" ]]; then
    exec "$app/Contents/MacOS/Mochinotch" --install-hooks
  fi
done

echo "Mochinotch.app을 찾지 못했어요. 앱 경로를 넘겨 주세요." >&2
echo "  ./scripts/install-hooks.sh /Applications/Mochinotch.app" >&2
exit 1
