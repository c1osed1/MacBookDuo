import AppKit
import Metal
import MetalKit

@MainActor
final class DuoMetalView: MTKView, MTKViewDelegate {
    var uniforms = DuoUniforms.identity
    var foldMode: FoldMode = .glass
    var openAngle: Double = 100
    var plusLook = PlusLook()
    var liveDesktop = false
    private let engine: DuoEngine

    init(engine: DuoEngine) {
        self.engine = engine
        super.init(frame: .zero, device: engine.device)
        delegate = self
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        isPaused = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 120
        autoResizeDrawable = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        applyChrome()
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        (layer as? CAMetalLayer)?.pixelFormat = .bgra8Unorm
        (layer as? CAMetalLayer)?.displaySyncEnabled = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyChrome() {
        layer?.isOpaque = !liveDesktop
        (layer as? CAMetalLayer)?.isOpaque = !liveDesktop
        preferredFramesPerSecond = 120
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard engine.hasSource,
              let source = engine.displayTexture,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = engine.commandQueue.makeCommandBuffer() else {
            return
        }

        var uniforms = self.uniforms
        uniforms.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        self.uniforms = uniforms

        if foldMode.usesLiveCapture {
            let pointSize = bounds.size
            let scale = Double(drawableSize.width) / max(Double(pointSize.width), 1)
            engine.preparePlus(from: source, commandBuffer: commandBuffer, drawableSize: drawableSize)
            guard let plus = engine.plusTexture,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                commandBuffer.commit()
                return
            }
            var plusUniforms = foldMode == .frost
                ? DuoPlusGeometry.frostUniforms(
                    startAngle: openAngle,
                    currentAngle: Double(uniforms.angle),
                    progress: Double(uniforms.progress),
                    look: plusLook,
                    screenSize: pointSize,
                    pixelScale: scale
                )
                : DuoPlusGeometry.plusUniforms(
                    startAngle: openAngle,
                    currentAngle: Double(uniforms.angle),
                    progress: Double(uniforms.progress),
                    look: plusLook,
                    screenSize: pointSize,
                    pixelScale: scale
                )
            encoder.setRenderPipelineState(foldMode == .frost ? engine.frostPipeline : engine.plusPipeline)
            encoder.setFragmentBytes(&plusUniforms, length: MemoryLayout<PlusUniforms>.stride, index: 0)
            encoder.setFragmentTexture(plus, index: 0)
            encoder.setFragmentSamplerState(engine.mipSampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        } else {
            guard let blur = engine.blurTextureOrSource(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                commandBuffer.commit()
                return
            }
            encoder.setRenderPipelineState(engine.pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DuoUniforms>.stride, index: 0)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentTexture(blur, index: 1)
            encoder.setFragmentSamplerState(engine.sampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
