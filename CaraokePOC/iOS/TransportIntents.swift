#if os(iOS)
import AppIntents
import WidgetKit

/// Transport buttons for the Live Activity and the Home Screen widgets.
/// Every intent routes through `TransportControl`, which drives whichever
/// player is the active source (Apple Music or Spotify) — never a hardcoded
/// `MPMusicPlayerController` call.
struct PausePlayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.playPause)
        return .result()
    }
}

struct RewindIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Previous Song"
    static let description = IntentDescription("Skips to the previous song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.previous)
        return .result()
    }
}

struct SkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Song"
    static let description = IntentDescription("Skips to the next song.")

    func perform() async throws -> some IntentResult {
        await TransportControl.perform(.next)
        return .result()
    }
}

/// Tapping the cover / refresh button in a widget rebuilds the timeline from
/// the shared payload (which carries the full timed lyric list, so the widget
/// lands on the correct current line immediately).
struct ResyncWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Resync Caraoke Lyrics"
    static let description = IntentDescription("Refreshes widget lyrics timeline.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
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
