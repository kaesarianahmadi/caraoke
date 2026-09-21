#if os(iOS)
import AppIntents
import WidgetKit

/// Transport buttons for the Home Screen widgets. Plain `AppIntent` on
/// purpose: a widget button runs in the widget extension, and the
/// `LiveActivityIntent` trio this used to use only performs in the app
/// process — the buttons silently did nothing. Both kinds route through
/// `TransportControl`, which drives whichever player is the active source.
/// (The Live Activity itself carries no transport buttons.)
struct ResyncWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Resync Caraoke Lyrics"
    static let description = IntentDescription("Refreshes widget lyrics timeline.")

    func perform() async throws -> some IntentResult {
        await WidgetResync.run()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Skips to the previous song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.previous)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current song.")

    func perform() async throws -> some IntentResult {
        if var payload = SharedWidgetStore.read() {
            payload.isPlaying.toggle()
            SharedWidgetStore.write(payload)
        }
        await TransportControl.perform(.playPause)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.next)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
#endif
