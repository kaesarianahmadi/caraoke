import SwiftUI

/// Demo fixture bundled with the app: an original, in-house song so there is
/// no copyrighted lyric content anywhere in the PoC. The same timing engine
/// (LyricTrack) drives the simulator, the Live Activity, and the CarPlay view.
enum DemoLyrics {
    static let title = "Road Trip Anthem"
    static let artist = "Cibul & Njun"

    /// Original lines, in milliseconds, matching the bundled TSV fixture.
    /// Keep in sync with CaraokeCore/Resources/demo_lyrics.tsv.
    static let lines: [(ms: Int, text: String)] = [
        (0, "The dashboard hums, the headlights glow"),
        (3000, "Two furry friends are in the know"),
        (6000, "Cibul the silver, first to sing"),
        (9000, "A puddle of wet food — the king"),
        (12000, "Njun stays out, the roads are long"),
        (15000, "But every chorus brings him home"),
        (18000, "Sing the lines that pass the time"),
        (21000, "Car-oke rhythm, hill and climb"),
        (24000, "The words come easy, line by line"),
        (27000, "Headlights, high beams, yours and mine"),
        (30000, "Take the wheel and take the night"),
        (33000, "Road trip verses, burning bright")
    ]

    /// The timing core used everywhere in the PoC. Built here (Foundation-only)
    /// so the iOS app and the widget extension share the exact same logic.
    static var track: LyricTrack {
        LyricTrack(lines: lines.map { LyricLine(startMs: $0.ms, text: $0.text) })
    }
}
