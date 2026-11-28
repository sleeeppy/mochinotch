#!/bin/sh
# Windows 앱을 빌드해서 설치 프로그램을 만든다. macOS에서도 돈다.
#
#   ./scripts/make-win-installer.sh
#
# 필요한 것: .NET 10 SDK, NSIS(brew install makensis)
# 결과: build/Mochinotch-win-x64-setup.exe. 릴리즈에는 이 파일만 올린다.
# 이름에 win이 들어가야 0.8.0 이하 앱도 업데이트로 찾고, setup이 들어가야 설치 창을 띄운다.
set -e

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/windows/Mochinotch.Win/Mochinotch.Win.csproj"
version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$project" | head -n 1)"
if [ -z "$version" ]; then
  echo "Mochinotch.Win.csproj에서 Version을 찾지 못했어요" >&2
  exit 1
fi
command -v makensis >/dev/null || { echo "makensis가 없어요. brew install makensis" >&2; exit 1; }

publish="$root/build/win-$version"
rm -rf "$publish"
dotnet publish "$project" -c Release -r win-x64 -o "$publish" -p:DebugType=None >/dev/null

setup="$root/build/Mochinotch-win-x64-setup.exe"
rm -f "$setup"
(cd "$root/windows/installer" && makensis -V2 -INPUTCHARSET UTF8 \
  -DVERSION="$version" -DAPP_EXE="$publish/Mochinotch.exe" -DOUT_FILE="$setup" Mochinotch.nsi)

echo "$setup"
