import ActivityKit
import Foundation

/// Shared payload for the Live Activity. Deliberately tiny: ActivityKit
/// serializes `ContentState` on every update, so we carry only the strings the
/// UI renders — no lyric arrays, no timers.
struct LyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var currentLine: String
        var nextLine: String?
        var isPlaying: Bool
        var progress: Double
    }
}
