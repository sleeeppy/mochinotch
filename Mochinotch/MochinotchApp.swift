import AppKit
import SwiftUI

@main
struct MochinotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(AppModel.shared)
        } label: {
            Image(systemName: "capsule.portrait.fill")
        }

        Settings {
            SettingsView()
                .environment(AppModel.shared)
                .frame(width: 440, height: 320)
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
