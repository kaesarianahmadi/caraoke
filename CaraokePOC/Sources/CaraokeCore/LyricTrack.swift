import Foundation

/// The original lyric-timing engine, independent of any Apple framework so it
/// runs and is unit-tested on any platform (macOS here).
///
/// A `LyricTrack` is a sorted list of timed lines. Given a playback position
/// in milliseconds it answers which line is current and which is next.
struct LyricTrack: Equatable, Sendable {
    let lines: [LyricLine]

    /// Lines must be strictly sorted by start time.
    init(lines: [LyricLine]) {
        precondition(zip(lines, lines.dropFirst()).allSatisfy { $0.startMs < $1.startMs },
                     "LyricTrack lines must be strictly sorted by startMs")
        self.lines = lines
    }

    var durationMs: Int { lines.last?.startMs ?? 0 }

    /// Index of the line current at `positionMs`, or nil before the first line
    /// or when the track is empty.
    func lineIndex(at positionMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        guard positionMs >= lines[0].startMs else { return nil }
        var low = 0
        var high = lines.count - 1
        var answer = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startMs <= positionMs {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    /// The line current at `positionMs` (nil before the first line).
    func line(at positionMs: Int) -> LyricLine? {
        guard let i = lineIndex(at: positionMs) else { return nil }
        return lines[i]
    }

    /// The line following the current one, used for the quiet "next line"
    /// preview. Nil when there is no next line.
    func nextLine(after positionMs: Int) -> LyricLine? {
        guard let i = lineIndex(at: positionMs), i + 1 < lines.count else { return nil }
        return lines[i + 1]
    }

    /// Lines following the current one, used for previews.
    func upcomingLines(after positionMs: Int, limit: Int = 8) -> [String] {
        let nextIndex: Int
        if let i = lineIndex(at: positionMs) {
            nextIndex = i + 1
        } else if positionMs >= 0 {
            nextIndex = 0
        } else {
            return []
        }
        guard nextIndex < lines.count else { return [] }
        let endIndex = min(nextIndex + limit, lines.count)
        return lines[nextIndex..<endIndex].map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Lines preceding the current one, used for karaoke context.
    func previousLines(before positionMs: Int, limit: Int = 2) -> [String] {
        guard let i = lineIndex(at: positionMs), i > 0 else { return [] }
        let startIndex = max(0, i - limit)
        return lines[startIndex..<i].map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Progress through the track in 0...1, clamped, for the Live Activity
    /// progress bar. Treats a single-line track as complete once started.
    func progress(at positionMs: Int) -> Double {
        guard !lines.isEmpty else { return 0 }
        let end = max(durationMs, 1)
        return min(max(Double(positionMs) / Double(end), 0), 1)
    }
}
