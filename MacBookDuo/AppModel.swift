import AppKit
import Foundation
import Observation
import QuartzCore

@MainActor
@Observable
final class AppModel {
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }
    var intensity: Double {
        didSet { UserDefaults.standard.set(intensity, forKey: "intensity") }
    }
    var openAngle: Double {
        didSet { UserDefaults.standard.set(openAngle, forKey: "openAngle") }
    }
    var closedAngle: Double {
        didSet { UserDefaults.standard.set(closedAngle, forKey: "closedAngle") }
    }
    var demoAngle: Double = 110
    var driveDisplayFromDemo = false
    var studioOpen = false

    let sensor = LidSensor()
    let engine: DuoEngine
    let overlay: OverlayController
    let capture: CaptureStream

    var lastCaptureFailed: Bool { engine.captureFailed && !engine.hasSource }
    var isCapturing: Bool { capture.isRunning }

    private var started = false
    private var smoothedAngle = 110.0
    private var smoothedProgress = 0.0
    private var cannedProgress: Double?
    private var cannedStart: TimeInterval = 0
    private var lastTime = CACurrentMediaTime()
    private var lastIdlePoll = 0.0
    private var displayLink: CADisplayLink?
    private let tickProxy = TickProxy()
    private var hideHold = 0
    private var highRate = false
    private var holdingFreeze = false
    private var captureTask: Task<Void, Never>?
    private var screenObservers: [NSObjectProtocol] = []

    var angle: Double {
        if cannedProgress != nil { return mappedAngle(for: smoothedProgress) }
        if driveDisplayFromDemo || !sensor.isAvailable { return demoAngle }
        return smoothedAngle
    }

    var progress: Double { smoothedProgress }
    var sensorAvailable: Bool { sensor.isAvailable }
    var sensorStatus: String { sensor.status }
    var overlayActive: Bool { overlay.isVisible }

    init() {
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        intensity = min(max(UserDefaults.standard.object(forKey: "intensity") as? Double ?? 1.35, 0.8), 1.85)
        openAngle = min(max(UserDefaults.standard.object(forKey: "openAngle") as? Double ?? 100, 50), 160)
        closedAngle = min(max(UserDefaults.standard.object(forKey: "closedAngle") as? Double ?? 18, 5), 50)
        engine = DuoEngine()
        overlay = OverlayController(engine: engine)
        capture = CaptureStream(engine: engine)
    }

    func start() {
        guard !started else { return }
        started = true
        sensor.start()
        let initial = sensor.isAvailable ? sensor.angle : 110
        demoAngle = initial
        smoothedAngle = initial
        lastTime = CACurrentMediaTime()

        tickProxy.onTick = { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        installDisplayLink()
        observeEnvironment()
    }

    func shutdown() async {
        overlay.destroyWindow()
        holdingFreeze = false
        capture.frozen = false
        displayLink?.invalidate()
        displayLink = nil
        screenObservers.forEach { NotificationCenter.default.removeObserver($0) }
        screenObservers.removeAll()
        captureTask?.cancel()
        captureTask = nil
        await capture.stop()
    }

    func hideOverlay() {
        overlay.hide()
        holdingFreeze = false
        capture.frozen = false
    }

    func handleEnvironmentChange() {
        if ScreenSnapper.builtinScreen() == nil {
            overlay.destroyWindow()
            holdingFreeze = false
            captureTask?.cancel()
            captureTask = nil
            Task { await capture.stop() }
            installDisplayLink()
            return
        }

        installDisplayLink()
        overlay.reassert()
    }

    func tick() {
        let now = CACurrentMediaTime()
        let active = needsActiveTick
        if !active, now - lastIdlePoll < 0.09 {
            return
        }
        lastIdlePoll = now

        let dt = min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0)
        lastTime = now

        if sensor.isAvailable {
            sensor.poll()
            if !driveDisplayFromDemo, cannedProgress == nil {
                demoAngle = sensor.angle
            }
        }

        let rawAngle: Double
        if cannedProgress != nil {
            rawAngle = mappedAngle(for: cannedCurveNow())
        } else if driveDisplayFromDemo || !sensor.isAvailable {
            rawAngle = demoAngle
        } else {
            rawAngle = sensor.angle
        }

        let speed = abs(rawAngle - smoothedAngle)
        let cutoff = 10.0 + min(speed, 18.0) * 1.6
        let angleFollow = 1 - exp(-dt * cutoff)
        smoothedAngle += (rawAngle - smoothedAngle) * angleFollow

        let target: Double
        if cannedProgress != nil {
            let elapsed = now - cannedStart
            if elapsed >= 2.6 {
                cannedProgress = nil
                target = Self.progress(for: smoothedAngle, open: openAngle, closed: closedAngle)
            } else {
                target = Self.cannedCurve(elapsed)
            }
        } else {
            target = Self.progress(for: smoothedAngle, open: openAngle, closed: closedAngle)
        }

        let progressFollow = 1 - exp(-dt * 26)
        smoothedProgress += (target - smoothedProgress) * progressFollow
        if abs(target - smoothedProgress) < 0.0005 {
            smoothedProgress = target
        }

        var uniforms = DuoUniforms.identity
        uniforms.progress = Float(min(max(smoothedProgress, 0), 1))
        uniforms.angle = Float(smoothedAngle)
        uniforms.intensity = Float(intensity)
        overlay.uniforms = uniforms

        guard enabled else {
            hideHold = 0
            holdingFreeze = false
            capture.frozen = false
            if overlay.isVisible { overlay.hide() }
            if capture.isRunning || capture.isStarting {
                captureTask?.cancel()
                captureTask = nil
                Task { await capture.stop() }
            }
            syncTickRate()
            return
        }

        if ScreenSnapper.builtinScreen() == nil {
            overlay.hide()
            holdingFreeze = false
            syncTickRate()
            return
        }

        let folding = smoothedProgress > 0.012 || cannedProgress != nil
        if folding {
            hideHold = 0
            if !holdingFreeze {
                if engine.hasSource {
                    commitFreezeAndShow()
                } else {
                    ensureCaptureStarted()
                }
            }
        } else if overlay.isVisible {
            hideHold += 1
            if hideHold > 10 {
                overlay.hide()
                holdingFreeze = false
                capture.frozen = false
                hideHold = 0
                captureTask?.cancel()
                captureTask = nil
                Task { await capture.stop() }
            }
        } else if capture.frozen, cannedProgress == nil {
            capture.frozen = false
            holdingFreeze = false
        }

        syncTickRate()
    }

    func playCannedDemo() {
        Task { [weak self] in
            guard let self else { return }
            if !self.engine.hasSource {
                await self.capture.start()
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard self.engine.hasSource else { return }
            self.commitFreezeAndShow()
            self.cannedStart = CACurrentMediaTime()
            self.cannedProgress = 0
            self.syncTickRate()
        }
    }

    func openStudio() {
        studioOpen = true
        StudioWindow.shared.show(model: self)
    }

    private func commitFreezeAndShow() {
        capture.frozen = true
        engine.commitBlur()
        holdingFreeze = true
        overlay.show()
        if capture.isRunning {
            Task { await capture.stopStream() }
        }
    }

    private func ensureCaptureStarted() {
        guard !capture.isRunning, !capture.isStarting, captureTask == nil else { return }
        captureTask = Task { [weak self] in
            await self?.capture.start()
            self?.captureTask = nil
        }
    }

    private var needsActiveTick: Bool {
        overlay.isVisible
            || cannedProgress != nil
            || smoothedProgress > 0.008
            || capture.isRunning
            || capture.isStarting
            || holdingFreeze
    }

    private func syncTickRate() {
        let active = needsActiveTick
        guard active != highRate else { return }
        highRate = active
        displayLink?.preferredFrameRateRange = active
            ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
    }

    private func installDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        highRate = false
        let screen = ScreenSnapper.builtinScreen() ?? NSScreen.screens.first
        let link = screen?.displayLink(target: tickProxy, selector: #selector(TickProxy.step(_:)))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
        link?.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func observeEnvironment() {
        let center = NotificationCenter.default
        let screens = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleEnvironmentChange()
            }
        }
        let spaces = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.overlay.reassert()
            }
        }
        screenObservers = [screens, spaces]
    }

    private func cannedCurveNow() -> Double {
        Self.cannedCurve(CACurrentMediaTime() - cannedStart)
    }

    private static func progress(for angle: Double, open: Double, closed: Double) -> Double {
        let span = max(open - closed, 12)
        let linear = (open - angle) / span
        return min(max(linear, 0), 1)
    }

    private func mappedAngle(for progress: Double) -> Double {
        let span = max(openAngle - closedAngle, 12)
        return openAngle - progress * span
    }

    private static func cannedCurve(_ elapsed: TimeInterval) -> Double {
        if elapsed < 1.05 {
            return smoothstep(elapsed / 1.05)
        }
        if elapsed < 1.35 {
            return 1
        }
        return 1 - smoothstep((elapsed - 1.35) / 1.15)
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

private final class TickProxy: NSObject {
    var onTick: () -> Void = {}

    @objc func step(_ sender: CADisplayLink) {
        onTick()
    }
}
