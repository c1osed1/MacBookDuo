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

enum FoldMode: String, CaseIterable, Identifiable {
    case glass
    case duoPlus
    case frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .duoPlus: "Duo+"
        case .frost: "Frost"
        }
    }

    var usesLiveCapture: Bool {
        self != .glass
    }

    var caption: String {
        switch self {
        case .glass:
            String(localized: "Freeze one frame, then recede.")
        case .duoPlus:
            String(localized: "Live desktop, warped around the hinge.")
        case .frost:
            String(localized: "Fixed plane: the picture holds its angle while the lid closes.")
        }
    }
}

struct PlusLook {
    var viewingDistance: Double = 6
    var recession: Double = 1
    var maxBlurRadius: Double = 135
    var blurEvenness: Double = 0
    var maxDim: Double = 1
    var dimReach: Double = 0.5

    static let farthestEye = 6.0
    static let nearestEye = 1.0
}

struct PlusUniforms {
    var column0 = SIMD4<Float>.zero
    var column1 = SIMD4<Float>.zero
    var column2 = SIMD4<Float>.zero
    var screenAndScale = SIMD4<Float>.zero
    var blur = SIMD4<Float>.zero
    var light = SIMD4<Float>.zero

    static let identity = PlusUniforms()
}

struct FrostUniforms {
    var plane = SIMD4<Float>.zero
    var optics = SIMD4<Float>.zero

    static let identity = FrostUniforms()
}
