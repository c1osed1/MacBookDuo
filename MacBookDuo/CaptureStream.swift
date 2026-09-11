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
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    private let outputQueue = DispatchQueue(label: "com.foldglass.macbookduo.capture", qos: .userInteractive)
    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var frozenFlag = false
    private var retainedCVTexture: CVMetalTexture?

    var frozen: Bool {
        get { lock.withLock { frozenFlag } }
        set { lock.withLock { frozenFlag = newValue } }
    }

    var isRunning: Bool { running }

    init(engine: DuoEngine) {
        self.engine = engine
        super.init()
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, engine.device, nil, &cache)
        textureCache = cache
    }

    func start() async {
        await stop()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let displayID = ScreenSnapper.builtinDisplayID(),
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                engine.markCaptureFailed()
                return
            }

            let bundleID = Bundle.main.bundleIdentifier
            let excluded = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.queueDepth = 3
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.displayP3
            config.minimumFrameInterval = CMTime(value: 1, timescale: 24)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
            self.stream = stream
            running = true
        } catch {
            running = false
            engine.markCaptureFailed()
        }
    }

    func stop() async {
        frozen = false
        running = false
        let current = stream
        stream = nil
        guard let current else { return }
        try? await current.stopCapture()
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

        Task { @MainActor in
            self.retainedCVTexture = cvTexture
            self.engine.setSourceTexture(texture)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.engine.markCaptureFailed()
        }
    }
}
