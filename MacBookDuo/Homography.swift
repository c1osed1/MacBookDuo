import simd

/// Maps a rectangle onto a quad (Heckbert square-to-quad).
enum Homography {
    static func matrix(width: Double, height: Double, to corners: [SIMD2<Double>]) -> simd_double3x3 {
        precondition(corners.count == 4)
        let x0 = corners[0].x, y0 = corners[0].y
        let x1 = corners[1].x, y1 = corners[1].y
        let x2 = corners[2].x, y2 = corners[2].y
        let x3 = corners[3].x, y3 = corners[3].y

        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        var g = 0.0
        var h = 0.0
        if abs(dx3) > 1e-9 || abs(dy3) > 1e-9 {
            let det = dx1 * dy2 - dx2 * dy1
            if abs(det) > 1e-12 {
                g = (dx3 * dy2 - dx2 * dy3) / det
                h = (dx1 * dy3 - dx3 * dy1) / det
            }
        }

        let a = x1 - x0 + g * x1
        let b = x3 - x0 + h * x3
        let d = y1 - y0 + g * y1
        let e = y3 - y0 + h * y3

        return simd_double3x3(columns: (
            SIMD3(a / width, d / width, g / width),
            SIMD3(b / height, e / height, h / height),
            SIMD3(x0, y0, 1)
        ))
    }
}
