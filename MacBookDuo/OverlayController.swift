import AppKit
import CoreGraphics

@MainActor
final class OverlayController {
    private let engine: DuoEngine
    private var window: OverlayPanel?
    private var metalView: DuoMetalView?
    private var boundDisplayID: CGDirectDisplayID?
    private var windowIsLive = false
    private var presenceWindow: NSWindow?
    private(set) var isVisible = false
    var liveDesktop = false
    var plusLook = PlusLook() {
        didSet { metalView?.plusLook = plusLook }
    }
    var foldMode: FoldMode = .glass {
        didSet { metalView?.foldMode = foldMode }
    }
    var openAngle: Double = 100 {
        didSet { metalView?.openAngle = openAngle }
    }

    init(engine: DuoEngine) {
        self.engine = engine
    }

    var uniforms: DuoUniforms {
        get { metalView?.uniforms ?? .identity }
        set { metalView?.uniforms = newValue }
    }

    func show() {
        guard engine.hasSource else { return }
        guard let screen = ScreenSnapper.builtinScreen(),
              let displayID = ScreenSnapper.builtinDisplayID() else {
            hide()
            return
        }

        if boundDisplayID != displayID || windowIsLive != liveDesktop {
            destroyWindow()
        }

        if window == nil {
            let metalView = DuoMetalView(engine: engine)
            metalView.foldMode = foldMode
            metalView.openAngle = openAngle
            metalView.plusLook = plusLook
            metalView.liveDesktop = liveDesktop
            metalView.applyChrome()
            let overlay = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            overlay.contentView = metalView
            self.metalView = metalView
            self.window = overlay
            boundDisplayID = displayID
            windowIsLive = liveDesktop
        }

        guard let window else { return }
        applyOverlayChrome(window, live: liveDesktop)
        metalView?.foldMode = foldMode
        metalView?.openAngle = openAngle
        metalView?.plusLook = plusLook
        metalView?.liveDesktop = liveDesktop
        if window.screen != screen || window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        metalView?.frame = window.contentView?.bounds ?? screen.frame
        metalView?.applyChrome()
        metalView?.isPaused = false
        window.orderFrontRegardless()
        isVisible = true
    }

    func reassert() {
        guard isVisible else { return }
        show()
    }

    func hide() {
        metalView?.isPaused = true
        window?.orderOut(nil)
        isVisible = false
    }

    func destroyWindow() {
        metalView?.isPaused = true
        window?.orderOut(nil)
        window = nil
        metalView = nil
        boundDisplayID = nil
        windowIsLive = false
        isVisible = false
    }

    /// ScreenCaptureKit only lists apps that own a window, so exclusion of
    /// the overlay from the capture stream needs this placeholder.
    func keepPresence() {
        guard presenceWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.alphaValue = 0.004
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.sharingType = .readOnly
        window.orderFrontRegardless()
        presenceWindow = window
    }

    private func applyOverlayChrome(_ overlay: OverlayPanel, live: Bool) {
        overlay.isOpaque = !live
        overlay.backgroundColor = live ? .clear : .black
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.hidesOnDeactivate = false
        overlay.becomesKeyOnlyIfNeeded = true
        overlay.isFloatingPanel = true
        overlay.worksWhenModal = true
        overlay.level = .screenSaver
        overlay.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        overlay.animationBehavior = .none
        overlay.isReleasedWhenClosed = false
        overlay.sharingType = .none
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
