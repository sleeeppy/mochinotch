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
        AppModel.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppModel.shared.handleIncomingURL(url)
        }
    }
}
