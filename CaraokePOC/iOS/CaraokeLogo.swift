import SwiftUI

/// Caraoke vector mark matching `design/caraoke-logo.svg`
public struct CaraokeLogo: View {
    public var size: CGFloat = 28
    public var color: Color?
    public var tinted: Bool = false
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat = 28, color: Color? = nil, tinted: Bool = false) {
        self.size = size
        self.color = color
        self.tinted = tinted
    }

    public var body: some View {
        let drawColor = color ?? (tinted ? AppTheme.accent(scheme) : AppTheme.fg(scheme))
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 64.0
            ZStack {
                // Open C ring
                CaraokeCRingShape()
                    .stroke(style: StrokeStyle(lineWidth: 6.5 * s, lineCap: .round))
                    .transformEffect(CGAffineTransform(scaleX: s, y: s))

                // Music Note + Play Triangle
                CaraokeInnerMarkShape()
                    .fill()
                    .transformEffect(CGAffineTransform(scaleX: s, y: s))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(width: size, height: size)
        .foregroundColor(drawColor)
    }
}

public typealias BrandMark = CaraokeLogo

private struct CaraokeCRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Arc: center (32, 32), radius 26.
        // Start from angle for point (53.3, 17.1) around (32, 32):
        // dx = 21.3, dy = -14.9 -> ~ -35 degrees (or 325 degrees).
        // Goes clockwise around the left side to (53.3, 46.9) -> +35 degrees.
        path.addArc(
            center: CGPoint(x: 32, y: 32),
            radius: 26,
            startAngle: .degrees(-35),
            endAngle: .degrees(35),
            clockwise: true
        )
        return path
    }
}

private struct CaraokeInnerMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Note head 1: cx 20.2, cy 41.3, rx 4.5, ry 3.4, rot -16
        var h1 = Path(ellipseIn: CGRect(x: -4.5, y: -3.4, width: 9.0, height: 6.8))
        var t1 = CGAffineTransform(rotationAngle: -16 * .pi / 180)
            .concatenating(CGAffineTransform(translationX: 20.2, y: 41.3))
        path.addPath(h1, transform: t1)

        // Note head 2: cx 32.5, cy 39.2, rx 4.5, ry 3.4, rot -16
        var h2 = Path(ellipseIn: CGRect(x: -4.5, y: -3.4, width: 9.0, height: 6.8))
        var t2 = CGAffineTransform(rotationAngle: -16 * .pi / 180)
            .concatenating(CGAffineTransform(translationX: 32.5, y: 39.2))
        path.addPath(h2, transform: t2)

        // Stem 1: x=22.2, y=23.2, w=3.2, h=18.1
        path.addRect(CGRect(x: 22.2, y: 23.2, width: 3.2, height: 18.1))

        // Stem 2: x=34.5, y=20.1, w=3.2, h=19.1
        path.addRect(CGRect(x: 34.5, y: 20.1, width: 3.2, height: 19.1))

        // Beam: 22.2, 19.8 -> 37.7, 15.4 -> 37.7, 20.3 -> 22.2, 24.7
        path.move(to: CGPoint(x: 22.2, y: 19.8))
        path.addLine(to: CGPoint(x: 37.7, y: 15.4))
        path.addLine(to: CGPoint(x: 37.7, y: 20.3))
        path.addLine(to: CGPoint(x: 22.2, y: 24.7))
        path.closeSubpath()

        // Play triangle: (42.5, 25) -> (42.5, 35) -> (50.9, 30)
        path.move(to: CGPoint(x: 42.5, y: 25.0))
        path.addLine(to: CGPoint(x: 42.5, y: 35.0))
        path.addLine(to: CGPoint(x: 50.9, y: 30.0))
        path.closeSubpath()

        return path
    }
}
