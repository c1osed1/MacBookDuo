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
        didSet {
            UserDefaults.standard.set(openAngle, forKey: "openAngle")
            if started {
                sawOpenPose = smoothedAngle >= openAngle - 1
            }
        }
    }
    var closedAngle: Double {
        didSet { UserDefaults.standard.set(closedAngle, forKey: "closedAngle") }
    }
    var foldMode: FoldMode {
        didSet {
            UserDefaults.standard.set(foldMode.rawValue, forKey: "foldMode")
            if started { handleModeChange() }
        }
    }
    var viewingDistance: Double {
        didSet { UserDefaults.standard.set(viewingDistance, forKey: "viewingDistance") }
    }
    var recession: Double {
        didSet { UserDefaults.standard.set(recession, forKey: "recession") }
    }
    var maxBlurRadius: Double {
        didSet { UserDefaults.standard.set(maxBlurRadius, forKey: "maxBlurRadius") }
    }
    var blurEvenness: Double {
        didSet { UserDefaults.standard.set(blurEvenness, forKey: "blurEvenness") }
    }
    var maxDim: Double {
        didSet { UserDefaults.standard.set(maxDim, forKey: "maxDim") }
    }
    var dimReach: Double {
        didSet { UserDefaults.standard.set(dimReach, forKey: "dimReach") }
    }
    var perspective: Double {
        get {
            (PlusLook.farthestEye - viewingDistance) / (PlusLook.farthestEye - PlusLook.nearestEye)
        }
        set {
            viewingDistance = PlusLook.farthestEye - min(max(newValue, 0), 1) * (PlusLook.farthestEye - PlusLook.nearestEye)
        }
    }
    var plusLook: PlusLook {
        PlusLook(
            viewingDistance: viewingDistance,
            recession: recession,
            maxBlurRadius: maxBlurRadius,
            blurEvenness: blurEvenness,
            maxDim: maxDim,
            dimReach: dimReach
        )
    }
    var demoAngle: Double = 110
    var driveDisplayFromDemo = false

    let sensor = LidSensor()
    let engine: DuoEngine
    let overlay: OverlayController
    let capture: CaptureStream

    var lastCaptureFailed: Bool { engine.captureFailed && !engine.hasSource }
    var isCapturing: Bool { capture.isRunning }

    private var started = false
    private var smoothedAngle = 110.0
    private var smoothedProgress = 0.0
    private var hingeVelocity = 0.0
    private var cannedProgress: Double?
    private var cannedStart: TimeInterval = 0
    private var lastTime = CACurrentMediaTime()
    private var lastIdlePoll = 0.0
    private var displayLink: CADisplayLink?
    private let tickProxy = TickProxy()
    private var overlayHideCandidateSince: TimeInterval = 0
    private var highRate = false
    private var holdingFreeze = false
    private var foldSessionActive = false
    private var sessionGeneration: UInt64 = 0
    private var captureEpoch: UInt64?
    private var angularVelocity = 0.0
    private var lastAngleSample = 0.0
    private var lastAngleSampleTime: TimeInterval = 0
    private var lastClosingTime: TimeInterval = -.greatestFiniteMagnitude
    private var peakAngle = 0.0
    private var sawOpenPose = false
    private var keepHotUntil: TimeInterval = 0
    private var captureTask: Task<Void, Never>?
    private var captureStopTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var screenObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

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
        if let stored = UserDefaults.standard.string(forKey: "foldMode"), let mode = FoldMode(rawValue: stored) {
            foldMode = mode
        } else {
            foldMode = .glass
        }
        viewingDistance = Self.stored("viewingDistance", 6, PlusLook.nearestEye...PlusLook.farthestEye)
        recession = Self.stored("recession", 1, 0...3)
        maxBlurRadius = Self.stored("maxBlurRadius", 135, 10...160)
        blurEvenness = Self.stored("blurEvenness", 0, 0...1)
        maxDim = Self.stored("maxDim", 1, 0...1)
        dimReach = Self.stored("dimReach", 0.5, 0.2...1)
        engine = DuoEngine()
        overlay = OverlayController(engine: engine)
        capture = CaptureStream(engine: engine)
    }

    func start() {
        guard !started else { return }
        started = true
        sensor.start()
        overlay.foldMode = foldMode
        overlay.liveDesktop = foldMode.usesLiveCapture
        overlay.openAngle = openAngle
        overlay.keepPresence()
        let initial = sensor.isAvailable ? sensor.angle : 110
        demoAngle = initial
        smoothedAngle = initial
        hingeVelocity = 0
        peakAngle = initial
        sawOpenPose = initial >= openAngle - 1
        lastTime = CACurrentMediaTime()

        tickProxy.onTick = { [weak self] dt in
            MainActor.assumeIsolated {
                self?.tick(frameDt: dt)
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
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        demoTask?.cancel()
        demoTask = nil
        captureTask?.cancel()
        captureTask = nil
        if let captureStopTask {
            await captureStopTask.value
        }
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
            requestCaptureStop(discard: true)
            installDisplayLink()
            return
        }

        installDisplayLink()
        overlay.reassert()
    }

    func tick(frameDt: TimeInterval) {
        let now = CACurrentMediaTime()
        let active = needsActiveTick
        if !active, now - lastIdlePoll < 0.09 {
            return
        }
        lastIdlePoll = now

        let dt = min(max(frameDt > 1e-4 ? frameDt : now - lastTime, 1.0 / 240.0), 1.0 / 20.0)
        lastTime = now

        if sensor.isAvailable {
            sensor.poll()
            if !driveDisplayFromDemo, cannedProgress == nil {
                demoAngle = sensor.angle
            }
        }

        if cannedProgress != nil {
            let elapsed = now - cannedStart
            if elapsed >= 2.6 {
                finishCannedDemo(now: now)
            } else {
                smoothedProgress = Self.cannedCurve(elapsed)
                smoothedAngle = mappedAngle(for: smoothedProgress)
                hingeVelocity = 0
            }
        } else {
            let targetAngle: Double
            if driveDisplayFromDemo || !sensor.isAvailable {
                targetAngle = demoAngle
            } else {
                targetAngle = sensor.predictedAngle(at: now)
            }
            let hidSpeed = abs(sensor.coastVelocity(at: now))
            // Slow closes need a longer window so 1° HID steps become a curve.
            // Fast slams shorten it so the pane still keeps up with the lid.
            let smoothTime = 0.1 - min(hidSpeed, 80) / 80 * 0.062
            smoothedAngle = Self.smoothDamp(
                current: smoothedAngle,
                target: targetAngle,
                velocity: &hingeVelocity,
                smoothTime: smoothTime,
                dt: dt
            )
            smoothedProgress = Self.progress(for: smoothedAngle, open: openAngle, closed: closedAngle)
        }

        var uniforms = DuoUniforms.identity
        uniforms.progress = Float(min(max(smoothedProgress, 0), 1))
        uniforms.angle = Float(smoothedAngle)
        uniforms.intensity = Float(intensity)
        overlay.foldMode = foldMode
        overlay.openAngle = openAngle
        overlay.liveDesktop = foldMode.usesLiveCapture
        overlay.plusLook = plusLook
        overlay.uniforms = uniforms

        let motionAngle = sensor.isAvailable ? sensor.angle : smoothedAngle
        trackLidMotion(motionAngle, now: now)
        peakAngle = max(peakAngle, smoothedAngle)
        if smoothedAngle >= openAngle - 1 {
            sawOpenPose = true
        }

        guard enabled else {
            overlayHideCandidateSince = 0
            holdingFreeze = false
            foldSessionActive = false
            captureEpoch = nil
            capture.frozen = false
            if overlay.isVisible { overlay.hide() }
            if capture.isRunning || capture.isStarting {
                requestCaptureStop(discard: false)
            }
            engine.discardSource()
            syncTickRate()
            return
        }

        if ScreenSnapper.builtinScreen() == nil {
            overlay.hide()
            holdingFreeze = false
            foldSessionActive = false
            syncTickRate()
            return
        }

        let folding = wantsFold(now: now)
        let prewarming = wantsPrewarm(now: now)
        if folding {
            overlayHideCandidateSince = 0
            presentFold()
        } else if overlay.isVisible {
            if overlayHideCandidateSince == 0 {
                overlayHideCandidateSince = now
            }
            if now - overlayHideCandidateSince > 0.12 {
                endFold(keepCapture: false)
            }
        } else if foldSessionActive || capture.frozen || captureEpoch != nil {
            endFold(keepCapture: false)
        }

        if !folding, prewarming {
            overlay.keepPresence()
            ensureCaptureStarted()
        } else if !folding, !prewarming, captureStopTask == nil, (capture.isRunning || capture.isStarting) {
            if capture.isRunning {
                _ = engine.persistSource()
            }
            requestCaptureStop(discard: false)
        }

        syncTickRate()
    }

    func playCannedDemo() {
        if cannedProgress != nil, engine.hasSource {
            cannedStart = CACurrentMediaTime()
            cannedProgress = 0
            overlayHideCandidateSince = 0
            syncTickRate()
            return
        }
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            await self?.runCannedDemo()
        }
    }

    private func runCannedDemo() async {
        overlay.keepPresence()
        capture.frozen = false
        holdingFreeze = false

        if !engine.hasSource {
            captureTask?.cancel()
            captureTask = nil
            if let captureStopTask {
                await captureStopTask.value
            }
            guard !Task.isCancelled else { return }
            let baseline = engine.sourceGeneration
            await capture.start(live: foldMode.usesLiveCapture)
            for _ in 0..<50 {
                if Task.isCancelled { return }
                if engine.sourceGeneration > baseline { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard engine.hasSource else { return }
            sessionGeneration = baseline
        } else {
            sessionGeneration = engine.sourceGeneration &- 1
        }

        guard !Task.isCancelled, engine.hasSource else { return }
        foldSessionActive = true
        if foldMode.usesLiveCapture {
            overlay.liveDesktop = true
            overlay.foldMode = foldMode
            overlay.openAngle = openAngle
            overlay.plusLook = plusLook
            overlay.show()
        } else {
            commitFreezeAndShow()
        }
        cannedStart = CACurrentMediaTime()
        cannedProgress = 0
        overlayHideCandidateSince = 0
        syncTickRate()
    }

    private func finishCannedDemo(now: TimeInterval) {
        cannedProgress = nil
        if sensor.isAvailable {
            sensor.poll()
            let real = sensor.angle
            smoothedAngle = real
            hingeVelocity = 0
            demoAngle = real
            lastAngleSample = real
            lastAngleSampleTime = now
        }
        angularVelocity = 0
        lastClosingTime = -.greatestFiniteMagnitude
        smoothedProgress = Self.progress(for: smoothedAngle, open: openAngle, closed: closedAngle)
        sawOpenPose = smoothedAngle >= openAngle - 1
        peakAngle = max(peakAngle, smoothedAngle)
        endFold(keepCapture: false)
    }

    func resetLook() {
        intensity = 1.35
        viewingDistance = 6
        recession = 1
        maxBlurRadius = 135
        blurEvenness = 0
        maxDim = 1
        dimReach = 0.5
    }

    private func presentFold() {
        overlay.keepPresence()
        if captureEpoch == nil {
            captureEpoch = engine.sourceGeneration
            sessionGeneration = engine.sourceGeneration
            holdingFreeze = false
            capture.frozen = false
        }
        ensureCaptureStarted()
        if foldMode.usesLiveCapture {
            guard engine.hasSource else { return }
            capture.frozen = false
            overlay.liveDesktop = true
            overlay.foldMode = foldMode
            overlay.openAngle = openAngle
            overlay.plusLook = plusLook
            if !overlay.isVisible {
                overlay.show()
            }
            foldSessionActive = true
            return
        }
        if holdingFreeze {
            foldSessionActive = true
            return
        }
        let hasFreshFrame = engine.sourceGeneration > sessionGeneration
        if engine.hasSource, hasFreshFrame || capture.isRunning {
            commitFreezeAndShow()
            foldSessionActive = true
            return
        }
        if engine.hasSource {
            overlay.liveDesktop = false
            overlay.show()
            foldSessionActive = true
        }
    }

    private func endFold(keepCapture: Bool) {
        overlay.hide()
        holdingFreeze = false
        capture.frozen = false
        foldSessionActive = false
        captureEpoch = nil
        overlayHideCandidateSince = 0
        keepHotUntil = 0
        if keepCapture { return }
        _ = engine.persistSource()
        requestCaptureStop(discard: false)
    }

    private func requestCaptureStop(discard: Bool) {
        captureTask?.cancel()
        captureTask = nil
        if discard {
            engine.discardSource()
        }
        captureStopTask = Task { [weak self] in
            await self?.capture.stop()
            self?.captureStopTask = nil
        }
    }

    private func commitFreezeAndShow() {
        capture.freeze()
        guard engine.persistSource() else { return }
        engine.commitBlur()
        holdingFreeze = true
        overlay.liveDesktop = false
        overlay.show()
        if captureStopTask == nil, (capture.isRunning || capture.isStarting) {
            requestCaptureStop(discard: false)
        }
    }

    private func ensureCaptureStarted() {
        overlay.keepPresence()
        if capture.isRunning || capture.isStarting || captureTask != nil {
            return
        }
        captureTask = Task { [weak self] in
            await self?.capture.start(live: self?.foldMode.usesLiveCapture == true)
            self?.captureTask = nil
        }
    }

    private func trackLidMotion(_ angle: Double, now: TimeInterval) {
        if lastAngleSampleTime > 0, now > lastAngleSampleTime {
            let dt = now - lastAngleSampleTime
            if dt > 0.001, angle != lastAngleSample {
                let instant = (angle - lastAngleSample) / dt
                angularVelocity = 0.5 * instant + 0.5 * angularVelocity
            }
        }
        if angle != lastAngleSample {
            if angle < lastAngleSample - 0.15 || angularVelocity <= -1.5 {
                lastClosingTime = now
            }
            lastAngleSample = angle
            lastAngleSampleTime = now
        } else if now - lastAngleSampleTime > 0.4 {
            angularVelocity = 0
        }
    }

    private func wantsPrewarm(now: TimeInterval) -> Bool {
        guard enabled, cannedProgress == nil, !overlay.isVisible else { return false }
        let closing = angularVelocity <= -1.5 || now - lastClosingTime < 0.35
        return closing
            && smoothedAngle <= openAngle + 40
            && smoothedAngle >= closedAngle
    }

    private var needsActiveTick: Bool {
        overlay.isVisible
            || cannedProgress != nil
            || smoothedProgress > 0.008
            || holdingFreeze
            || angularVelocity <= -2
            || CACurrentMediaTime() < keepHotUntil
            || CACurrentMediaTime() - lastClosingTime < 0.5
    }

    private func syncTickRate() {
        let active = needsActiveTick
        guard active != highRate else { return }
        highRate = active
        displayLink?.preferredFrameRateRange = active
            ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 15, maximum: 30, preferred: 20)
    }

    private func installDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        highRate = false
        let screen = ScreenSnapper.builtinScreen() ?? NSScreen.screens.first
        let link = screen?.displayLink(target: tickProxy, selector: #selector(TickProxy.step(_:)))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 20)
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
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSleep()
            }
        }
        let wake = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
        screenObservers = [screens, spaces]
        workspaceObservers = [sleep, wake]
    }

    private func handleSleep() {
        endFold(keepCapture: false)
        lastClosingTime = -.greatestFiniteMagnitude
        angularVelocity = 0
        sawOpenPose = false
    }

    private func handleWake() {
        lastClosingTime = -.greatestFiniteMagnitude
        angularVelocity = 0
        lastAngleSampleTime = 0
        let angle = sensor.isAvailable ? sensor.angle : smoothedAngle
        peakAngle = max(peakAngle, angle)
        sawOpenPose = angle >= openAngle - 1
    }

    private func wantsFold(now: TimeInterval) -> Bool {
        if cannedProgress != nil { return true }
        let openingPastStart = angularVelocity >= 2 && smoothedAngle >= openAngle
        if overlay.isVisible || captureEpoch != nil {
            if openingPastStart { return false }
            return smoothedProgress > 0.012
        }
        guard sawOpenPose, smoothedProgress > 0.012, !openingPastStart else { return false }
        return angularVelocity <= -1 || now - lastClosingTime < 0.8
    }

    private func handleModeChange() {
        overlay.foldMode = foldMode
        overlay.liveDesktop = foldMode.usesLiveCapture
        overlay.openAngle = openAngle
        overlay.destroyWindow()
        holdingFreeze = false
        foldSessionActive = false
        captureEpoch = nil
        capture.frozen = false
        cannedProgress = nil
        demoTask?.cancel()
        demoTask = nil
        requestCaptureStop(discard: true)
    }

    private static func stored(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(UserDefaults.standard.object(forKey: key) as? Double ?? fallback, range.lowerBound), range.upperBound)
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

    /// Critically damped follow, same family as Preview's per-frame curve.
    private static func smoothDamp(
        current: Double,
        target: Double,
        velocity: inout Double,
        smoothTime: Double,
        dt: Double
    ) -> Double {
        let smoothTime = max(0.0008, smoothTime)
        let omega = 2 / smoothTime
        let x = omega * dt
        let exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * exp
        return target + (change + temp) * exp
    }

}

private final class TickProxy: NSObject {
    var onTick: (TimeInterval) -> Void = { _ in }

    @objc func step(_ sender: CADisplayLink) {
        onTick(sender.targetTimestamp - sender.timestamp)
    }
}
