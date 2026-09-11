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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    nonisolated(unsafe) static var retained: AppDelegate?
    private static let showWindowNote = Notification.Name("com.foldglass.macbookduo.showWindow")

    let model = AppModel()
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
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

        installStatusItem()
        installMainWindow()
        model.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleEnabled(_:)) {
            menuItem.state = model.enabled ? .on : .off
        }
        return true
    }

    @objc func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if mainWindow == nil {
            installMainWindow()
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        statusItem?.isVisible = true
    }

    @objc func preview(_ sender: Any?) {
        model.playCannedDemo()
    }

    @objc func toggleEnabled(_ sender: Any?) {
        model.enabled.toggle()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow, !isQuitting else { return true }
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        statusItem?.isVisible = true
        return false
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
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "com.foldglass.macbookduo.statusItem.icon.v2"
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MacBook Duo")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "MacBook Duo"
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "MacBook Duo", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", action: #selector(showMainWindow), key: ","))
        menu.addItem(menuItem("Preview", action: #selector(preview(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Enable lid effect", action: #selector(toggleEnabled(_:))))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacBook Duo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
