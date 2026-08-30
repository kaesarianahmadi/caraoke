#if os(iOS)
import AppIntents

/// Ported from DriveVerse `App/DriveModeIntents.swift` (MIT © 2026 Praveet
/// Gupta, see THIRD_PARTY_NOTICES.md), renamed to Caraoke's Ride Mode.
///
/// LiveActivityIntent executes in the app's process — launching it into the
/// background if it isn't running — and is the one context iOS allows
/// Activity.request from without the app being foregrounded. This is the
/// legal background path (the keep-alive alternative driveverse later added
/// — a background location session — is NOT App Store-safe and is deliberate-
/// ly not ported; a store build would use push-updated activities instead).
struct StartRideModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Ride Mode"
    static let description = IntentDescription(
        "Turns on Ride Mode and starts the lyrics Live Activity for whatever plays next."
    )

    func perform() async throws -> some IntentResult {
        await AppModel.shared.startRideSession()
        // Hold the intent open so the first playback read flows through the
        // pipeline while the LiveActivityIntent grant is in effect.
        try? await Task.sleep(for: .seconds(3))
        return .result()
    }
}

struct StopRideModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Ride Mode"
    static let description = IntentDescription(
        "Turns off Ride Mode and ends the lyrics Live Activity."
    )

    func perform() async throws -> some IntentResult {
        await AppModel.shared.stopRideSession()
        return .result()
    }
}

struct CaraokeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRideModeIntent(),
            phrases: ["Start \(.applicationName) Ride Mode"],
            shortTitle: "Start Ride Mode",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: StopRideModeIntent(),
            phrases: ["Stop \(.applicationName) Ride Mode"],
            shortTitle: "Stop Ride Mode",
            systemImageName: "car"
        )
    }
}
#endif
