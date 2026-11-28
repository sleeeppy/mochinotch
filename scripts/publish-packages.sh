#!/bin/sh
# GitHub 릴리즈를 올린 뒤 돌린다. Homebrew tap과 winget에 같은 버전을 알린다.
# 릴리즈에 올라간 파일의 SHA-256을 GitHub에서 읽으니, 로컬 빌드 파일은 없어도 된다.
#
#   ./scripts/publish-packages.sh 0.8.2            Homebrew tap에 올리고 winget PR을 보낸다
#   ./scripts/publish-packages.sh 0.8.2 --dry-run  파일만 만들고 아무 데도 올리지 않는다
#
# 필요한 것: gh(로그인), git, komac(brew install komac)
# macOS:   brew trust sleeeppy/tap && brew install --cask sleeeppy/tap/mochinotch
#          (Homebrew 7부터 공식이 아닌 tap은 brew trust를 먼저 해야 한다)
# Windows: winget install sleeeppy.Mochinotch   (첫 PR이 microsoft/winget-pkgs에 머지된 뒤)
set -e

version="${1:-}"
dry=""
[ "${2:-}" = "--dry-run" ] && dry=1
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: $0 <version> [--dry-run]" >&2; exit 1 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="sleeeppy/mochinotch"
tap="sleeeppy/homebrew-tap"
package="sleeeppy.Mochinotch"
dmg="Mochinotch-$version.dmg"
setup="Mochinotch-win-x64-setup.exe"
base="https://github.com/$repo/releases/download/v$version"

digest() {
  gh api "repos/$repo/releases/tags/v$version" \
    -q ".assets[] | select(.name == \"$1\") | .digest" | sed 's/^sha256://'
}
dmg_sha="$(digest "$dmg")"
setup_sha="$(digest "$setup")"
if [ -z "$dmg_sha" ] || [ -z "$setup_sha" ]; then
  echo "v$version 릴리즈에서 $dmg 또는 $setup을 찾지 못했어요" >&2
  exit 1
fi
released="$(gh api "repos/$repo/releases/tags/v$version" -q '.published_at[0:10]')"

out="$root/build/packages/$version"
rm -rf "$out"
mkdir -p "$out/homebrew" "$out/winget"

# ---------- Homebrew ----------
# 공증을 받지 않은 앱이라, README 안내와 같이 설치 뒤 격리 표시를 지운다.
# 앱이 스스로 업데이트하므로 auto_updates를 켜 brew upgrade가 덮어쓰지 않게 한다.
cat > "$out/homebrew/mochinotch.rb" <<EOF
cask "mochinotch" do
  version "$version"
  sha256 "$dmg_sha"

  url "https://github.com/$repo/releases/download/v#{version}/Mochinotch-#{version}.dmg"
  name "Mochinotch"
  desc "Notch alerts for when AI coding agents need you or finish a task"
  homepage "https://github.com/$repo"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Mochinotch.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Mochinotch.app"],
        writable_paths: ["{{appdir}}/Mochinotch.app"]
  end

  uninstall quit: "dev.sleeeppy.mochinotch"

  zap trash: [
    "~/Library/Application Support/Mochinotch",
    "~/Library/Logs/Mochinotch",
    "~/Library/Preferences/dev.sleeeppy.mochinotch.plist",
  ]
end
EOF

# ---------- winget ----------
# NSIS 스텁은 x86이지만 앱은 x64다. 설치 프로그램이 /S일 때 런타임을 묻지 않으니 의존성으로 받게 한다.
manifests="$out/winget/manifests/s/sleeeppy/Mochinotch/$version"
mkdir -p "$manifests"
schema="1.10.0"
setup_upper="$(printf '%s' "$setup_sha" | tr '[:lower:]' '[:upper:]')"

cat > "$manifests/$package.yaml" <<EOF
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.version.$schema.schema.json

PackageIdentifier: $package
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $schema
EOF

cat > "$manifests/$package.installer.yaml" <<EOF
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.installer.$schema.schema.json

PackageIdentifier: $package
PackageVersion: $version
InstallerType: nullsoft
Scope: user
InstallModes:
- interactive
- silent
UpgradeBehavior: install
Dependencies:
  PackageDependencies:
  - PackageIdentifier: Microsoft.DotNet.Runtime.10
ProductCode: Mochinotch
ReleaseDate: $released
AppsAndFeaturesEntries:
- DisplayName: Mochinotch
  Publisher: sleeeppy
  ProductCode: Mochinotch
InstallationMetadata:
  DefaultInstallLocation: '%LocalAppData%\Programs\Mochinotch'
Installers:
- Architecture: x64
  InstallerUrl: $base/$setup
  InstallerSha256: $setup_upper
ManifestType: installer
ManifestVersion: $schema
EOF

cat > "$manifests/$package.locale.en-US.yaml" <<EOF
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.defaultLocale.$schema.schema.json

PackageIdentifier: $package
PackageVersion: $version
PackageLocale: en-US
Publisher: sleeeppy
PublisherUrl: https://github.com/sleeeppy
PublisherSupportUrl: https://github.com/$repo/issues
Author: sleeeppy
PackageName: Mochinotch
PackageUrl: https://github.com/$repo
License: GPL-3.0
LicenseUrl: https://github.com/$repo/blob/main/LICENSE
ShortDescription: Shows when your AI coding agents need you or finish a task, at the top of the screen.
Description: Mochinotch shows a small alert at the top of the screen when Claude Code, Cursor, Codex, Kiro or Antigravity is waiting for you or has finished a task.
Moniker: mochinotch
Tags:
- ai
- claude
- codex
- cursor
- notifications
ReleaseNotesUrl: https://github.com/$repo/releases/tag/v$version
ManifestType: defaultLocale
ManifestVersion: $schema
EOF

cat > "$manifests/$package.locale.ko-KR.yaml" <<EOF
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.locale.$schema.schema.json

PackageIdentifier: $package
PackageVersion: $version
PackageLocale: ko-KR
ShortDescription: AI 코딩 에이전트가 확인을 기다리거나 작업을 끝내면 화면 위쪽에 알려 줘요.
ManifestType: locale
ManifestVersion: $schema
EOF

echo "$out/homebrew/mochinotch.rb"
echo "$manifests"
if [ -n "$dry" ]; then
  echo "--dry-run: 아무 데도 올리지 않았어요"
  exit 0
fi

# ---------- 올리기 ----------
work="$(mktemp -d /tmp/mochinotch-tap.XXXXXX)"
trap 'rm -rf "$work"' EXIT
if ! gh repo view "$tap" >/dev/null 2>&1; then
  gh repo create "$tap" --public --description "Homebrew tap for Mochinotch" >/dev/null
fi
gh repo clone "$tap" "$work/tap" -- --quiet 2>/dev/null || git init -q "$work/tap"
mkdir -p "$work/tap/Casks"
cp "$out/homebrew/mochinotch.rb" "$work/tap/Casks/mochinotch.rb"
if [ ! -f "$work/tap/README.md" ]; then
  cat > "$work/tap/README.md" <<'EOF'
# sleeeppy/tap

```sh
brew trust sleeeppy/tap
brew install --cask sleeeppy/tap/mochinotch
```
EOF
fi
(
  cd "$work/tap"
  git add -A
  if git diff --cached --quiet; then
    echo "Homebrew tap은 이미 v$version이에요"
  else
    git commit -q -m "mochinotch $version"
    git branch -M main
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$tap.git"
    git push -q origin main
    echo "Homebrew tap을 v$version으로 올렸어요"
  fi
)

GITHUB_TOKEN="$(gh auth token)" komac submit --yes "$manifests"
