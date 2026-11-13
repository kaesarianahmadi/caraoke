import Foundation

/// Display-only line segmentation for provider lyrics that arrive as whole
/// sentences (e.g. LRCLIB/YouTube Music LRC lines of 8-12 words).
///
/// A provider line carries ONE timestamp, so carving it into new timed
/// lines would fabricate sync the provider never supplied. This function
/// changes no timing: it returns the source string with `\n` inserted at
/// whole-word boundaries (at most 5 words per visual line), and the parent
/// renderers draw each visual line at the source line's existing weight
/// and opacity. Compatible with SwiftUI `Text` (`lineLimit`/`lineSpacing`)
/// and with native wrapping: CJK runs have no whitespace to break at, so
/// they come back unchanged and wrap natively on the surface.
enum LyricSegmenter {
    /// Inserts `\n` after every 5th word — at the whitespace that follows
    /// that word, so every original non-newline character and whitespace
    /// character survives exactly (removing the inserted `\n`s gives `text`
    /// back). Words are whitespace-delimited runs, so a run of Latin
    /// letters is never split: a lone long token produces no boundary and
    /// is returned unchanged. Inputs with no 6th word — including blank
    /// text and emoji-only text — are returned unchanged.
    ///
    /// - Parameter text: one source lyric line (it does not span lines).
    /// - Parameter maxWords: whole words per visual line (default 5).
    static func segmentedDisplayText(for text: String, maxWords: Int = 5) -> String {
        let limit = max(1, maxWords)
        var words = 0
        var inWord = false
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            if character.isNewline {
                words = 0
                inWord = false
            } else if character.isWhitespace {
                inWord = false
            } else if !inWord {
                if words == limit {
                    result.append("\n")
                    words = 0
                }
                words += 1
                inWord = true
            }
            result.append(character)
        }
        return result
    }
}
