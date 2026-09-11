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
    var showsAngleInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showsAngleInMenuBar, forKey: "showsAngleInMenuBar") }
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
    private var foldSessionActive = false
    private var sessionGeneration: UInt64 = 0
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
        showsAngleInMenuBar = UserDefaults.standard.object(forKey: "showsAngleInMenuBar") as? Bool ?? false
        engine = DuoEngine()
        overlay = OverlayController(engine: engine)
        capture = CaptureStream(engine: engine)
    }

    func start() {
        guard !started else { return }
        started = true
        sensor.start()
        overlay.foldMode = foldMode
        overlay.liveDesktop = foldMode == .duoPlus
        overlay.openAngle = openAngle
        overlay.keepPresence()
        let initial = sensor.isAvailable ? sensor.angle : 110
        demoAngle = initial
        smoothedAngle = initial
        peakAngle = initial
        sawOpenPose = initial >= openAngle - 1
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
                finishCannedDemo(now: now)
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
        overlay.foldMode = foldMode
        overlay.openAngle = openAngle
        overlay.liveDesktop = foldMode == .duoPlus
        overlay.plusLook = plusLook
        overlay.uniforms = uniforms

        let motionAngle = sensor.isAvailable ? sensor.angle : rawAngle
        trackLidMotion(motionAngle, now: now)
        peakAngle = max(peakAngle, smoothedAngle)
        if smoothedAngle >= openAngle - 1 {
            sawOpenPose = true
        }

        guard enabled else {
            hideHold = 0
            holdingFreeze = false
            foldSessionActive = false
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
            hideHold = 0
            presentFold()
        } else if overlay.isVisible {
            hideHold += 1
            if hideHold > 18 {
                endFold(keepCapture: prewarming)
            }
        } else if capture.frozen, cannedProgress == nil {
            capture.frozen = false
            holdingFreeze = false
            foldSessionActive = false
        }

        if !folding, prewarming {
            overlay.keepPresence()
            ensureCaptureStarted()
        } else if !folding, !prewarming, now >= keepHotUntil, (capture.isRunning || capture.isStarting) {
            requestCaptureStop(discard: true)
        }

        syncTickRate()
    }

    func playCannedDemo() {
        if cannedProgress != nil, engine.hasSource {
            cannedStart = CACurrentMediaTime()
            cannedProgress = 0
            hideHold = 0
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

        let reuseLive = foldMode == .duoPlus && capture.isRunning && engine.hasSource
        let reuseFreeze = foldMode != .duoPlus && engine.hasSource
        if !reuseLive, !reuseFreeze {
            captureTask?.cancel()
            captureTask = nil
            if let captureStopTask {
                await captureStopTask.value
            }
            guard !Task.isCancelled else { return }
            let baseline = engine.sourceGeneration
            await capture.start(live: foldMode == .duoPlus)
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
        if foldMode == .duoPlus {
            overlay.liveDesktop = true
            overlay.foldMode = .duoPlus
            overlay.openAngle = openAngle
            overlay.plusLook = plusLook
            overlay.show()
        } else {
            commitFreezeAndShow()
        }
        cannedStart = CACurrentMediaTime()
        cannedProgress = 0
        hideHold = 0
        keepHotUntil = CACurrentMediaTime() + 2.5
        syncTickRate()
    }

    private func finishCannedDemo(now: TimeInterval) {
        cannedProgress = nil
        if sensor.isAvailable {
            sensor.poll()
            let real = sensor.angle
            smoothedAngle = real
            demoAngle = real
            lastAngleSample = real
            lastAngleSampleTime = now
        }
        angularVelocity = 0
        lastClosingTime = -.greatestFiniteMagnitude
        smoothedProgress = Self.progress(for: smoothedAngle, open: openAngle, closed: closedAngle)
        sawOpenPose = smoothedAngle >= openAngle - 1
        peakAngle = max(peakAngle, smoothedAngle)
        keepHotUntil = now + 2.5
        endFold(keepCapture: true)
    }

    func openStudio() {
        studioOpen = true
        StudioWindow.shared.show(model: self)
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
        if !foldSessionActive {
            foldSessionActive = true
            sessionGeneration = engine.sourceGeneration
            holdingFreeze = false
            capture.frozen = false
        }
        ensureCaptureStarted()
        guard engine.sourceGeneration > sessionGeneration else { return }
        if foldMode == .duoPlus {
            capture.frozen = false
            overlay.liveDesktop = true
            overlay.foldMode = .duoPlus
            overlay.openAngle = openAngle
            overlay.plusLook = plusLook
            if !overlay.isVisible {
                overlay.show()
            }
        } else if !holdingFreeze {
            commitFreezeAndShow()
        }
    }

    private func endFold(keepCapture: Bool) {
        overlay.hide()
        holdingFreeze = false
        capture.frozen = false
        foldSessionActive = false
        hideHold = 0
        if keepCapture { return }
        requestCaptureStop(discard: true)
    }

    private func requestCaptureStop(discard: Bool) {
        captureTask?.cancel()
        captureTask = nil
        captureStopTask = Task { [weak self] in
            await self?.capture.stop()
        }
        if discard {
            engine.discardSource()
        }
    }

    private func commitFreezeAndShow() {
        capture.frozen = true
        engine.persistSource()
        engine.commitBlur()
        holdingFreeze = true
        overlay.liveDesktop = false
        overlay.show()
        if capture.isRunning {
            captureStopTask = Task { [weak self] in
                await self?.capture.stop()
            }
        }
    }

    private func ensureCaptureStarted() {
        overlay.keepPresence()
        guard !capture.isRunning, !capture.isStarting, captureTask == nil else { return }
        captureTask = Task { [weak self] in
            await self?.capture.start(live: self?.foldMode == .duoPlus)
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
            if angularVelocity <= -2 {
                lastClosingTime = now
            }
            lastAngleSample = angle
            lastAngleSampleTime = now
        } else if now - lastAngleSampleTime > 0.4 {
            angularVelocity = 0
        }
    }

    private func wantsPrewarm(now: TimeInterval) -> Bool {
        guard enabled else { return false }
        let closingRecently = now - lastClosingTime < 2.0
        return closingRecently && smoothedAngle <= openAngle + 70
    }

    private var needsActiveTick: Bool {
        overlay.isVisible
            || cannedProgress != nil
            || smoothedProgress > 0.008
            || holdingFreeze
            || angularVelocity <= -2
            || CACurrentMediaTime() < keepHotUntil
    }

    private func syncTickRate() {
        let active = needsActiveTick
        guard active != highRate else { return }
        highRate = active
        displayLink?.preferredFrameRateRange = active
            ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
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
        let opening = angularVelocity >= 2
        if foldSessionActive || overlay.isVisible {
            if opening, smoothedAngle >= openAngle { return false }
            return smoothedProgress > 0.012
        }
        let closingRecently = now - lastClosingTime < 1.5
        return sawOpenPose
            && closingRecently
            && !opening
            && smoothedProgress > 0.012
    }

    private func handleModeChange() {
        overlay.foldMode = foldMode
        overlay.liveDesktop = foldMode == .duoPlus
        overlay.openAngle = openAngle
        overlay.destroyWindow()
        holdingFreeze = false
        foldSessionActive = false
        capture.frozen = false
        cannedProgress = nil
        demoTask?.cancel()
        demoTask = nil
        requestCaptureStop(discard: true)
    }

    private static func stored(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(UserDefaults.standard.object(forKey: key) as? Double ?? fallback, range.lowerBound), range.upperBound)
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
