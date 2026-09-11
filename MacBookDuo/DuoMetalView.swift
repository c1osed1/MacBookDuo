import AppKit
import Metal
import MetalKit

@MainActor
final class DuoMetalView: MTKView, MTKViewDelegate {
    var uniforms = DuoUniforms.identity
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
        layer?.isOpaque = true
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        (layer as? CAMetalLayer)?.pixelFormat = .bgra8Unorm
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard engine.hasSource,
              let source = engine.displayTexture,
              let blur = engine.blurTextureOrSource(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = engine.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var uniforms = self.uniforms
        uniforms.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        self.uniforms = uniforms

        encoder.setRenderPipelineState(engine.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DuoUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(blur, index: 1)
        encoder.setFragmentSamplerState(engine.sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
