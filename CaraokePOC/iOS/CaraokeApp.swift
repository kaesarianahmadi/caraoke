import SwiftUI
#if canImport(TipKit)
import TipKit
#endif

@main
struct CaraokeApp: App {
    // Shared so RideModeIntents (App Intents live in the app process, even
    // from a background context) and this UI drive the same ViewModel.
    @ObservedObject private var model = AppModel.shared.ride
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.auto.rawValue
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CrashReporter.shared.start()
        Analytics.initialize()
        AppearanceSettings.apply(mode: AppearanceSettings.mode)
        // The widget extension refreshes the Spotify token with this ID, and
        // it only ships in the app bundle.
        SpotifyClientIDStore.mirrorBundledClientID()
        #if canImport(TipKit)
        if #available(iOS 17.0, *) {
            try? Tips.configure([.displayFrequency(.immediate)])
        }
        #endif
    }

    private var preferredScheme: ColorScheme? {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .auto
        return AppearanceSettings.scheme(for: mode)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView(model: model)
            }
                .preferredColorScheme(preferredScheme)
                .task { showWelcome = !hasSeenWelcome }
                .sheet(isPresented: $showWelcome, onDismiss: {
                    hasSeenWelcome = true
                }) {
                    OnboardingView {
                        hasSeenWelcome = true
                        showWelcome = false
                    }
                }
        }
        // Activity.request is only legal in the foreground, so a ride left
        // running while the activity was ended (or the app relaunched) gets it
        // back the moment we come forward.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.ensureActivity()
        }
    }
}
