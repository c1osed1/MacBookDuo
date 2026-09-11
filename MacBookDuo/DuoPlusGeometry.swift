import CoreGraphics
import Foundation
import simd

/// Hinged-sheet projection used by Duo+.
enum DuoPlusGeometry {
    static let paddingInPoints: Double = 120
    private static let maxSeparationDegrees = 88.0

    /// Bottom-left, bottom-right, top-right, top-left, in screen points.
    static func corners(
        startAngle: Double,
        currentAngle: Double,
        viewingDistance: Double,
        recession: Double,
        screenSize: CGSize
    ) -> [SIMD2<Double>] {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let start = startAngle * .pi / 180
        let current = currentAngle * .pi / 180
        let travel = max(startAngle - currentAngle, 0)
        let separation = min(recession * travel, maxSeparationDegrees) * .pi / 180

        let reach = height * viewingDistance + height / 2 * cos(start)
        let rise = height / 2 * sin(start)
        let along = reach * cos(current) + rise * sin(current)
        let depth = max(reach * sin(current) - rise * cos(current), height / 10)
        let half = width / 2

        func project(_ x: Double, _ y: Double) -> SIMD2<Double> {
            let scale = depth / (depth + y * sin(separation))
            return SIMD2(
                half + (x - half) * scale,
                along + (y * cos(separation) - along) * scale
            )
        }

        return [project(0, 0), project(width, 0), project(width, height), project(0, height)]
    }

    static func plusUniforms(
        startAngle: Double,
        currentAngle: Double,
        progress: Double,
        look: PlusLook,
        screenSize: CGSize,
        pixelScale: Double
    ) -> PlusUniforms {
        let corners = corners(
            startAngle: startAngle,
            currentAngle: currentAngle,
            viewingDistance: look.viewingDistance,
            recession: look.recession,
            screenSize: screenSize
        )
        let forward = Homography.matrix(
            width: Double(screenSize.width),
            height: Double(screenSize.height),
            to: corners
        )
        let inverse = forward.inverse
        let blurStrength = pow(min(max(progress, 0), 1), 1.6)
        let dimStrength = pow(min(max(progress, 0), 1), 0.7)
        let maxLevel = Float(max(Int(floor(log2(Double(max(
            Double(screenSize.width) * pixelScale,
            Double(screenSize.height) * pixelScale
        ))))), 1))

        func column(_ index: Int) -> SIMD4<Float> {
            let c = inverse[index]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }

        return PlusUniforms(
            column0: column(0),
            column1: column(1),
            column2: column(2),
            screenAndScale: SIMD4(
                Float(screenSize.width),
                Float(screenSize.height),
                Float(pixelScale),
                Float(blurStrength)
            ),
            blur: SIMD4(
                Float(look.maxBlurRadius * pixelScale),
                Float(look.blurEvenness),
                Float(look.maxDim),
                Float(look.dimReach)
            ),
            light: SIMD4(0.2, Float(dimStrength), maxLevel, Float(paddingInPoints))
        )
    }

    /// World-locked sheet: the picture stays put while the lid sweeps through it.
    static func frostLook(from look: PlusLook) -> PlusLook {
        PlusLook(
            viewingDistance: min(max(look.viewingDistance, 3.2), 5.4),
            recession: 1,
            maxBlurRadius: look.maxBlurRadius,
            blurEvenness: max(look.blurEvenness, 0.08),
            maxDim: look.maxDim,
            dimReach: max(look.dimReach, 0.45)
        )
    }

    static func frostUniforms(
        startAngle: Double,
        currentAngle: Double,
        progress: Double,
        look: PlusLook,
        screenSize: CGSize,
        pixelScale: Double
    ) -> PlusUniforms {
        var uniforms = plusUniforms(
            startAngle: startAngle,
            currentAngle: currentAngle,
            progress: progress,
            look: frostLook(from: look),
            screenSize: screenSize,
            pixelScale: pixelScale
        )
        uniforms.light.w = Float(28 * pixelScale)
        return uniforms
    }
}
