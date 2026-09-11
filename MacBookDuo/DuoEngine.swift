import Foundation
import Metal
import MetalKit

@MainActor
final class DuoEngine {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let kawasePipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState

    private(set) var sourceTexture: MTLTexture?
    private(set) var blurTexture: MTLTexture?
    private(set) var hasSource = false
    private(set) var captureFailed = false

    private var kawaseA: MTLTexture?
    private var kawaseB: MTLTexture?

    var displayTexture: MTLTexture? { sourceTexture }

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is unavailable")
        }
        self.device = device
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "duo_vertex"),
              let fragment = library.makeFunction(name: "duo_fragment"),
              let kawase = library.makeFunction(name: "duo_kawase") else {
            fatalError("Missing Metal functions")
        }

        pipeline = Self.makePipeline(device: device, vertex: vertex, fragment: fragment)
        kawasePipeline = Self.makePipeline(device: device, vertex: vertex, fragment: kawase)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
    }

    func setSourceTexture(_ texture: MTLTexture) {
        sourceTexture = texture
        hasSource = true
        captureFailed = false
    }

    func commitBlur() {
        guard let source = sourceTexture else { return }
        rebuildBlur(from: source)
    }

    func markCaptureFailed() {
        captureFailed = true
    }

    func blurTextureOrSource() -> MTLTexture? {
        blurTexture ?? sourceTexture
    }

    private func rebuildBlur(from source: MTLTexture) {
        let halfWidth = max(source.width / 2, 1)
        let halfHeight = max(source.height / 2, 1)
        if kawaseA?.width != halfWidth || kawaseA?.height != halfHeight {
            kawaseA = makeTarget(width: halfWidth, height: halfHeight)
            kawaseB = makeTarget(width: halfWidth, height: halfHeight)
        }
        guard let kawaseA, let kawaseB, let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        encodeKawase(commandBuffer: commandBuffer, source: source, destination: kawaseA, offset: 1.0)
        encodeKawase(commandBuffer: commandBuffer, source: kawaseA, destination: kawaseB, offset: 2.0)
        encodeKawase(commandBuffer: commandBuffer, source: kawaseB, destination: kawaseA, offset: 3.5)
        encodeKawase(commandBuffer: commandBuffer, source: kawaseA, destination: kawaseB, offset: 5.5)
        commandBuffer.commit()
        blurTexture = kawaseB
    }

    private func encodeKawase(commandBuffer: MTLCommandBuffer, source: MTLTexture, destination: MTLTexture, offset: Float) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var uniforms = KawaseUniforms(
            texelSize: SIMD2<Float>(1 / Float(source.width), 1 / Float(source.height)),
            offset: offset
        )
        encoder.setRenderPipelineState(kawasePipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<KawaseUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private static func makePipeline(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Pipeline error: \(error)")
        }
    }
}
