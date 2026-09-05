import SwiftUI

/// The Settings → Appearance picker (design: settings.html bottom sheet).
/// Auto follows the device; Light / Dark force the palette. Stored under
/// `caraoke-appearance` so the HTML mock and the app agree on the key.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// Short label shown on the Settings row's trailing value.
    var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Full label shown in the bottom sheet.
    var sheetLabel: String {
        switch self {
        case .auto: return "Auto — follow system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Persisted appearance preference + the `preferredColorScheme` it maps to.
enum AppearanceSettings {
    static let storageKey = "caraoke-appearance"

    static var mode: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    /// nil = follow system.
    static var preferredScheme: ColorScheme? {
        switch mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}