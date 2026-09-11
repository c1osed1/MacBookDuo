import CoreMedia
import CoreVideo
import Foundation
import Metal
import ScreenCaptureKit

@MainActor
final class CaptureStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private let engine: DuoEngine
    private var stream: SCStream?
    private var running = false
    private var startingCount = 0
    private var stoppingIntentionally = false
    private var opChain: Task<Void, Never> = Task {}
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    private let outputQueue = DispatchQueue(label: "com.foldglass.macbookduo.capture", qos: .userInteractive)
    private let lock = NSLock()
    nonisolated(unsafe) private var frozenFlag = false
    private var retainedCVTexture: CVMetalTexture?
    private var liveFrameRing: [CVMetalTexture] = []
    nonisolated(unsafe) private var pendingCV: CVMetalTexture?
    nonisolated(unsafe) private var pendingTexture: MTLTexture?
    nonisolated(unsafe) private var hopScheduled = false

    var frozen: Bool {
        get { lock.withLock { frozenFlag } }
        set { lock.withLock { frozenFlag = newValue } }
    }

    func freeze() {
        lock.withLock {
            frozenFlag = true
            pendingCV = nil
            pendingTexture = nil
            hopScheduled = false
        }
    }

    var isRunning: Bool { running }
    var isStarting: Bool { startingCount > 0 }

    init(engine: DuoEngine) {
        self.engine = engine
        super.init()
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, engine.device, nil, &cache)
        textureCache = cache
    }

    func start(live: Bool = false) async {
        startingCount += 1
        defer { startingCount -= 1 }
        await runSerialized {
            await self.performStart(live: live)
        }
    }

    func stop() async {
        await runSerialized {
            await self.stopStream()
        }
    }

    private func runSerialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = opChain
        let next = Task { @MainActor in
            await previous.value
            await work()
        }
        opChain = next
        await next.value
    }

    private func performStart(live: Bool) async {
        frozen = false
        await stopStream()
        for attempt in 0..<12 {
            if Task.isCancelled { return }
            do {
                try await beginCapture(live: live)
                return
            } catch {
                running = false
                let delay = min(80 * (attempt + 1), 400)
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
        engine.markCaptureFailed()
    }

    private func beginCapture(live: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = ScreenSnapper.builtinDisplayID(),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureStartError.noDisplay
        }

        guard let ownApplications = CaptureFilterSafety.excludedApplications(in: content) else {
            throw CaptureStartError.notExcludable
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        if let pixels = ScreenSnapper.capturePixelSize() {
            config.width = pixels.width
            config.height = pixels.height
        } else {
            config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
            config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        }
        config.showsCursor = false
        config.scalesToFit = false
        config.queueDepth = live ? 3 : 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        config.minimumFrameInterval = CMTime(value: 1, timescale: live ? 60 : 30)
        if live, let pixels = ScreenSnapper.capturePixelSize() {
            config.width = max(pixels.width / 2, 960)
            config.height = max(pixels.height / 2, 600)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
        running = true
    }

    private func stopStream() async {
        running = false
        lock.withLock {
            pendingCV = nil
            pendingTexture = nil
            hopScheduled = false
        }
        let current = stream
        stream = nil
        liveFrameRing.removeAll()
        retainedCVTexture = nil
        guard let current else { return }
        stoppingIntentionally = true
        try? await current.stopCapture()
        stoppingIntentionally = false
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        if lock.withLock({ frozenFlag }) { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        guard let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }

        let shouldHop = lock.withLock {
            pendingCV = cvTexture
            pendingTexture = texture
            if hopScheduled { return false }
            hopScheduled = true
            return true
        }
        if shouldHop {
            Task { @MainActor in
                self.flushPending()
            }
        }
    }

    private func flushPending() {
        let pair: (CVMetalTexture, MTLTexture)? = lock.withLock {
            hopScheduled = false
            if frozenFlag {
                pendingCV = nil
                pendingTexture = nil
                return nil
            }
            guard let cv = pendingCV, let tex = pendingTexture else { return nil }
            pendingCV = nil
            pendingTexture = nil
            return (cv, tex)
        }
        guard let pair else { return }
        adopt(pair.0, texture: pair.1)
    }

    private func adopt(_ cvTexture: CVMetalTexture, texture: MTLTexture) {
        if frozen { return }
        retainedCVTexture = cvTexture
        liveFrameRing.append(cvTexture)
        if liveFrameRing.count > 2 {
            liveFrameRing.removeFirst()
        }
        engine.setSourceTexture(texture)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            if self.stoppingIntentionally { return }
            self.running = false
            self.engine.markCaptureFailed()
        }
    }
}

private enum CaptureStartError: Error {
    case noDisplay
    case notExcludable
}
