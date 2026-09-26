# Mochinotch (もちノッチ)

맥북 노치를 아이폰 다이나믹 아일랜드처럼 쓰는 macOS 앱입니다. 접혀 있을 때는 노치와 하나로 보이고, 충전기나 작업이 끝나면 좌우로 늘어났다가, 노치에 마우스를 올리면 아래로 펼쳐집니다.

AI API는 쓰지 않습니다. Claude Code, Cursor, Codex는 각 도구의 hook이 로컬로 "끝났다"는 신호만 보냅니다.

## 맥에서 실행

Xcode 15 이상, macOS 14 이상이 필요합니다.

```bash
cd project
brew install xcodegen
xcodegen generate
open Mochinotch.xcodeproj
```

Xcode에서 서명을 **Sign to Run Locally**로 두고 Run 합니다. 메뉴 막대에 캡슐 아이콘이 생기고, 실행 직후 노치가 잠깐 늘어나며 `もちノッチ`가 보입니다.

노치가 없는 맥이나 외부 모니터만 연결된 상태에서는 화면 위 중앙의 알약으로 대신 뜹니다.

## 지금 되는 것

- 충전기를 꽂거나 빼면 노치 좌우로 번개와 배터리 퍼센트가 나왔다가 접힙니다. 숫자는 굴러가듯 바뀝니다.
- 메뉴 막대 아이콘에서 충전, Claude, Cursor, Codex, 알림 미리보기를 가짜로 띄울 수 있습니다.
- 알림 미리보기는 노치를 넓히지 않습니다. 오른쪽 끝에 14pt 원형 앱 아이콘이 붙고, 그 오른쪽 위에 빨간 점만 찍힙니다. 노치나 그 원에 마우스를 올리면 목록이 열립니다.
- 노치(또는 알약)에 마우스를 올리면 목록이 펼쳐집니다. 항목을 누르면 그 앱으로 이동합니다.
- 실패한 작업은 아일랜드가 짧게 흔들리고 붉은 테두리가 납니다.

시스템 알림이 노치에 쌓이는 모양은 아직입니다. 레퍼런스 그림을 받은 뒤에 넣습니다. 메뉴의 **알림 데이터베이스 실험…**은 알림 DB를 읽을 수 있는지만 확인합니다.

## 에이전트 작업 완료 연결

앱이 떠 있는 동안 `127.0.0.1:47321`으로만 받습니다.

```bash
./scripts/install-hooks.sh --apply
```

이 명령은 `~/.local/bin/mochinotch-notify`를 만들고, 아래 파일을 고치기 전에 `.mochinotch.bak`으로 복사합니다.

- Claude Code: `~/.claude/settings.json`의 `Stop`, `StopFailure`, `Notification`
- Cursor: `~/.cursor/hooks.json`의 `stop`
- Codex: `~/.codex/config.toml`의 `notify` (이미 `notify`가 있으면 건드리지 않습니다)

직접 보낼 때:

```bash
curl -s -X POST http://127.0.0.1:47321/event \
  -H 'Content-Type: application/json' \
  -d '{"tool":"claude","title":"Claude Code 작업 완료","detail":"mochinotch","kind":"completed","bundleID":"com.apple.Terminal"}'
```

`kind`는 `completed`, `failed`, `needsInput`, `cancelled` 중 하나입니다.

URL로도 보낼 수 있습니다.

```text
mochinotch://event?tool=cursor&title=Cursor%20%EC%99%84%EB%A3%8C&kind=completed
```

## 폴더

| 경로 | 역할 |
|---|---|
| `project/project.yml` | XcodeGen 프로젝트 |
| `project/Mochinotch/` | 앱 소스 |
| `scripts/mochinotch-notify` | hook이 호출하는 전달 스크립트 |
| `scripts/install-hooks.sh` | 스크립트 설치와 hook 병합 |
| `hooks/` | 설정 예시 |
| `docs/PLAN.md` | 개발 플랜 |

## 아직 맥에서 확인하지 못한 것

이 저장소를 만든 환경은 Linux라서 앱을 빌드하거나 실행해 보지 못했습니다. 노치 위치, 스프링 속도, 메뉴 막대와의 겹침은 맥에서 실행한 뒤 맞춰야 합니다.
