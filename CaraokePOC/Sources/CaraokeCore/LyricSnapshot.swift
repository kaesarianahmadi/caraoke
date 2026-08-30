import Foundation

/// Snapshot of what the Live Activity and the CarPlay small view show at one
/// instant. Kept tiny on purpose: Live Activity content state is serialized on
/// every update, so it carries only the strings the UI needs.
struct LyricSnapshot: Equatable, Sendable {
    let title: String
    let artist: String
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
    let progress: Double
    /// Index of the current line in the track — lets the activity update
    /// policy detect real line changes instead of re-sending on every tick.
    let lineIndex: Int?
}
