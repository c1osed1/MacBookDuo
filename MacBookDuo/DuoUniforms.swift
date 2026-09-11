import Foundation
import simd

struct DuoUniforms {
    var resolution = SIMD2<Float>(1920, 1080)
    var progress: Float = 0
    var angle: Float = 110
    var time: Float = 0
    var intensity: Float = 1
    var pad = SIMD2<Float>.zero

    static let identity = DuoUniforms()
}

struct KawaseUniforms {
    var texelSize = SIMD2<Float>.zero
    var offset: Float = 1
    var pad: Float = 0
}
