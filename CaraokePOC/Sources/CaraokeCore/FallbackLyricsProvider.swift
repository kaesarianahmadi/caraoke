import Foundation

/// Races LRCLIB and YouTube Music. A short preference window favors verified
/// word-timed LRCLIB phrases; otherwise the first valid line-timed result wins.
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
        let lrclibTask = Task { try? await lrclib.lyrics(for: track) }
        let ytmTask = Task { try? await ytm.lyrics(for: track) }
        return await withTaskCancellationHandler {
            await withTaskGroup(of: (Int, LyricTrack?).self) { group in
            group.addTask { (0, await lrclibTask.value) }
            group.addTask { (1, await ytmTask.value) }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return (2, nil)
            }
            var fallback: LyricTrack?
            var completed = 0
            var graceExpired = false
            for await (source, result) in group {
                if source == 2 { graceExpired = true }
                else {
                    completed += 1
                    if source == 0, let result, result.hasWordTiming {
                        lrclibTask.cancel(); ytmTask.cancel(); group.cancelAll()
                        return result
                    }
                    if fallback == nil { fallback = result }
                }
                if let fallback, graceExpired || completed == 2 {
                    lrclibTask.cancel(); ytmTask.cancel(); group.cancelAll()
                    return fallback
                }
                if completed == 2 { break }
            }
            lrclibTask.cancel(); ytmTask.cancel(); group.cancelAll()
            return fallback
            }
        } onCancel: {
            lrclibTask.cancel()
            ytmTask.cancel()
        }
    }
}
