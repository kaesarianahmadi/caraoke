import Foundation

/// A track to look lyrics up for. Everything a lyrics provider needs to
/// match a recording — deliberately mirroring what the now-playing sources
/// can supply (Apple Music via MediaPlayer, Spotify via the Web API).
struct TrackSignature: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?

    init(title: String, artist: String, album: String? = nil, durationMs: Int? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

/// The seam every lyrics source plugs into. Swift-mobile-first design: a
/// provider can be swapped in one commit (LRCLIB today, the indie-artist
/// catalog or a licensed aggregator later) without touching the UI or the
/// Live Activity pipeline.
///
/// Contract:
/// - Returns `nil` when no **synced** lyrics exist for the track (plain-only
///   and instrumental tracks count as unavailable — Caraoke renders timed
///   lines only, per PRD D4).
/// - Throws `LyricsError` for conditions the caller should surface
///   (rate limit, transport failure with no cache).
protocol LyricsRepository {
    func lyrics(for track: TrackSignature) async throws -> LyricTrack?
}

enum LyricsError: Error, Equatable {
    /// The provider asked us to back off (HTTP 429 + Retry-After).
    case rateLimited(until: Date)
    /// The network failed and no cached copy exists.
    case networkUnderlying(String)

    static func network(_ error: Error) -> LyricsError {
        .networkUnderlying(String(describing: error))
    }
}
