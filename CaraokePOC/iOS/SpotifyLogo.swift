import SwiftUI

/// Spotify vector logo matching `design/spotify-logo.svg`
public struct SpotifyLogo: View {
    public var size: CGFloat = 34

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x1DB954))

            SpotifyWavesShape()
                .fill(Color.black)
                .scaleEffect(0.68)
        }
        .frame(width: size, height: size)
    }
}

private struct SpotifyWavesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0

        // Bottom wave
        path.move(to: CGPoint(x: 17.521 * sx, y: 17.34 * sy))
        path.addCurve(to: CGPoint(x: 16.5 * sx, y: 17.58 * sy), control1: CGPoint(x: 17.28 * sx, y: 17.7 * sy), control2: CGPoint(x: 16.86 * sx, y: 17.82 * sy))
        path.addCurve(to: CGPoint(x: 5.94 * sx, y: 16.44 * sy), control1: CGPoint(x: 13.68 * sx, y: 15.84 * sy), control2: CGPoint(x: 10.14 * sy, y: 15.48 * sy))
        path.addCurve(to: CGPoint(x: 5.04 * sx, y: 15.9 * sy), control1: CGPoint(x: 5.52 * sx, y: 16.56 * sy), control2: CGPoint(x: 5.16 * sx, y: 16.26 * sy))
        path.addCurve(to: CGPoint(x: 5.58 * sx, y: 15.0 * sy), control1: CGPoint(x: 4.92 * sx, y: 15.48 * sy), control2: CGPoint(x: 5.22 * sx, y: 15.12 * sy))
        path.addCurve(to: CGPoint(x: 17.22 * sx, y: 16.32 * sy), control1: CGPoint(x: 10.14 * sx, y: 13.98 * sy), control2: CGPoint(x: 14.1 * sx, y: 14.4 * sy))
        path.addCurve(to: CGPoint(x: 17.521 * sx, y: 17.34 * sy), control1: CGPoint(x: 17.64 * sx, y: 16.5 * sy), control2: CGPoint(x: 17.7 * sx, y: 16.98 * sy))
        path.closeSubpath()

        // Middle wave
        path.move(to: CGPoint(x: 18.96 * sx, y: 14.04 * sy))
        path.addCurve(to: CGPoint(x: 17.7 * sx, y: 14.34 * sy), control1: CGPoint(x: 18.66 * sx, y: 14.46 * sy), control2: CGPoint(x: 18.12 * sx, y: 14.64 * sy))
        path.addCurve(to: CGPoint(x: 5.76 * sx, y: 12.96 * sy), control1: CGPoint(x: 14.46 * sx, y: 12.36 * sy), control2: CGPoint(x: 9.54 * sx, y: 11.76 * sy))
        path.addCurve(to: CGPoint(x: 4.62 * sx, y: 12.36 * sy), control1: CGPoint(x: 5.28 * sx, y: 13.08 * sy), control2: CGPoint(x: 4.74 * sx, y: 12.84 * sy))
        path.addCurve(to: CGPoint(x: 5.22 * sx, y: 11.22 * sy), control1: CGPoint(x: 4.5 * sx, y: 11.88 * sy), control2: CGPoint(x: 4.74 * sx, y: 11.34 * sy))
        path.addCurve(to: CGPoint(x: 18.72 * sx, y: 12.84 * sy), control1: CGPoint(x: 9.6 * sx, y: 9.9 * sy), control2: CGPoint(x: 15.0 * sx, y: 10.56 * sy))
        path.addCurve(to: CGPoint(x: 18.96 * sx, y: 14.04 * sy), control1: CGPoint(x: 19.08 * sx, y: 13.02 * sy), control2: CGPoint(x: 19.26 * sx, y: 13.62 * sy))
        path.closeSubpath()

        // Top wave
        path.move(to: CGPoint(x: 20.28 * sx, y: 10.68 * sy))
        path.addCurve(to: CGPoint(x: 18.72 * sx, y: 10.98 * sy), control1: CGPoint(x: 19.98 * sx, y: 11.1 * sy), control2: CGPoint(x: 19.26 * sx, y: 11.28 * sy))
        path.addCurve(to: CGPoint(x: 5.16 * sx, y: 9.30 * sy), control1: CGPoint(x: 15.24 * sx, y: 8.4 * sy), control2: CGPoint(x: 8.82 * sx, y: 8.16 * sy))
        path.addCurve(to: CGPoint(x: 3.78 * sx, y: 8.58 * sy), control1: CGPoint(x: 4.56 * sx, y: 9.48 * sy), control2: CGPoint(x: 3.96 * sx, y: 9.12 * sy))
        path.addCurve(to: CGPoint(x: 4.5 * sx, y: 7.2 * sy), control1: CGPoint(x: 3.6 * sx, y: 7.98 * sy), control2: CGPoint(x: 3.96 * sx, y: 7.38 * sy))
        path.addCurve(to: CGPoint(x: 20.22 * sx, y: 8.82 * sy), control1: CGPoint(x: 8.76 * sx, y: 5.94 * sy), control2: CGPoint(x: 15.78 * sx, y: 6.18 * sy))
        path.addCurve(to: CGPoint(x: 20.28 * sx, y: 10.68 * sy), control1: CGPoint(x: 20.76 * sx, y: 9.12 * sy), control2: CGPoint(x: 20.58 * sx, y: 10.14 * sy))
        path.closeSubpath()

        return path
    }
}
