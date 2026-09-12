import QuartzCore
import SwiftUI

struct LookGallery: View {
    @Binding var foldMode: FoldMode

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = Self.foldProgress(at: context.date)
            VStack(spacing: 20) {
                MacBookPreview(mode: foldMode, progress: progress)
                    .frame(maxWidth: 360)
                    .padding(.top, 4)

                HStack(spacing: 14) {
                    ForEach(FoldMode.allCases) { mode in
                        LookStyleCard(
                            mode: mode,
                            progress: progress,
                            isSelected: foldMode == mode
                        ) {
                            foldMode = mode
                        }
                    }
                }

                Text(foldMode.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    /// Same open / hold / close loop as Preview, so the cards read as a fold.
    private static func foldProgress(at date: Date) -> CGFloat {
        let cycle = 2.9
        let x = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if x < 1.05 { return smoothstep(x / 1.05) }
        if x < 1.35 { return 1 }
        if x < 2.5 { return 1 - smoothstep((x - 1.35) / 1.15) }
        return 0
    }

    private static func smoothstep(_ t: Double) -> CGFloat {
        let x = min(max(t, 0), 1)
        return CGFloat(x * x * (3 - 2 * x))
    }
}

private struct LookStyleCard: View {
    let mode: FoldMode
    let progress: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Color.black
                    LookDesktop(mode: mode, progress: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
                .frame(height: 74)

                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    Text(mode.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.09) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(mode.caption)
    }
}

private struct MacBookPreview: View {
    let mode: FoldMode
    let progress: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            lid
            hinge
            deck
        }
    }

    private var lid: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.43, blue: 0.45),
                            Color(red: 0.22, green: 0.23, blue: 0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 22, y: 14)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black)
                .padding(6)

            ZStack {
                Color.black
                LookDesktop(mode: mode, progress: progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(8)

            VStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(white: 0.12))
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .fill(Color(red: 0.08, green: 0.12, blue: 0.2))
                                .frame(width: 3, height: 3)
                        }
                }
                .padding(.top, 11)
                Spacer()
            }
        }
        .aspectRatio(1.62, contentMode: .fit)
    }

    private var hinge: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 5)
            .padding(.horizontal, 22)
            .offset(y: -1)
    }

    private var deck: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 7,
                bottomTrailingRadius: 7,
                topTrailingRadius: 2,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.70, green: 0.71, blue: 0.73),
                        Color(red: 0.50, green: 0.51, blue: 0.53)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 86, height: 4)
                .offset(y: 2)
        }
        .frame(height: 18)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

private struct LookDesktop: View {
    let mode: FoldMode
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                wallpaper
                    .frame(width: geo.size.width, height: geo.size.height)
                    .modifier(LookPreviewEffect(mode: mode, progress: progress, size: geo.size))
            }
        }
        .allowsHitTesting(false)
    }

    private var wallpaper: some View {
        Canvas { context, size in
            let sky = Gradient(colors: [
                Color(red: 0.62, green: 0.78, blue: 0.90),
                Color(red: 0.90, green: 0.82, blue: 0.78),
                Color(red: 0.97, green: 0.90, blue: 0.80)
            ])
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            )

            var glow = context
            glow.addFilter(.blur(radius: 16))
            glow.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.58, y: size.height * 0.18, width: size.width * 0.34, height: size.width * 0.34)),
                with: .color(Color(red: 1.0, green: 0.84, blue: 0.58).opacity(0.7))
            )

            var farHills = Path()
            farHills.move(to: CGPoint(x: 0, y: size.height * 0.58))
            farHills.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.60),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.46),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.68)
            )
            farHills.addLine(to: CGPoint(x: size.width, y: size.height))
            farHills.addLine(to: CGPoint(x: 0, y: size.height))
            farHills.closeSubpath()
            context.fill(farHills, with: .color(Color(red: 0.58, green: 0.68, blue: 0.70).opacity(0.55)))

            var nearHills = Path()
            nearHills.move(to: CGPoint(x: 0, y: size.height * 0.72))
            nearHills.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.70),
                control1: CGPoint(x: size.width * 0.34, y: size.height * 0.82),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.60)
            )
            nearHills.addLine(to: CGPoint(x: size.width, y: size.height))
            nearHills.addLine(to: CGPoint(x: 0, y: size.height))
            nearHills.closeSubpath()
            context.fill(nearHills, with: .color(Color(red: 0.46, green: 0.56, blue: 0.50).opacity(0.72)))

            context.fill(
                Path(CGRect(x: 0, y: size.height * 0.86, width: size.width, height: size.height * 0.14)),
                with: .color(Color(red: 0.78, green: 0.72, blue: 0.58).opacity(0.55))
            )
        }
        .overlay(alignment: .top) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 7, weight: .bold))
                Text("Finder")
                    .font(.system(size: 8, weight: .semibold))
                Spacer()
                Text("12:04")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.26).opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 3)
            .background(.white.opacity(0.32))
        }
        .overlay(alignment: .bottomLeading) {
            previewWindow
                .padding(10)
        }
    }

    private var previewWindow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Circle().fill(Color.red.opacity(0.68)).frame(width: 5, height: 5)
                Circle().fill(Color.yellow.opacity(0.68)).frame(width: 5, height: 5)
                Circle().fill(Color.green.opacity(0.68)).frame(width: 5, height: 5)
                Text("Notes")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.24, blue: 0.26).opacity(0.72))
                    .padding(.leading, 2)
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.5))
                .frame(width: 72, height: 16)
        }
        .padding(6)
        .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: 0.8)
        )
    }
}

private struct LookPreviewEffect: ViewModifier {
    let mode: FoldMode
    let progress: CGFloat
    let size: CGSize

    func body(content: Content) -> some View {
        switch mode {
        case .glass:
            content
                .rotation3DEffect(
                    .degrees(Double(progress) * 72),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.82
                )
                .scaleEffect(1 - progress * 0.34, anchor: .bottom)
        case .duoPlus:
            content
                .modifier(DuoPlusSheetEffect(progress: progress, size: size))
                .opacity(1 - progress * 0.28)
        case .frost:
            FrostLookPreview(progress: progress, size: size) {
                content
            }
        }
    }

}

/// World-locked plane: the picture holds, then milks toward the far edge.
private struct FrostLookPreview<Desktop: View>: View {
    let progress: CGFloat
    let size: CGSize
    @ViewBuilder var desktop: () -> Desktop

    private var angle: Double { Double(progress) * 1.25 }
    private var milk: CGFloat { CGFloat(abs(sin(angle))) }

    var body: some View {
        ZStack {
            Color.black
            desktop()
            desktop()
                .blur(radius: 8 * milk)
                .mask(frostMask(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.28), location: 0.32),
                    .init(color: .black, location: 0.78)
                ]))
            desktop()
                .blur(radius: 22 * milk)
                .mask(frostMask(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.24),
                    .init(color: .black.opacity(0.5), location: 0.55),
                    .init(color: .black, location: 0.88)
                ]))
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.04 * milk),
                    Color.black.opacity(0.22 * milk)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .modifier(FrostPlaneEffect(progress: progress, size: size))
    }

    private func frostMask(stops: [Gradient.Stop]) -> some View {
        LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }
}

private struct FrostPlaneEffect: GeometryEffect {
    var progress: CGFloat
    var size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let width = Double(size.width)
        let height = Double(size.height)
        let closed = Double(progress)
        // Plane holds the hinge and stretches upward off the lid.
        let stretch = 1 + closed * 1.55
        let top = height * (1 - stretch)
        let inset = width * 0.10 * closed
        let dest = [
            SIMD2(inset, top),
            SIMD2(width - inset, top),
            SIMD2(width, height),
            SIMD2(0, height)
        ]
        let matrix = Homography.matrix(width: width, height: height, to: dest)
        var transform = CATransform3DIdentity
        transform.m11 = CGFloat(matrix[0][0])
        transform.m12 = CGFloat(matrix[0][1])
        transform.m14 = CGFloat(matrix[0][2])
        transform.m21 = CGFloat(matrix[1][0])
        transform.m22 = CGFloat(matrix[1][1])
        transform.m24 = CGFloat(matrix[1][2])
        transform.m41 = CGFloat(matrix[2][0])
        transform.m42 = CGFloat(matrix[2][1])
        transform.m44 = CGFloat(matrix[2][2])
        return ProjectionTransform(transform)
    }
}

private struct DuoPlusSheetEffect: GeometryEffect {
    var progress: CGFloat
    var size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let width = Double(size.width)
        let height = Double(size.height)
        let closed = Double(progress)
        let topInset = width * 0.30 * closed
        let topDrop = height * 0.38 * closed
        let dest = [
            SIMD2(topInset, topDrop),
            SIMD2(width - topInset, topDrop),
            SIMD2(width, height),
            SIMD2(0, height)
        ]
        let matrix = Homography.matrix(
            width: width,
            height: height,
            to: dest
        )
        var transform = CATransform3DIdentity
        transform.m11 = CGFloat(matrix[0][0])
        transform.m12 = CGFloat(matrix[0][1])
        transform.m14 = CGFloat(matrix[0][2])
        transform.m21 = CGFloat(matrix[1][0])
        transform.m22 = CGFloat(matrix[1][1])
        transform.m24 = CGFloat(matrix[1][2])
        transform.m41 = CGFloat(matrix[2][0])
        transform.m42 = CGFloat(matrix[2][1])
        transform.m44 = CGFloat(matrix[2][2])
        return ProjectionTransform(transform)
    }
}
