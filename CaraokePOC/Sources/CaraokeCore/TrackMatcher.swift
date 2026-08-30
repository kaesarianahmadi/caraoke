import Foundation

/// A lyric result handed to the matcher by any lyrics source — a licensed
/// provider API now, local LRC imports later. Deliberately vendor-agnostic:
/// no provider response type leaks into the core.
struct LyricsCandidate: Equatable {
    let title: String?
    let durationMs: Int?
    let hasSyncedLyrics: Bool
}

/// Ported from DriveVerse `LyricsMatcher` (MIT © 2026 Praveet Gupta, see
/// THIRD_PARTY_NOTICES.md); the vendor-specific response type is replaced by
/// `LyricsCandidate`.
///
/// Title/artist normalization for lyric-provider queries and for cache keys.
enum TrackMatcher {
    /// "Song (feat. X) - Remix" → "song"
    static func normalizeTitle(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        if let dash = s.range(of: " - ") {
            s = String(s[..<dash.lowerBound])
        }
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    /// "Rihanna feat. JAY-Z" → "rihanna"
    static func normalizeArtist(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    /// Cache key for a track. Duration is bucketed to 5 s so slightly different
    /// reports of the same track (Apple Music vs Spotify) usually collide.
    static func signature(title: String, artist: String, durationMs: Int?) -> String {
        let bucket = durationMs.map { Int((Double($0) / 5000.0).rounded()) } ?? -1
        return "\(normalizeTitle(title))|\(normalizeArtist(artist))|\(bucket)"
    }

    /// Picks the candidate whose normalized title matches and whose duration
    /// is within ±3 s (when ours is known); prefers synced lyrics.
    static func bestMatch(from candidates: [LyricsCandidate],
                          title: String,
                          durationMs: Int?) -> LyricsCandidate? {
        let wantedTitle = normalizeTitle(title)
        let matches = candidates.filter { candidate in
            guard normalizeTitle(candidate.title ?? "") == wantedTitle else { return false }
            guard let durationMs else { return true }
            guard let duration = candidate.durationMs else { return false }
            return abs(duration - durationMs) <= 3000
        }
        return matches.first { $0.hasSyncedLyrics } ?? matches.first
    }

    // MARK: - Helpers

    /// Removes every `(…)` and `[…]` segment.
    private static func stripBracketed(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" {
                depth += 1
            } else if ch == ")" || ch == "]" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 {
                out.append(ch)
            }
        }
        return out
    }

    private static let featMarkers = [" feat. ", " feat ", " featuring ", " ft. ", " ft "]

    private static func stripFeatClause(_ s: String) -> String {
        var s = s
        for marker in featMarkers {
            if let r = s.range(of: marker) {
                s = String(s[..<r.lowerBound])
            }
        }
        return s
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
