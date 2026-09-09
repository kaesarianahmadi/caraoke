import SwiftUI
import UIKit
import CoreImage

/// App design tokens: Pure OLED Black & Zinc for dark mode, clean Ivory White for light mode.
/// Follows competitor palette (Dynamic Lyrics reference IMG_5085).
enum AppTheme {

    // MARK: - Dark palette (Pure OLED Black)
    static let darkBG      = Color(hex: 0x000000)
    static let darkSurface = Color(hex: 0x121214)
    static let darkFG      = Color(hex: 0xFFFFFF)
    static let darkMuted   = Color(hex: 0x8E8E93)
    static let darkBorder  = Color(hex: 0x27272A)
    static let darkAccent  = Color(hex: 0xFF9845)

    // MARK: - Light palette (Ivory White)
    static let lightBG      = Color(hex: 0xFAFAFA)
    static let lightSurface = Color(hex: 0xFFFFFF)
    static let lightFG      = Color(hex: 0x09090B)
    static let lightMuted   = Color(hex: 0x71717A)
    static let lightBorder  = Color(hex: 0xE4E4E7)
    static let lightAccent  = Color(hex: 0xB36527)

    // State colors
    static let ok   = Color(hex: 0x34C759)
    static let warn = Color(hex: 0xFF9F0A)
    static let err  = Color(hex: 0xFF453A)

    // Adaptive accessors
    static func bg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBG : lightBG }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSurface : lightSurface }
    static func fg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkFG : lightFG }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkMuted : lightMuted }
    static func border(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBorder : lightBorder }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkAccent : lightAccent }

    static func background(_ scheme: ColorScheme) -> some View {
        bg(scheme).ignoresSafeArea()
    }

    /// Cover-following wash — the same recipe the widgets paint, reused by the
    /// lyrics page so a song's colour follows the user everywhere.
    static func coverWash(_ hex: String?) -> LinearGradient? {
        guard let hex, let color = Color(hexString: hex) else { return nil }
        return LinearGradient(
            colors: [color.opacity(0.92), color.opacity(0.5), .black.opacity(0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Continuous vinyl rotation for the in-app discs. WidgetKit renders static
/// snapshots, so a Home Screen widget can never spin — this is app-only.
private struct VinylSpin: ViewModifier {
    let isSpinning: Bool
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear { if isSpinning { spin() } }
            .onChange(of: isSpinning) { _, spinning in
                spinning ? spin() : halt()
            }
    }

    private func spin() {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
    }

    /// Retargeting the same property with a short animation cancels the repeat
    /// and freezes the disc where it stands.
    private func halt() {
        withAnimation(.linear(duration: 0.3)) { angle = angle.truncatingRemainder(dividingBy: 360) }
    }
}

extension View {
    /// Spins while `isSpinning` (playback active), stops dead otherwise.
    func vinylSpin(_ isSpinning: Bool) -> some View {
        modifier(VinylSpin(isSpinning: isSpinning))
    }
}

/// Widget theme options. Raw values are stable storage keys (they travel to
/// the widget extension through the shared keychain); `displayName` is UI.
enum WidgetTheme: String, CaseIterable, Codable {
    case artwork
    case pitchBlack
    case simpleSlate
    case ivoryWhite

    var displayName: String {
        switch self {
        case .artwork: return "Follow Cover"
        case .pitchBlack: return "Pitch Black"
        case .simpleSlate: return "Simple Slate"
        case .ivoryWhite: return "Ivory White"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .artwork: return Color(hex: 0x243047)
        case .pitchBlack: return Color(hex: 0x000000)
        case .simpleSlate: return Color(hex: 0x18181B)
        case .ivoryWhite: return Color(hex: 0xFAFAFA)
        }
    }

    var textColor: Color {
        switch self {
        case .artwork, .pitchBlack, .simpleSlate: return .white
        case .ivoryWhite: return Color(hex: 0x09090B)
        }
    }

    var mutedTextColor: Color {
        switch self {
        case .artwork, .pitchBlack, .simpleSlate: return Color(hex: 0xA1A1AA)
        case .ivoryWhite: return Color(hex: 0x71717A)
        }
    }
}

/// Widget cover art style.
enum WidgetCoverStyle: String, CaseIterable, Codable {
    case picture
    case vinyl

    var displayName: String {
        switch self {
        case .picture: return "Picture"
        case .vinyl: return "Vinyl Disc"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Parses the `RRGGBB` string produced by `UIImage.averageColorHex`.
    init?(hexString: String) {
        guard hexString.count == 6, let value = UInt32(hexString, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension UIImage {
    /// Average colour of the cover as `RRGGBB`. Computed once in the app and
    /// shipped in the shared payload so the widget paints a song-following
    /// background without re-running CoreImage on every timeline reload.
    var averageColorHex: String? {
        guard let input = CIImage(image: self),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent)
              ]), let output = filter.outputImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(
            output, toBitmap: &rgba, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return String(format: "%02X%02X%02X", rgba[0], rgba[1], rgba[2])
    }
}
