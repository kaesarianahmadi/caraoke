import SwiftUI

@main
struct CaraokeApp: App {
    // Shared so RideModeIntents (App Intents live in the app process, even
    // from a background context) and this UI drive the same ViewModel.
    @ObservedObject private var model = AppModel.shared.ride

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
        }
    }
}
