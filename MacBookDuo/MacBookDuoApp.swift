import AppKit
import SwiftUI

@main
enum MacBookDuoMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    nonisolated(unsafe) static var retained: AppDelegate?
    private static let showWindowNote = Notification.Name("com.foldglass.macbookduo.showWindow")

    let model = AppModel()
    private var mainWindow: NSWindow?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.foldglass.macbookduo")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DistributedNotificationCenter.default().post(name: Self.showWindowNote, object: nil)
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showMainWindow),
            name: Self.showWindowNote,
            object: nil
        )

        installMainWindow()
        model.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isQuitting = true
        Task {
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.hideOverlay()
        DistributedNotificationCenter.default().removeObserver(self, name: Self.showWindowNote, object: nil)
    }

    @objc func showMainWindow() {
        if mainWindow == nil {
            installMainWindow()
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMainWindow() {
        let host = NSHostingController(rootView: MainWindowView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "MacBook Duo"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 720, height: 480)
        window.center()
        window.isReleasedWhenClosed = true
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow, !isQuitting else { return true }
        NSApp.terminate(nil)
        return false
    }
}
