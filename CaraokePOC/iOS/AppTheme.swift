import SwiftUI
import UIKit
import CoreImage

/// App design tokens: Pure OLED Black & Zinc for dark mode, clean Ivory White for light mode.
/// Follows competitor palette (Dynamic Lyrics reference IMG_5085).
enum AppTheme {

    // MARK: - Dark palette (Pure OLED Black)
    static let darkBG              = Color(hex: 0x000000)
    static let darkSurface         = Color(hex: 0x121214)
    static let darkSurfaceElevated = Color(hex: 0x1A1A1E)
    static let darkFG              = Color(hex: 0xFFFFFF)
    static let darkMuted           = Color(hex: 0x9898A0)
    static let darkSubtle          = Color(hex: 0x5A5A62)
    static let darkBorder          = Color(hex: 0x27272A)
    static let darkAccent          = Color(hex: 0xFF9845)

    // MARK: - Light palette (Ivory White)
    static let lightBG              = Color(hex: 0xF7F7F8)
    static let lightSurface         = Color(hex: 0xFFFFFF)
    static let lightSurfaceElevated = Color(hex: 0xF0F0F3)
    static let lightFG              = Color(hex: 0x09090B)
    static let lightMuted           = Color(hex: 0x6E6E77)
    static let lightSubtle          = Color(hex: 0xA1A1AA)
    static let lightBorder          = Color(hex: 0xE4E4E7)
    static let lightAccent          = Color(hex: 0xC85A00)

    // State colors
    static let ok   = Color(hex: 0x34C759)
    static let warn = Color(hex: 0xFF9F0A)
    static let err  = Color(hex: 0xFF453A)

    // Adaptive accessors
    static func bg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBG : lightBG }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSurface : lightSurface }
    static func surfaceElevated(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSurfaceElevated : lightSurfaceElevated }
    static func fg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkFG : lightFG }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkMuted : lightMuted }
    static func subtle(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSubtle : lightSubtle }
    static func border(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBorder : lightBorder }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkAccent : lightAccent }

    static func background(_ scheme: ColorScheme) -> some View {
        bg(scheme).ignoresSafeArea()
    }
}

/// One cover treatment for the in-app surfaces (floating mini player, the
/// Widget section's preview). The real artwork when there is one, otherwise the
/// same vinyl fallback the Home Screen widget paints — so the app never shows a
/// hand-painted stand-in for the song that is actually playing (build 40's
/// preview hardcoded a blue gradient and a fixed brown disc).
struct CoverArtworkView: View {
    let artworkData: Data?
    var cornerRadius: CGFloat = 12
    /// Circular vinyl fallback instead of the artwork square (the Widget
    /// preview's default cover style).
    var showsVinylFallback: Bool = false
    /// Cover average colour (`RRGGBB`), used to tint the artwork placeholder so
    /// even the empty state follows the song.
    var artworkColorHex: String?

    var body: some View {
        Group {
            if let data = artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if showsVinylFallback {
                vinyl
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            (artworkColorHex.flatMap(Color.init(hexString:)) ?? AppTheme.darkSurface)
            Image(systemName: "music.note")
                .font(.system(size: cornerRadius * 1.1, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var vinyl: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.black, Color(white: 0.16), .black],
                                         center: .center, startRadius: 6, endRadius: 60))
            ForEach(0..<6, id: \.self) { index in
                Circle().stroke(.white.opacity(0.07), lineWidth: 0.5)
                    .padding(CGFloat(index * 8 + 6))
            }
            (artworkColorHex.flatMap(Color.init(hexString:)) ?? Color(white: 0.45))
                .frame(width: 83, height: 83)
                .clipShape(Circle())
            Circle().fill(.white.opacity(0.5)).frame(width: 7, height: 7)
        }
    }
}

/// Realistic vinyl disc with authentic black record grooves and artwork label.
/// Shared between the Home Screen medium widget and the in-app showcase.
struct VinylRecordView: View {
    var artworkData: Data? = nil
    var artworkImage: UIImage? = nil
    var diameter: CGFloat = 126
    var labelDiameter: CGFloat = 88

    private var image: UIImage? {
        artworkImage ?? artworkData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.black, Color(white: 0.16), .black], center: .center, startRadius: 8, endRadius: diameter / 2))
            ForEach(0..<7, id: \.self) { index in
                Circle().stroke(.white.opacity(0.07), lineWidth: 0.5)
                    .padding(CGFloat(index * 7 + 5))
            }
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Circle().fill(.gray.opacity(0.35)).overlay(Image(systemName: "music.note"))
                }
            }
            .frame(width: labelDiameter, height: labelDiameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.15)))
            Circle().fill(.white.opacity(0.55)).frame(width: 7, height: 7)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }
}

/// Cover-following wash — the same recipe the widgets paint, reused by the
/// lyrics page so a song's colour follows the user everywhere.
extension CoverArtworkView {
    static func wash(_ hex: String?) -> LinearGradient? {
        guard let hex, let color = Color(hexString: hex) else { return nil }
        return LinearGradient(
            colors: [color.opacity(0.48), color.opacity(0.22), Color(white: 0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Controlled ambient wash for Stage Card & Full Lyrics backdrop (max alpha 0.34 over #09090B).
    static func controlledStageWash(_ hex: String?, enabled: Bool) -> LinearGradient? {
        guard enabled, let hex, let color = Color(hexString: hex) else { return nil }
        return LinearGradient(
            colors: [color.opacity(0.34), color.opacity(0.16), Color(hex: 0x09090B)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum CockpitMetrics {
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 12
    static let innerRadius: CGFloat = 10
    static let consoleRadius: CGFloat = 20
    static let consolePadding: CGFloat = 10
    static let hitTarget: CGFloat = 44
}

enum HomeLayoutMode: String, CaseIterable, Identifiable {
    case stageFocus = "stage_focus"
    case surfaceStudio = "surface_studio"
    case minimalCockpit = "minimal_cockpit"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stageFocus: return "Stage Focus"
        case .surfaceStudio: return "Surface Studio"
        case .minimalCockpit: return "Minimal Cockpit"
        }
    }
}

enum LyricsBackdropStyle: String, CaseIterable, Identifiable {
    case ambientCover = "ambient_cover"
    case oledBlack = "oled_black"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ambientCover: return "Ambient Cover"
        case .oledBlack: return "OLED Pitch Black"
        }
    }
}

enum ExternalSurfaceTab: String, CaseIterable, Identifiable {
    case island = "Island"
    case carPlay = "CarPlay"
    case lock = "Lock"
    case widget = "Widget"

    var id: String { rawValue }
}

/// Continuous vinyl rotation for the in-app discs. WidgetKit renders static
/// snapshots, so a Home Screen widget can never spin — this is app-only.
private struct VinylSpin: ViewModifier {
    let isSpinning: Bool
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = isSpinning && !reduceMotion
        content
            .rotationEffect(.degrees(angle))
            .onAppear { if active { spin() } }
            .onChange(of: active) { _, spinning in
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
    @MainActor var widgetArtwork: (data: Data, hex: String?)? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, 160 / max(size.width, size.height))
        let thumbnailSize = CGSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = UIGraphicsImageRenderer(size: thumbnailSize).jpegData(withCompressionQuality: 0.8) { _ in
            self.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
        return (thumbnail, averageColorHex)
    }

    @MainActor static func fetchWidgetArtwork(_ urlString: String?, timeout: TimeInterval = 6) async -> (data: Data, hex: String?)? {
        guard let urlString, let url = URL(string: urlString), url.scheme == "https" else { return nil }
        let request = URLRequest(url: url, timeoutInterval: timeout)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)?.widgetArtwork
    }

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
