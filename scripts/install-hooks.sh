#!/bin/bash
# mochinotch-notify를 ~/.local/bin에 두고, 원하면 hook 설정을 병합한다.
# 설정 파일은 수정 전에 .mochinotch.bak 으로 복사한다.
#
#   ./scripts/install-hooks.sh
#   ./scripts/install-hooks.sh --apply

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/mochinotch-notify"
APPLY=0

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

mkdir -p "$BIN_DIR"
cp "$ROOT/scripts/mochinotch-notify" "$TARGET"
chmod +x "$TARGET"

echo "설치함: $TARGET"
echo

if [[ "$APPLY" -eq 0 ]]; then
  cat <<EOF
hook까지 넣으려면:
  ./scripts/install-hooks.sh --apply

직접 넣을 때 명령은 이거예요.
  $TARGET

Claude Code  ~/.claude/settings.json
Cursor       ~/.cursor/hooks.json
Codex        ~/.codex/config.toml   (notify 는 사용자 설정에만 동작)

예시는 hooks/ 폴더에 있어요.
EOF
  exit 0
fi

python3 - "$TARGET" <<'PY'
import json, os, shutil, sys

target = sys.argv[1]

def backup(path):
    if os.path.exists(path):
        shutil.copy2(path, path + ".mochinotch.bak")

def merge_claude():
    path = os.path.expanduser("~/.claude/settings.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = {}
    if os.path.exists(path):
        backup(path)
        with open(path) as handle:
            data = json.load(handle)
    hooks = data.setdefault("hooks", {})
    command = f"{target} --source claude"
    for event in ("Stop", "Notification", "StopFailure"):
        groups = hooks.setdefault(event, [])
        if any(command in json.dumps(group) for group in groups):
            continue
        groups.append({"hooks": [{"type": "command", "command": command}]})
    with open(path, "w") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"Claude Code: {path}")

def merge_cursor():
    path = os.path.expanduser("~/.cursor/hooks.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = {"version": 1, "hooks": {}}
    if os.path.exists(path):
        backup(path)
        with open(path) as handle:
            data = json.load(handle)
    data.setdefault("version", 1)
    hooks = data.setdefault("hooks", {})
    command = f"{target} --source cursor"
    stops = hooks.setdefault("stop", [])
    if not any(command in json.dumps(item) for item in stops):
        stops.append({"command": command})
    with open(path, "w") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"Cursor: {path}")

def merge_codex():
    import re
    import tomllib

    path = os.path.expanduser("~/.codex/config.toml")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    existing = ""
    if os.path.exists(path):
        with open(path) as handle:
            existing = handle.read()
    if target in existing:
        print(f"Codex: 이미 연결됨 ({path})")
        return

    current = tomllib.loads(existing).get("notify") if existing else None
    command = [target, "--source", "codex"]
    # notify는 하나만 받으니, 원래 명령은 --chain으로 넘겨 그대로 이어서 실행한다.
    if isinstance(current, list) and current:
        command += ["--chain", json.dumps(current, ensure_ascii=False)]
    line = "notify = " + json.dumps(command, ensure_ascii=False)

    backup(path)
    # notify는 맨 위 테이블 키다. 첫 [섹션] 앞에서만 찾는다.
    header = re.search(r"^\s*\[", existing, flags=re.M)
    head, tail = (existing[: header.start()], existing[header.start():]) if header else (existing, "")
    pattern = re.compile(r"^notify\s*=\s*\[.*?\][ \t]*$", flags=re.M | re.S)
    if current is not None and pattern.search(head):
        head = pattern.sub(lambda _: line, head, count=1)
    else:
        if head and not head.endswith("\n"):
            head += "\n"
        head += f"# Mochinotch\n{line}\n"
        if tail:
            head += "\n"
    updated = head + tail
    tomllib.loads(updated)
    with open(path, "w") as handle:
        handle.write(updated)
    print(f"Codex: {path}" + (" (기존 notify 는 이어서 실행)" if current else ""))

try:
    merge_claude()
    merge_cursor()
    merge_codex()
except Exception as error:
    print(f"설정을 병합하지 못했어요: {error}", file=sys.stderr)
    sys.exit(1)
PY
