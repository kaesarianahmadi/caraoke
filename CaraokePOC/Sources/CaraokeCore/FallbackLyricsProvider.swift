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
        let lrclibTask = Task { () -> Result<LyricTrack?, Error> in
            do { return .success(try await lrclib.lyrics(for: track)) } catch { return .failure(error) }
        }
        let ytmTask = Task { () -> Result<LyricTrack?, Error> in
            do { return .success(try await ytm.lyrics(for: track)) } catch { return .failure(error) }
        }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: (Int, Result<LyricTrack?, Error>?).self) { group in
            group.addTask { (0, await lrclibTask.value) }
            group.addTask { (1, await ytmTask.value) }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return (2, nil)
            }
            var fallback: LyricTrack?
            var failure: Error?
            var completed = 0
            var graceExpired = false
            for try await (source, outcome) in group {
                if source == 2 { graceExpired = true }
                else {
                    completed += 1
                    let result: LyricTrack?
                    switch outcome {
                    case .success(let track): result = track
                    case .failure(let error): failure = error; result = nil
                    case nil: result = nil
                    }
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
            if fallback == nil, let failure { throw failure }
            return fallback
            }
        } onCancel: {
            lrclibTask.cancel()
            ytmTask.cancel()
        }
    }
}
