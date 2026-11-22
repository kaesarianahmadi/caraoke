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

    /// Splits long LRC lines into timed sub-phrases (`maxWords` each) by
    /// interpolating across the line's span for narrow glanceable surfaces.
    static func segmentTimedLines(_ lines: [LyricLine], maxWords: Int = 6) -> [LyricLine] {
        let limit = max(1, maxWords)
        var out: [LyricLine] = []
        out.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            let words = line.text.split(whereSeparator: { $0.isWhitespace })
            guard words.count > limit else {
                out.append(line)
                continue
            }
            let nextStart = index + 1 < lines.count ? lines[index + 1].startMs : line.startMs + 4000
            let span = max(1, nextStart - line.startMs)
            let chunkCount = (words.count + limit - 1) / limit
            for chunkIndex in 0..<chunkCount {
                let startWord = chunkIndex * limit
                let endWord = min(words.count, startWord + limit)
                let text = words[startWord..<endWord].joined(separator: " ")
                let offset = (span * startWord) / words.count
                let candidateMs = line.startMs + offset
                let timeMs = out.last.map { max($0.startMs + 1, candidateMs) } ?? candidateMs
                out.append(LyricLine(startMs: timeMs, text: text, translation: line.translation))
            }
        }
        return out
    }
}
