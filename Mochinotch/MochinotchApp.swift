import AppKit
import SwiftUI

@main
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
