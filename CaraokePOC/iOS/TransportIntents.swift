#if os(iOS)
import AppIntents
import MediaPlayer

/// Live Activity transport buttons (design: live-activity.html transport row).
/// The Lock Screen banner and Dynamic Island expanded show rewind /
/// play-pause / skip; tapping one fires the matching App Intent. These run in
/// the app's process (LiveActivityIntent), so they reach the active playback
/// path regardless of which music source is driving it.
///
/// The buttons are wired to the **system music player** (`systemMusicPlayer`):
/// Apple Music always routes through it, and MPMusicPlayerController is the
/// only player both iOS and CarPlay-side control surfaces share without extra
/// entitlements. If the user plays from another app (Spotify app playback is
/// out of the app's sandbox), the intents are harmless no-ops — the buttons
/// still render, per the design.
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
#endif