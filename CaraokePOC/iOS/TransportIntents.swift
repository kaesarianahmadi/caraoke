#if os(iOS)
import AppIntents
import WidgetKit
import os

/// Transport buttons stay extension-side. Resync is a LiveActivityIntent so
/// the system runs its one-shot repair in the audio-holding app process.

struct ResyncWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resync Caraoke Lyrics"
    static let description = IntentDescription("Refreshes widget lyrics timeline.")

    func perform() async throws -> some IntentResult {
        Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
            .notice("resync requested")
#if !CARAOKE_WIDGET_EXTENSION
        await AppModel.shared.ride.resync()
#else
        await WidgetResync.run()
#endif
        return .result()
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
        if case .performed = await TransportControl.perform(.playPause) {
            // Let the player snapshot publish the new clock and play state together.
            SharedWidgetStore.requestReload(reason: "tap-playpause")
        }
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
