import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders

@MainActor
final class DuoEngine {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let plusPipeline: MTLRenderPipelineState
    let frostPipeline: MTLRenderPipelineState
    let kawasePipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    let mipSampler: MTLSamplerState

    private(set) var sourceTexture: MTLTexture?
    private(set) var blurTexture: MTLTexture?
    private(set) var hasSource = false
    private(set) var captureFailed = false

    private var kawaseA: MTLTexture?
    private var kawaseB: MTLTexture?
    private(set) var plusTexture: MTLTexture?
    private var frostLevels: [MTLTexture] = []
    private var frostFilters: [MPSImageGaussianBlur] = []
    private lazy var plusScaler = MPSImageBilinearScale(device: device)
    private(set) var sourceGeneration: UInt64 = 0
    private var plusGeneration: UInt64 = .max
    private var frostGeneration: UInt64 = .max
    private static let frostSigmas: [Float] = [2, 6, 16, 40]

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
              let plus = library.makeFunction(name: "duo_plus_fragment"),
              let frost = library.makeFunction(name: "duo_frost_fragment"),
              let kawase = library.makeFunction(name: "duo_kawase") else {
            fatalError("Missing Metal functions")
        }

        pipeline = Self.makePipeline(device: device, vertex: vertex, fragment: fragment)
        plusPipeline = Self.makePipeline(device: device, vertex: vertex, fragment: plus)
        frostPipeline = Self.makePipeline(device: device, vertex: vertex, fragment: frost)
        kawasePipeline = Self.makePipeline(device: device, vertex: vertex, fragment: kawase)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)!

        let mipDescriptor = MTLSamplerDescriptor()
        mipDescriptor.minFilter = .linear
        mipDescriptor.magFilter = .linear
        mipDescriptor.mipFilter = .linear
        mipDescriptor.sAddressMode = .clampToEdge
        mipDescriptor.tAddressMode = .clampToEdge
        mipSampler = device.makeSamplerState(descriptor: mipDescriptor)!
    }

    func setSourceTexture(_ texture: MTLTexture) {
        sourceTexture = texture
        hasSource = true
        captureFailed = false
        sourceGeneration &+= 1
    }

    func persistSource() -> Bool {
        guard let source = sourceTexture else { return false }
        if source.storageMode == .private, source.usage.contains(.shaderWrite) {
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let dest = device.makeTexture(descriptor: descriptor),
              let commands = commandQueue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return false }
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: dest,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        sourceTexture = dest
        return true
    }

    func commitBlur() {
        guard let source = sourceTexture else { return }
        rebuildBlur(from: source)
    }

    func discardSource() {
        sourceTexture = nil
        blurTexture = nil
        plusTexture = nil
        frostGeneration = .max
        hasSource = false
        plusGeneration = .max
    }

    func markCaptureFailed() {
        captureFailed = true
    }

    func blurTextureOrSource() -> MTLTexture? {
        blurTexture ?? sourceTexture
    }

    func preparePlus(from source: MTLTexture, commandBuffer: MTLCommandBuffer, drawableSize: CGSize) {
        _ = drawableSize
        let width = source.width
        let height = source.height
        let sizeChanged = plusTexture?.width != width || plusTexture?.height != height
        if sizeChanged {
            plusTexture = makeMipTarget(width: width, height: height)
            plusGeneration = .max
        }
        guard sourceGeneration != plusGeneration || sizeChanged else { return }
        plusGeneration = sourceGeneration
        guard let target = plusTexture else { return }

        if source.width == width, source.height == height {
            guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
            blit.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: target,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.generateMipmaps(for: target)
            blit.endEncoding()
        } else {
            plusScaler.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: target)
            if let mipBlit = commandBuffer.makeBlitCommandEncoder() {
                mipBlit.generateMipmaps(for: target)
                mipBlit.endEncoding()
            }
        }
        plusTexture = target
    }

    func prepareFrost(from source: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let width = source.width
        let height = source.height
        if frostLevels.first?.width != width || frostLevels.first?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            frostLevels = (0..<Self.frostSigmas.count).compactMap { _ in
                device.makeTexture(descriptor: descriptor)
            }
            let scale = Float(max(height, 1)) / 1000
            frostFilters = Self.frostSigmas.map { sigma in
                let filter = MPSImageGaussianBlur(device: device, sigma: max(sigma * scale, 0.8))
                filter.edgeMode = .clamp
                return filter
            }
            frostGeneration = .max
        }
        guard sourceGeneration != frostGeneration else { return }
        frostGeneration = sourceGeneration
        for (filter, destination) in zip(frostFilters, frostLevels) {
            filter.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
        }
    }

    func frostLevel(_ index: Int) -> MTLTexture? {
        frostLevels.indices.contains(index) ? frostLevels[index] : nil
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
        commandBuffer.waitUntilCompleted()
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

    private func makeMipTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func clearToBlack(_ target: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let commands = commandQueue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }

    private static func makePipeline(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        blended: Bool = false
    ) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        if blended, let color = descriptor.colorAttachments[0] {
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Pipeline error: \(error)")
        }
    }
}
