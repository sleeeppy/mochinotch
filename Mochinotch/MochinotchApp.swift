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
        guard !status.present.isEmpty else {
            print("Claude Code, Cursor, Codex를 찾지 못했어요.")
            return 1
        }
        let result = HookInstaller.install(tools: status.present)
        print("전달 스크립트: \(HookInstaller.relayURL.path)")
        for tool in result.connected {
            print("\(tool.displayName): " + (result.changed.contains(tool) ? "연결함" : "이미 연결됨"))
        }
        for (tool, message) in result.failures {
            print("\(tool.displayName): \(message)")
        }
        let restarts = result.changed.filter(\.needsRestart)
        if !restarts.isEmpty {
            print("켜져 있는 \(restarts.map(\.displayName).joined(separator: ", "))는 다시 시작해야 적용돼요.")
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
