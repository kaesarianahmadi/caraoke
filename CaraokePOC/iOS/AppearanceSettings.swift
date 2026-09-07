import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Settings → Appearance picker (design: settings.html bottom sheet).
/// Auto follows the device; Light / Dark force the palette. Stored under
/// `caraoke-appearance` so the HTML mock and the app agree on the key.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

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

    var colorScheme: ColorScheme? {
        AppearanceSettings.scheme(for: self)
    }
}

/// Persisted appearance preference + reactive updates
enum AppearanceSettings {
    static let storageKey = "caraoke-appearance"

    static var mode: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            apply(mode: newValue)
            NotificationCenter.default.post(name: .appearanceDidChange, object: nil)
        }
    }

    /// nil = follow system.
    static var preferredScheme: ColorScheme? {
        scheme(for: mode)
    }

    static func scheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func apply(mode: AppearanceMode) {
        #if canImport(UIKit)
        let updateBlock = {
            let style: UIUserInterfaceStyle
            switch mode {
            case .auto: style = .unspecified
            case .light: style = .light
            case .dark: style = .dark
            }
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
        #endif
    }
}

extension Notification.Name {
    static let appearanceDidChange = Notification.Name("CaraokeAppearanceDidChange")
}
