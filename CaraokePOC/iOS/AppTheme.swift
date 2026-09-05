import SwiftUI

/// "Night Podium" design tokens (caraoke design system §7.2), translated from
/// the OpenDesign screens' oklch values to sRGB hex (computed via OkLab →
/// linear sRGB → sRGB transfer). Two palettes: Dark (default, the night-drive
/// look) and Light. The Live Activity surfaces are ALWAYS dark glass
/// (`alwaysDark` → the LA tile never follows the system appearance).
///
/// These are the only colors the UI uses — matching the design screens at
/// 99% means matching these numbers.
enum AppTheme {

    // MARK: - Dark palette (Night Podium)

    static let darkBG      = Color(hex: 0x0A0E15)
    static let darkSurface = Color(hex: 0x131921)
    static let darkFG      = Color(hex: 0xECEFF2)
    static let darkMuted   = Color(hex: 0x82868E)
    static let darkBorder  = Color(hex: 0x292E36)
    /// Stage-glow amber — the live dot / app-icon accent only.
    static let darkAccent  = Color(hex: 0xFF9845)

    // MARK: - Light palette

    static let lightBG      = Color(hex: 0xF4F6F9)
    static let lightSurface = Color(hex: 0xFFFFFF)
    static let lightFG      = Color(hex: 0x191E27)
    static let lightMuted   = Color(hex: 0x565B63)
    static let lightBorder  = Color(hex: 0xD9DCE2)
    static let lightAccent  = Color(hex: 0xB36527)

    /// Apple semantic state colors (unchanged in both palettes).
    static let ok   = Color(hex: 0x34C759)
    static let warn = Color(hex: 0xFF9F0A)
    static let err  = Color(hex: 0xFF453A)

    // MARK: - Adaptive accessors (follow the current color scheme)

    static func bg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBG : lightBG }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSurface : lightSurface }
    static func fg(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkFG : lightFG }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkMuted : lightMuted }
    static func border(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBorder : lightBorder }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkAccent : lightAccent }

    /// The home screen background: the design uses a soft radial wash of the
    /// accent at the top melting into the bg. Emulated with a vertical
    /// gradient of accent-tinted bg → flat bg.
    static func background(_ scheme: ColorScheme) -> some View {
        let base = bg(scheme)
        let glow = accent(scheme).opacity(0.06)
        return LinearGradient(
            colors: [glow, glow.opacity(0.35), base, base],
            startPoint: .top, endPoint: .bottom
        )
        .background(base)
        .ignoresSafeArea()
    }
}

extension Color {
    /// 0xRRGGBB → Color in the sRGB color space.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}