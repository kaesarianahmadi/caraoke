import Foundation

/// One timed lyric line. `startMs` is the time the line becomes the current
/// line; the line stays current until the next line's `startMs`.
struct LyricLine: Codable, Equatable, Sendable {
    let startMs: Int
    let text: String
    /// Optional translated text for this line.
    var translation: String?

    init(startMs: Int, text: String, translation: String? = nil) {
        self.startMs = startMs
        self.text = text
        self.translation = translation
    }
}
