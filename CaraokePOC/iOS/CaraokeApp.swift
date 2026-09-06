import SwiftUI

@main
struct CaraokeApp: App {
    // Shared so RideModeIntents (App Intents live in the app process, even
    // from a background context) and this UI drive the same ViewModel.
    @ObservedObject private var model = AppModel.shared.ride
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue

    private var preferredScheme: ColorScheme? {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .auto
        return AppearanceSettings.scheme(for: mode)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .preferredColorScheme(preferredScheme)
        }
    }
}
