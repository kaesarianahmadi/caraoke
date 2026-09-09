#if os(iOS)
import AppIntents
import MediaPlayer
import WidgetKit

/// Live Activity transport buttons (design: live-activity.html transport row).
struct PausePlayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current song.")

    func perform() async throws -> some IntentResult {
        let player = MPMusicPlayerController.systemMusicPlayer
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        return .result()
    }
}

struct RewindIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Previous Song"
    static let description = IntentDescription("Skips to the previous song.")

    func perform() async throws -> some IntentResult {
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        return .result()
    }
}

struct SkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Song"
    static let description = IntentDescription("Skips to the next song.")

    func perform() async throws -> some IntentResult {
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        return .result()
    }
}

/// AppIntent for tapping vinyl album art in widgets to immediately refresh & resync lyrics
struct ResyncWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Resync Caraoke Lyrics"
    static let description = IntentDescription("Refreshes widget lyrics timeline.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Widget transport intents
struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Skips to the previous song.")

    func perform() async throws -> some IntentResult {
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        return .result()
    }
}

struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the current song.")

    func perform() async throws -> some IntentResult {
        let player = MPMusicPlayerController.systemMusicPlayer
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song.")

    func perform() async throws -> some IntentResult {
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        return .result()
    }
}
#endif
