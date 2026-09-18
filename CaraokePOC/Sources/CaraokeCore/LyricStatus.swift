import Foundation

/// The 5 live states every Live-Activity surface renders (playing / paused /
/// no-lyrics / loading / stale), plus `idle` for the pre-song placeholder the
/// moment Ride Mode turns on. Lives in the iOS layer (not CaraokeCore) so the
/// widget extension target can compile it without the core module.
enum LyricStatus: String, Codable, Equatable, Sendable {
    case playing
    case paused
    case noLyrics
    case loading
    case stale
    case idle
    /// The payload ran past the end of the song it describes and nothing
    /// replaced it — the widget's baked timeline is spent and the app never
    /// came back. Distinct from `stale`, which is a deliberate stop ("ride
    /// ended"): this one means "the lyrics stopped following the song" and the
    /// tile offers a resync tap.
    case expired

    /// Human label rendered in the tile's header badge (nil = no badge).
    var badge: String? {
        switch self {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .noLyrics: return "No lyrics"
        case .loading: return "Finding lyrics…"
        case .stale: return "Ride ended"
        case .expired: return "Out of date"
        case .idle: return nil
        }
    }

    /// The Home screen's player-card header badge ("Ride Mode" idle shows a
    /// muted status instead of nothing).
    var homeBadge: String {
        switch self {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .noLyrics: return "No lyrics"
        case .loading: return "Finding lyrics…"
        case .stale: return "Ride ended"
        case .expired: return "Out of date"
        case .idle: return "Ready"
        }
    }

    init?(raw: String?) {
        guard let raw else { return nil }
        self.init(rawValue: raw)
    }
}