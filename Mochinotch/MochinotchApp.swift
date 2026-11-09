import AppKit
import SwiftUI

/// hook이 부르는 명령과 설치 명령은 창을 띄우지 않고 끝난다.
@main
enum Launcher {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "--hook":
            exit(HookRelay.run(Array(arguments.dropFirst())))
        case "--install-hooks":
            exit(installHooks())
        case "--self-test":
            let notices = NotificationWatcherSelfTest.run()
            let security = SecuritySelfTest.run()
            exit(notices == 0 && security == 0 ? 0 : 1)
        default:
            MochinotchApp.main()
        }
    }

    private static func installHooks() -> Int32 {
        let status = HookInstaller.status()
        let language = AppLanguage.stored
        guard !status.present.isEmpty else {
            print(L10n.text(.agentsMissing, language))
            return 1
        }
        let result = HookInstaller.install(tools: status.present)
        print("\(HookInstaller.relayURL.path)")
        for tool in result.connected {
            let state = result.changed.contains(tool) ? L10n.text(.linked, language) : L10n.text(.alreadyLinked, language)
            print("\(tool.displayName): \(state)")
        }
        for (tool, problem) in result.failures {
            print("\(tool.displayName): \(problem.text(in: language))")
        }
        let restarts = result.changed.filter(\.needsRestart)
        if !restarts.isEmpty {
            print(L10n.text(.restartManually, language, restarts.map(\.displayName).joined(separator: ", ")))
        }
        return result.failures.isEmpty ? 0 : 1
    }
}

struct MochinotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 메뉴바 아이콘은 쓰지 않는다. Scene은 있어야 앱이 살아 있다.
    @State private var showMenuBarExtra = false

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 보이는 창이 없는 상주 앱을 유휴 종료 대상으로 올리지 않는다.
        ProcessInfo.processInfo.disableAutomaticTermination("menu-bar-resident")
        ProcessInfo.processInfo.disableSuddenTermination()
        AppModel.shared.start()
    }

    /// 사용자가 종료를 누르거나, 업데이트·권한 재실행이 `quit()`을 호출한 뒤에만 꺼진다.
    /// Apple Intelligence가 화면을 조회하면 `linkd`가 이미 떠 있는 프로세스에도 quit을 보낸다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppModel.shared.isQuitting || Self.sessionIsEnding {
            return .terminateNow
        }
        return .terminateCancel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppModel.shared.handleIncomingURL(url)
        }
    }

    /// 로그아웃, 재시동, 시스템 종료, 모두 종료. 거절하면 세션이 끝나지 않는다.
    private static var sessionIsEnding: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEQuitApplication else { return false }
        let reason = event.paramDescriptor(forKeyword: kAEQuitReason)
            ?? event.attributeDescriptor(forKeyword: kAEQuitReason)
        guard let reason else { return false }
        let code = reason.descriptorType == typeEnumerated ? reason.enumCodeValue : reason.typeCodeValue
        return sessionEndingReasons.contains(code)
    }

    private static let sessionEndingReasons: Set<OSType> = [
        OSType(kAELogOut),
        OSType(kAEReallyLogOut),
        OSType(kAERestart),
        OSType(kAEShutDown),
        OSType(kAEQuitAll),
    ]
}
