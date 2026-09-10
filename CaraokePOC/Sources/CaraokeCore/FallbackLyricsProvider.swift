import Foundation

/// Concurrent racing lyrics provider:
/// 1. Races LRCLIB (fast primary, keyless, ~300ms) and YouTube Music InnerTube (broadest coverage, ~1.4s).
/// 2. Returns whichever finishes first with valid synced lyrics.
/// 3. If LRCLIB returns nil (e.g. 404, plain-only, or rate-limited), awaits YouTube Music fallback.
/// 4. Returns nil gracefully if unavailable anywhere.
final class FallbackLyricsProvider: LyricsRepository {
    private let lrclib: LRCLIBLyricsProvider
    private let ytm: YouTubeMusicLyricsProvider

    init(session: URLSession = .shared,
         lrclib: LRCLIBLyricsProvider? = nil,
         ytm: YouTubeMusicLyricsProvider? = nil) {
        self.lrclib = lrclib ?? LRCLIBLyricsProvider(session: session)
        self.ytm = ytm ?? YouTubeMusicLyricsProvider(session: session)
    }

    func lyrics(for track: TrackSignature) async throws -> LyricTrack? {
        await withTaskGroup(of: LyricTrack?.self) { group in
            group.addTask {
                try? await self.lrclib.lyrics(for: track)
            }
            group.addTask {
                try? await self.ytm.lyrics(for: track)
            }

            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }
}
