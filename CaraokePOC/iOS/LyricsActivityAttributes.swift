import ActivityKit
import Foundation

/// Shared payload for the Live Activity. Deliberately tiny: ActivityKit
/// serializes `ContentState` on every update, so we carry only what the UI
/// renders — title, artist, current + next lyric line, playing state and
/// progress — plus the two numbers the times row needs (`1:24 / -1:28`).
/// No album art, no translations, no extra lyric lines (design contract).
struct LyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var currentLine: String
        var nextLine: String?
        var isPlaying: Bool
        var progress: Double
        /// Which of the 5 live states (playing/paused/nolyr/loading/stale)
        /// this content renders; the widget falls back to deriving it from
        /// `isPlaying` + `currentLine` when a relay push omits it.
        var status: String?
        /// Elapsed / track-length for the tabular times row. Relay pushes
        /// (background) include these; without them the row hides.
        var positionMs: Int?
        var durationMs: Int?
    }
}