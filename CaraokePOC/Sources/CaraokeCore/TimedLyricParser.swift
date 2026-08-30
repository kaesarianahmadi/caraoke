import Foundation

/// Parses a compact timed-lyric format used by the offline demo fixture:
/// one line per row, `startMs<TAB>text`. Blank rows are skipped. No lyrics
/// are embedded in code — the fixture file is the single source of truth.
enum TimedLyricParser {
    static func parse(_ raw: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for row in raw.components(separatedBy: .newlines) {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let startMs = Int(parts[0]) else { continue }
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            result.append(LyricLine(startMs: startMs, text: text))
        }
        return result.sorted { $0.startMs < $1.startMs }
    }
}
