import SwiftUI

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
}

/// Widget Theme Options
enum WidgetTheme: String, CaseIterable, Codable {
    case artwork = "Follow Cover"
    case pitchBlack = "Pitch Black"
    case simpleSlate = "Simple Slate"
    case ivoryWhite = "Ivory White"

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

/// Widget Cover Art Style
enum WidgetCoverStyle: String, CaseIterable, Codable {
    case picture = "Picture"
    case vinyl = "Vinyl Disc"
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
