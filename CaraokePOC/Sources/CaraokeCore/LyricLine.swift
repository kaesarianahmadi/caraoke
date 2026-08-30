import Foundation

/// One timed lyric line. `startMs` is the time the line becomes the current
/// line; the line stays current until the next line's `startMs`.
struct LyricLine: Equatable, Sendable {
    let startMs: Int
    let text: String
}
