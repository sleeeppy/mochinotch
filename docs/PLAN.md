# Mochinotch (もちノッチ) — 개발 플랜

맥북 노치를 아이폰 다이나믹 아일랜드처럼 활용하는 macOS 앱.
애플 공식 앱 수준의 UI와 애니메이션(Dynamic Island / Live Activity 디자인 언어)을 목표로 한다.
AI API는 사용하지 않으며, 모든 기능은 로컬에서 동작한다.

---

## 1. 기능 목록

| # | 기능 | 구현 방식 | 난이도 |
|---|---|---|---|
| F1 | 충전기 연결 시 애니메이션 | IOKit 전원 알림(`IOPSNotificationCreateRunLoopSource`)으로 연결/해제 감지 | 쉬움 |
| F2 | 알림이 노치 쪽에 쌓이는 UI | 아래 "F2 제약" 참고 | **어려움** |
| F3 | Cursor / Claude Code / Codex 작업 완료 표시 (로고 강조) | 각 앱의 공식 hook → `mochinotch://` URL 스킴 또는 `127.0.0.1:47321` HTTP로 이벤트 전달 | 보통 |
| F4 | 노치 호버 시 확장, 상세 알림 확인, 클릭 시 해당 앱으로 이동 | 트래킹 영역 + 목록 UI + `NSWorkspace` 앱 활성화 | 보통 |

### F2 제약

macOS는 서드파티 앱이 다른 앱의 알림을 읽는 공개 API를 제공하지 않는다. 우회 방법은 두 가지다.

- **알림 센터 DB 읽기** (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`)
  - 전체 디스크 접근 권한이 필요하다.
  - 비공개 포맷이라 macOS 업데이트 시 깨질 수 있다.
- **Accessibility API로 알림 배너 창 읽기**
  - 손쉬운 사용 권한이 필요하다.
  - 불안정하다.

두 방법 모두 샌드박스 밖에서만 가능하므로 **앱스토어 배포는 불가**하다(Developer ID로 직접 배포하거나 개인용으로만 사용).
따라서 본 구현 전에 실제로 알림을 읽을 수 있는지 검증하는 실험 단계(Phase 4a)를 둔다.

### F3 hook 연결 방식

| 도구 | hook 위치 | 사용할 이벤트 |
|---|---|---|
| Claude Code | `~/.claude/settings.json` → `hooks` | `Stop`, `Notification` |
| Codex CLI | `~/.codex/config.toml` → `notify` | `agent-turn-complete` |
| Cursor | `~/.cursor/hooks.json` 또는 프로젝트 `.cursor/hooks.json` | `stop` |

- 로고
  - 설치된 앱은 `NSWorkspace.shared.icon(forFile:)`로 실제 아이콘을 가져온다.
  - 터미널 기반 도구(Claude Code, Codex)는 공식 브랜드 에셋을 사용한다.
- 클릭 시 이동
  - 앱은 번들 ID로 활성화한다.
  - CLI 도구는 hook 실행 환경의 `$TERM_PROGRAM` 등으로 터미널 앱을 판별해 활성화한다.

---

## 2. 구현 순서

제어 가능한 것부터 만들고, 리스크가 가장 큰 F2는 마지막에 둔다.

### Phase 0 — 기반

- [x] XcodeGen(`project.yml`) 기반 프로젝트 구성. 메뉴바 상주 앱(`LSUIElement`), macOS 14+
- [x] 노치 지오메트리 감지 (`NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`)
- [x] 노치 없는 맥 / 외부 모니터 폴백: 상단 중앙에 떠 있는 알약 형태
- [x] 노치 패널 (`NSPanel`)
  - `.nonactivatingPanel`, `.borderless`
  - 메뉴 바보다 위 (`CGWindowLevelForKey(.mainMenuWindow) + 3`)
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]`
  - 접힌 상태에서는 `ignoresMouseEvents`로 클릭을 통과시킨다
- [x] **아일랜드 모핑 엔진**
  - 하나의 검은 도형이 `idle → compact → expanded`로 변형된다
  - 컴팩트 상태의 글자는 노치 좌우 귀에만 둔다
  - 상단은 화면 끝에 붙고, 모서리는 continuous corner
- [x] 디자인 토큰: 스프링 프리셋, 코너 반경, 색상 (`IslandMotion`, `IslandColor`)
- [x] 메뉴바 아이콘: 설정, 종료, 디버그용 가짜 이벤트 트리거

### Phase 1 — 충전 애니메이션 (F1)

- [x] 전원 소스 감시 (연결 / 해제 / 완충)
- [x] 연출: 노치 좌우 확장 → 초록 번개 아이콘 + 배터리 % 숫자 롤링(`.contentTransition(.numericText())`) → 수 초 후 자동 수축
- [x] 해제 시에는 짧은 축소 연출

### Phase 2 — 에이전트 작업 완료 (F3)

- [x] 이벤트 수신부: URL 스킴(`mochinotch://event?...`) + 루프백 HTTP `POST /event` (포트 47321)
  - Unix 소켓 대신 HTTP를 쓴다. hook에서 `curl`/`python`으로 보내기 쉽고, `Application Support` 경로의 공백을 피한다.
- [x] CLI 헬퍼 `scripts/mochinotch-notify` 및 `scripts/install-hooks.sh`
- [x] 상태 연출
  - 성공: 완료 라벨
  - 실패: 좌우 흔들림 + 붉은 글로우
  - 입력 대기: 경고색 라벨, 더 오래 유지
- [x] 클릭 시 원래 앱 / 터미널로 이동 (`bundleID`, 없으면 도구 앱 번들)
- [x] Cursor / Claude / Codex에만, 그 색으로 화면 가장자리가 잠깐 굴절된다

### Phase 3 — 호버 확장 + 알림 목록 (F4)

- [x] 이벤트 목록 (동시에 여러 개, 최신 12개)
- [x] 호버 진입 시 짧은 지연 후 확장, 이탈 시 수축
- [x] 확장 상태의 목록 UI: 앱 아이콘, 제목, 본문, 시간
- [x] 항목 클릭 시 해당 앱 활성화
- [ ] `matchedGeometryEffect`로 compact 아이콘이 목록 아이콘으로 이어지는 전환 (다음 다듬기)

### Phase 4 — 시스템 알림 쌓기 (F2)

- [x] **4a. 실험**: 메뉴의 "알림 데이터베이스 실험…"이 DB 경로, 권한, 테이블 이름을 보고한다. 알림 본문은 아직 해석하지 않는다.
- [x] **4b. 대기 표시**: 안 본 알림을 앱별로 묶어, 앱 하나마다 접힌 노치가 오른쪽으로 한 칸(22pt 아이콘 + Dock 같은 개수 배지)씩 늘어난다. 먼저 온 앱이 노치에 가깝고 최대 5개. 목록을 펼쳤다 닫으면 본 것으로 친다.
- [x] **4b. 실제 알림 수집**: `NotificationWatcher`가 DB의 새 `record`를 2초마다 읽어 뱃지로 넣는다. 전체 디스크 접근 권한이 필요하다.

---

## 3. 기술 스택

| 항목 | 선택 |
|---|---|
| 언어 / UI | Swift, SwiftUI (창 제어는 AppKit) |
| 최소 OS | macOS 14 Sonoma (`phaseAnimator`, `keyframeAnimator`, `.blurReplace`, `@Observable`) |
| 프로젝트 | XcodeGen `project.yml` → `xcodegen generate`로 `.xcodeproj` 생성 |
| 배포 | Developer ID 직접 배포 또는 개인용 (F2 때문에 앱스토어 불가) |

## 4. 애니메이션 원칙

- 새 뷰가 뜨는 것이 아니라 **하나의 검은 도형이 형태를 바꾸는 것**처럼 보여야 한다.
- 배경은 노치와 구분되지 않는 순수 검정(`#000000`)을 사용한다.
- 스프링은 살짝 튀는 값(`dampingFraction` ≈ 0.7 전후)을 기본으로 하고, 확장/수축/알림별 프리셋을 분리한다.
- 콘텐츠 전환은 `.blurReplace` + scale을 기본으로 하고, 아이콘 연속성은 `matchedGeometryEffect`로 유지한다.
- 숫자는 `.contentTransition(.numericText())`, 강조 모션은 `keyframeAnimator`를 사용한다.

## 5. 작업 방식

- 개발 환경(Linux)에서는 macOS 앱 빌드와 실행이 불가능하다.
- 따라서 코드 푸시 → 맥에서 `git pull` 후 실행 → 스크린샷/녹화/에러로 피드백 → 수정의 루프로 진행한다.
- Phase 단위로 커밋하고, 각 Phase가 끝나면 맥에서 확인한 뒤 다음 단계로 넘어간다.

## 6. 미정 사항

- [ ] macOS 버전 및 맥북 모델 (노치 크기 기준)
- [ ] 개인용인지, 공개 배포 예정인지 (F2 방식과 권한 설계에 영향)
- [ ] Claude Code / Codex를 실행하는 터미널 (Terminal, iTerm2, Ghostty, Warp 등)
