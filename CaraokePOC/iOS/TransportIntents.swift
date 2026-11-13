#if os(iOS)
import AppIntents
import WidgetKit
import os

/// Transport buttons stay extension-side. Resync is a LiveActivityIntent so
/// the system runs its repair and follow-on in the audio-holding app process.

struct ResyncWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resync Caraoke Lyrics"
    static let description = IntentDescription("Refreshes widget lyrics timeline.")

    func perform() async throws -> IntentResultContainer<String, WidgetRefreshIntent, Never, Never> {
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("resync requested")
        let session = SharedWidgetStore.startWidgetRefreshSession()
#if !CARAOKE_WIDGET_EXTENSION
        await AppModel.shared.ride.resync(session: session)
#else
        await WidgetResync.run()
#endif
        var result: IntentResultContainer<String, WidgetRefreshIntent, Never, Never> =
            .result(value: session, opensIntent: WidgetRefreshIntent(session: session))
        if !SharedWidgetStore.isWidgetRefreshSession(session) { result.opensIntent = nil }
        return result
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Skips to the previous song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.previous)
        SharedWidgetStore.requestReload(reason: "tap-prev")
        return .result()
    }
}

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current song.")

    func perform() async throws -> some IntentResult {
        let before = SharedWidgetStore.read()
        if var payload = before {
            payload.isPlaying.toggle()
            SharedWidgetStore.write(payload)
        }
        let outcome = await TransportControl.perform(.playPause)
        if case .performed = outcome {
            // Real change — the app's next snapshot confirms the new state.
        } else {
            // A failed call must undo the optimistic toggle: a payload left
            // inverted freezes the widget, whose timeline only advances
            // while `isPlaying`.
            SharedWidgetStore.write(before)
        }
        SharedWidgetStore.requestReload(reason: "tap-playpause")
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.next)
        SharedWidgetStore.requestReload(reason: "tap-next")
        return .result()
    }
}
#endif
