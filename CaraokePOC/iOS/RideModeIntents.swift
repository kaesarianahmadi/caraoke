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

    func perform() async throws -> IntentResultContainer<String, WidgetRefreshIntent, Never, Never> {
        let session = await MainActor.run {
            AppModel.shared.startRideSession()
            return SharedWidgetStore.startWidgetRefreshSession()
        }
        return .result(value: session, opensIntent: WidgetRefreshIntent(session: session))
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

/// The in-app switch must enter App Intents dispatch, not call `perform()` itself.
struct SetRideModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Live Lyrics"
    static let isDiscoverable = false

    @Parameter(title: "Enabled", default: true) var enabled: Bool

    init() {}

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func perform() async throws -> IntentResultContainer<String, WidgetRefreshIntent, Never, Never> {
        if !enabled {
            await AppModel.shared.stopRideSession()
            var result: IntentResultContainer<String, WidgetRefreshIntent, Never, Never> =
                .result(value: "stopped", opensIntent: WidgetRefreshIntent(session: ""))
            result.opensIntent = nil
            return result
        }
        let session = await MainActor.run {
            AppModel.shared.startRideSession()
            return SharedWidgetStore.startWidgetRefreshSession()
        }
        return .result(value: session, opensIntent: WidgetRefreshIntent(session: session))
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
