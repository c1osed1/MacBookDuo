import AppKit

@MainActor
final class OverlayController {
    private let engine: DuoEngine
    private var window: NSWindow?
    private var metalView: DuoMetalView?
    private(set) var isVisible = false

    init(engine: DuoEngine) {
        self.engine = engine
    }

    var uniforms: DuoUniforms {
        get { metalView?.uniforms ?? .identity }
        set { metalView?.uniforms = newValue }
    }

    func show() {
        guard engine.hasSource else { return }
        let screen = ScreenSnapper.builtinScreen() ?? NSScreen.main
        guard let screen else { return }

        if window == nil {
            let metalView = DuoMetalView(engine: engine)
            let overlay = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: true,
                screen: screen
            )
            overlay.contentView = metalView
            overlay.isOpaque = true
            overlay.backgroundColor = .black
            overlay.hasShadow = false
            overlay.ignoresMouseEvents = true
            overlay.level = .screenSaver
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            overlay.animationBehavior = .none
            overlay.isReleasedWhenClosed = false
            overlay.sharingType = .none
            self.metalView = metalView
            self.window = overlay
        }

        guard let window else { return }
        window.setFrame(screen.frame, display: false)
        metalView?.frame = window.contentView?.bounds ?? screen.frame
        metalView?.isPaused = false
        window.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        metalView?.isPaused = true
        window?.orderOut(nil)
        isVisible = false
    }
}
