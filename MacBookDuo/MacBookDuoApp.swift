import AppKit
import SwiftUI

@main
enum MacBookDuoMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var retained: AppDelegate?
    private static let showMenuNote = Notification.Name("com.foldglass.macbookduo.showMenu")

    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.foldglass.macbookduo")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DistributedNotificationCenter.default().post(name: Self.showMenuNote, object: nil)
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPopover),
            name: Self.showMenuNote,
            object: nil
        )

        installStatusItem()
        model.start()
        observeStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showPopover()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.hideOverlay()
        DistributedNotificationCenter.default().removeObserver(self, name: Self.showMenuNote, object: nil)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "com.foldglass.macbookduo.statusItem.icon"
        item.isVisible = true
        item.behavior = []
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MacBook Duo")
            button.image?.isTemplate = true
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "MacBook Duo"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let host = NSHostingController(rootView: MenuBarView(model: model))
        host.sizingOptions = .preferredContentSize

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = host
        self.popover = popover
        refreshStatusItem()
    }

    private func observeStatusItem() {
        withObservationTracking {
            _ = model.angle
            _ = model.showsAngleInMenuBar
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshStatusItem()
                self?.observeStatusItem()
            }
        }
    }

    private func refreshStatusItem() {
        guard let item = statusItem, let button = item.button else { return }
        if model.showsAngleInMenuBar {
            item.length = NSStatusItem.variableLength
            button.title = String(format: " %.0f°", model.angle)
            button.imagePosition = .imageLeading
        } else {
            item.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    @objc func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        statusItem?.isVisible = true

        if let host = popover.contentViewController {
            host.view.layoutSubtreeIfNeeded()
            let fitted = host.view.fittingSize
            popover.contentSize = NSSize(width: 320, height: max(fitted.height, 1))
        }

        // Attach to the top of the status button, then pin the panel to the
        // actual menu-bar bottom so it does not sit a full button-height lower.
        let attach = NSRect(x: 0, y: button.bounds.height, width: button.bounds.width, height: 0)
        popover.show(relativeTo: attach, of: button, preferredEdge: .minY)

        guard let popoverWindow = popover.contentViewController?.view.window,
              let buttonWindow = button.window else { return }

        var frame = popoverWindow.frame
        let buttonScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let menuBarHeight = buttonWindow.frame.height
        let screenMaxY = buttonWindow.screen?.frame.maxY ?? buttonScreen.maxY
        let menuBarMinY = screenMaxY - menuBarHeight
        frame.origin.y = menuBarMinY - frame.height
        frame.origin.x = buttonScreen.midX - frame.width / 2
        popoverWindow.setFrame(frame, display: true)
        popoverWindow.makeKey()
    }
}
