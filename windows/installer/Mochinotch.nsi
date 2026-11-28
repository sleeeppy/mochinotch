; Mochinotch Windows 설치 프로그램.
; scripts/make-win-installer.sh가 VERSION, APP_EXE, OUT_FILE을 넘겨 빌드한다.
;
; 관리자 권한 없이 %LOCALAPPDATA%\Programs\Mochinotch에 깐다. 앱 안 업데이트가 같은 자리에
; 덮어쓸 수 있고, AI hook이 가리키는 경로도 버전이 바뀌어도 그대로다.
; /S로 실행하면 창 없이 덮어쓰고 앱을 다시 켠다. 앱 안 업데이트가 이 방식을 쓴다.

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!ifndef VERSION
  !error "VERSION을 넘겨 주세요. 예: makensis -DVERSION=0.9.0"
!endif
!ifndef APP_EXE
  !error "APP_EXE를 넘겨 주세요. dotnet publish로 만든 Mochinotch.exe 경로입니다."
!endif
!ifndef OUT_FILE
  !define OUT_FILE "Mochinotch-win-x64-setup.exe"
!endif

!define APP_NAME "Mochinotch"
!define PUBLISHER "sleeeppy"
!define HOMEPAGE "https://github.com/sleeeppy/mochinotch"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Mochinotch"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define DOTNET_URL "https://aka.ms/dotnet/10.0/dotnet-runtime-win-x64.exe"
!define DOTNET_PAGE "https://dotnet.microsoft.com/download/dotnet/10.0"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel user
BrandingText "${APP_NAME} ${VERSION}"
ShowInstDetails nevershow
ShowUninstDetails nevershow

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=0 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=0 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=0 "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey /LANG=0 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=0 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=0 "LegalCopyright" "© ${PUBLISHER}"

; ---------- 화면 ----------
!define MUI_ICON "..\Mochinotch.Win\Mochinotch.ico"
!define MUI_UNICON "..\Mochinotch.Win\Mochinotch.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "$(WelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$(FinishTitle)"
!define MUI_FINISHPAGE_TEXT "$(FinishText)"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Mochinotch.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(RunNow)"
; README 칸을 바탕 화면 바로 가기 선택으로 쓴다.
!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME_TEXT "$(DesktopShortcut)"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION CreateDesktopShortcut
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 처음 넣은 언어가 기본값이다. 시스템 언어가 아래에 있으면 그 언어로 뜬다.
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "Japanese"
!insertmacro MUI_LANGUAGE "SimpChinese"

; ---------- 문구 ----------
LangString WelcomeTitle ${LANG_ENGLISH} "Install Mochinotch"
LangString WelcomeTitle ${LANG_KOREAN} "Mochinotch 설치"
LangString WelcomeTitle ${LANG_JAPANESE} "Mochinotch のインストール"
LangString WelcomeTitle ${LANG_SIMPCHINESE} "安装 Mochinotch"

LangString WelcomeText ${LANG_ENGLISH} "Mochinotch shows when your AI agents need you or finish a task, right at the top of the screen.$\r$\n$\r$\nIt installs for your account only, so no administrator rights are needed.$\r$\n$\r$\nClick Next to continue."
LangString WelcomeText ${LANG_KOREAN} "AI 에이전트가 확인을 기다리거나 작업을 끝내면 화면 위쪽에 바로 알려 줘요.$\r$\n$\r$\n지금 계정에만 설치하므로 관리자 권한이 필요 없어요.$\r$\n$\r$\n계속하려면 다음을 누르세요."
LangString WelcomeText ${LANG_JAPANESE} "AI エージェントが確認を待っているときや作業が終わったときに、画面上部ですぐにお知らせします。$\r$\n$\r$\nこのアカウントだけにインストールするので、管理者権限は不要です。$\r$\n$\r$\n続けるには「次へ」を押してください。"
LangString WelcomeText ${LANG_SIMPCHINESE} "AI 代理等待确认或完成任务时，Mochinotch 会在屏幕顶部及时提醒你。$\r$\n$\r$\n只为当前账户安装，不需要管理员权限。$\r$\n$\r$\n点击“下一步”继续。"

LangString FinishTitle ${LANG_ENGLISH} "Mochinotch is ready"
LangString FinishTitle ${LANG_KOREAN} "설치가 끝났어요"
LangString FinishTitle ${LANG_JAPANESE} "インストールが完了しました"
LangString FinishTitle ${LANG_SIMPCHINESE} "安装完成"

LangString FinishText ${LANG_ENGLISH} "Open settings from the tray icon and press Connect under AI agents to start getting alerts."
LangString FinishText ${LANG_KOREAN} "트레이 아이콘에서 설정을 열고 AI 에이전트 연결의 연결을 누르면 알림이 오기 시작해요."
LangString FinishText ${LANG_JAPANESE} "トレイアイコンから設定を開き、AI エージェント連携の「連携」を押すと通知が届き始めます。"
LangString FinishText ${LANG_SIMPCHINESE} "从托盘图标打开设置，在 AI 代理连接中点击“连接”即可开始接收提醒。"

LangString RunNow ${LANG_ENGLISH} "Open Mochinotch now"
LangString RunNow ${LANG_KOREAN} "지금 Mochinotch 열기"
LangString RunNow ${LANG_JAPANESE} "今すぐ Mochinotch を開く"
LangString RunNow ${LANG_SIMPCHINESE} "立即打开 Mochinotch"

LangString DesktopShortcut ${LANG_ENGLISH} "Add a shortcut to the desktop"
LangString DesktopShortcut ${LANG_KOREAN} "바탕 화면에 바로 가기 만들기"
LangString DesktopShortcut ${LANG_JAPANESE} "デスクトップにショートカットを作成"
LangString DesktopShortcut ${LANG_SIMPCHINESE} "在桌面创建快捷方式"

LangString NeedWin10 ${LANG_ENGLISH} "Mochinotch needs 64-bit Windows 10 or later."
LangString NeedWin10 ${LANG_KOREAN} "Mochinotch는 64비트 Windows 10 이상에서 실행돼요."
LangString NeedWin10 ${LANG_JAPANESE} "Mochinotch には 64 ビット版 Windows 10 以降が必要です。"
LangString NeedWin10 ${LANG_SIMPCHINESE} "Mochinotch 需要 64 位 Windows 10 或更高版本。"

LangString AskRuntime ${LANG_ENGLISH} "Mochinotch needs the .NET 10 runtime from Microsoft (about 30 MB).$\r$\n$\r$\nDownload and install it now?"
LangString AskRuntime ${LANG_KOREAN} "Mochinotch를 실행하려면 Microsoft .NET 10 런타임(약 30MB)이 필요해요.$\r$\n$\r$\n지금 받아서 설치할까요?"
LangString AskRuntime ${LANG_JAPANESE} "Mochinotch の実行には Microsoft .NET 10 ランタイム (約 30 MB) が必要です。$\r$\n$\r$\n今すぐダウンロードしてインストールしますか?"
LangString AskRuntime ${LANG_SIMPCHINESE} "运行 Mochinotch 需要 Microsoft .NET 10 运行时（约 30 MB）。$\r$\n$\r$\n现在下载并安装吗？"

LangString GettingRuntime ${LANG_ENGLISH} "Downloading the .NET 10 runtime..."
LangString GettingRuntime ${LANG_KOREAN} ".NET 10 런타임을 받는 중..."
LangString GettingRuntime ${LANG_JAPANESE} ".NET 10 ランタイムをダウンロードしています..."
LangString GettingRuntime ${LANG_SIMPCHINESE} "正在下载 .NET 10 运行时..."

LangString InstallingRuntime ${LANG_ENGLISH} "Installing the .NET 10 runtime..."
LangString InstallingRuntime ${LANG_KOREAN} ".NET 10 런타임을 설치하는 중..."
LangString InstallingRuntime ${LANG_JAPANESE} ".NET 10 ランタイムをインストールしています..."
LangString InstallingRuntime ${LANG_SIMPCHINESE} "正在安装 .NET 10 运行时..."

LangString RuntimeFailed ${LANG_ENGLISH} "The .NET 10 runtime could not be installed. The download page will open so you can install it yourself, then start Mochinotch from the Start menu."
LangString RuntimeFailed ${LANG_KOREAN} ".NET 10 런타임을 설치하지 못했어요. 받기 페이지를 열어 드릴게요. 직접 설치한 뒤 시작 메뉴에서 Mochinotch를 켜 주세요."
LangString RuntimeFailed ${LANG_JAPANESE} ".NET 10 ランタイムをインストールできませんでした。ダウンロードページを開きます。手動でインストールしてから、スタートメニューで Mochinotch を起動してください。"
LangString RuntimeFailed ${LANG_SIMPCHINESE} "无法安装 .NET 10 运行时。将打开下载页面，请手动安装后从开始菜单启动 Mochinotch。"

LangString RuntimeSkipped ${LANG_ENGLISH} "Install the .NET 10 runtime before opening Mochinotch. The download page will open now."
LangString RuntimeSkipped ${LANG_KOREAN} "Mochinotch를 켜기 전에 .NET 10 런타임을 설치해 주세요. 받기 페이지를 열어 드릴게요."
LangString RuntimeSkipped ${LANG_JAPANESE} "Mochinotch を開く前に .NET 10 ランタイムをインストールしてください。ダウンロードページを開きます。"
LangString RuntimeSkipped ${LANG_SIMPCHINESE} "请在打开 Mochinotch 前安装 .NET 10 运行时。现在将打开下载页面。"

LangString Closing ${LANG_ENGLISH} "Closing Mochinotch..."
LangString Closing ${LANG_KOREAN} "실행 중인 Mochinotch를 닫는 중..."
LangString Closing ${LANG_JAPANESE} "実行中の Mochinotch を終了しています..."
LangString Closing ${LANG_SIMPCHINESE} "正在关闭 Mochinotch..."

Var RuntimeReady

; ---------- 도우미 ----------
!macro CloseApp
  DetailPrint "$(Closing)"
  nsExec::Exec '"$SYSDIR\taskkill.exe" /F /IM Mochinotch.exe'
  Pop $0
  Sleep 600
!macroend

; Avalonia는 기본 .NET 런타임만 쓴다. Windows Desktop 런타임은 필요 없다.
Function HasRuntime
  StrCpy $RuntimeReady 0
  ${DisableX64FSRedirection}
  FindFirst $0 $1 "$PROGRAMFILES64\dotnet\shared\Microsoft.NETCore.App\10.*"
  ${If} $1 != ""
    StrCpy $RuntimeReady 1
  ${EndIf}
  FindClose $0
  ; Arm64 Windows에서 x64 런타임은 dotnet\x64 아래에 깔린다.
  ${If} $RuntimeReady == 0
    FindFirst $0 $1 "$PROGRAMFILES64\dotnet\x64\shared\Microsoft.NETCore.App\10.*"
    ${If} $1 != ""
      StrCpy $RuntimeReady 1
    ${EndIf}
    FindClose $0
  ${EndIf}
  ${EnableX64FSRedirection}
FunctionEnd

Function InstallRuntime
  Call HasRuntime
  ${If} $RuntimeReady == 1
    Return
  ${EndIf}
  ; 앱 안 업데이트(/S)는 이미 런타임으로 돌던 앱에서 오므로 묻지 않는다.
  ${If} ${Silent}
    Return
  ${EndIf}
  MessageBox MB_YESNO|MB_ICONQUESTION "$(AskRuntime)" IDYES download
  MessageBox MB_OK|MB_ICONINFORMATION "$(RuntimeSkipped)"
  ExecShell "open" "${DOTNET_PAGE}"
  Return

download:
  InitPluginsDir
  DetailPrint "$(GettingRuntime)"
  SetDetailsPrint none
  nsExec::Exec `powershell -NoProfile -ExecutionPolicy Bypass -Command "$$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '${DOTNET_URL}' -OutFile '$PLUGINSDIR\dotnet-runtime.exe'"`
  Pop $0
  SetDetailsPrint both
  ${IfNot} ${FileExists} "$PLUGINSDIR\dotnet-runtime.exe"
    Goto failed
  ${EndIf}
  DetailPrint "$(InstallingRuntime)"
  ; 런타임 설치 프로그램이 스스로 관리자 권한을 요청하고 진행 창을 띄운다.
  ExecWait '"$PLUGINSDIR\dotnet-runtime.exe" /install /passive /norestart' $0
  Call HasRuntime
  ${If} $RuntimeReady == 1
    Return
  ${EndIf}

failed:
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(RuntimeFailed)"
  ExecShell "open" "${DOTNET_PAGE}"
FunctionEnd

Function CreateDesktopShortcut
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\Mochinotch.exe"
FunctionEnd

Function .onInit
  ${IfNot} ${RunningX64}
  ${OrIfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "$(NeedWin10)" /SD IDOK
    Abort
  ${EndIf}
  ; 설치 프로그램을 두 번 열면 하나만 남긴다.
  System::Call 'kernel32::CreateMutex(p 0, i 0, t "dev.sleeeppy.mochinotch.setup") p .r1 ?e'
  Pop $0
  ${If} $0 == 183
    Abort
  ${EndIf}
FunctionEnd

; ---------- 설치 ----------
Section "Mochinotch" Main
  SectionIn RO
  !insertmacro CloseApp

  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "/oname=Mochinotch.exe" "${APP_EXE}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\Mochinotch.exe"
  ; 바탕 화면 바로 가기가 이미 있으면 새 경로로 맞춘다.
  ${If} ${FileExists} "$DESKTOP\${APP_NAME}.lnk"
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\Mochinotch.exe"
  ${EndIf}

  WriteRegStr HKCU "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "${HOMEPAGE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Mochinotch.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" "$0"

  Call InstallRuntime
  ${If} $RuntimeReady == 1
    ; portable exe에서 넘어왔으면 예전 경로를 가리키던 hook과 로그인 시 실행을 옮긴다.
    nsExec::Exec '"$INSTDIR\Mochinotch.exe" --relink'
    Pop $0
    ${If} ${Silent}
      Exec '"$INSTDIR\Mochinotch.exe"'
    ${EndIf}
  ${EndIf}
SectionEnd

; ---------- 지우기 ----------
Section "Uninstall"
  !insertmacro CloseApp

  Delete "$INSTDIR\Mochinotch.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; 로그인 시 실행이 이 설치본을 가리킬 때만 지운다.
  ReadRegStr $0 HKCU "${RUN_KEY}" "${APP_NAME}"
  ${If} $0 == '"$INSTDIR\Mochinotch.exe"'
    DeleteRegValue HKCU "${RUN_KEY}" "${APP_NAME}"
  ${EndIf}

  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\${APP_NAME}"
  ; 설정(%APPDATA%\Mochinotch)은 다시 설치할 때 쓰도록 남긴다.
SectionEnd
