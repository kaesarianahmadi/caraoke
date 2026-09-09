import Foundation
import WidgetKit

/// Widget-side resync, run by `ResyncWidgetIntent` when the user taps a
/// widget's record/cover.
///
/// The tap must not be a no-op and must not merely open the app. So: pulse the
/// cover immediately (the widget has no animation, the pulse rides the
/// timeline), then ask Spotify what is playing right now and re-anchor the
/// shared payload to it — same song ⇒ correct the clock, different song ⇒ pull
/// its synced lyrics from LRCLIB and rebuild the payload. The app's next
/// snapshot overwrites all of this, so there is no second source of truth.
enum WidgetResync {

    private struct NowPlaying {
        let title: String
        let artist: String
        let durationMs: Int
        let progressMs: Int
        let isPlaying: Bool
    }

    static func run() async {
        guard var payload = SharedWidgetStore.read() else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        payload.resyncingUntilMs = nowMs + WidgetTimelineBuilder.resyncPulseWindowMs
        SharedWidgetStore.write(payload)
        WidgetCenter.shared.reloadAllTimelines()

        guard payload.source == "spotify",
              let token = await TransportControl.accessToken(),
              let playing = await spotifyNowPlaying(token: token) else { return }

        // Same song with lyrics already loaded: the only thing that drifts is
        // the clock, so re-anchor it and keep everything else.
        if playing.title == payload.title, !payload.lines.isEmpty {
            payload.trackStartEpochMs = nowMs - playing.progressMs
            payload.durationMs = playing.durationMs
            payload.isPlaying = playing.isPlaying
            payload.progress = fraction(playing.progressMs, playing.durationMs)
            payload.status = (playing.isPlaying ? LyricStatus.playing : LyricStatus.paused).rawValue
            payload.resyncingUntilMs = 0
            SharedWidgetStore.write(payload)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let lines = await syncedLyrics(title: playing.title, artist: playing.artist,
                                       durationMs: playing.durationMs)
        let position = SyncEngine.position(atMs: playing.progressMs, lines: lines,
                                           durationMs: playing.durationMs,
                                           isPlaying: playing.isPlaying)
        let status: LyricStatus
        if lines.isEmpty {
            status = .noLyrics
        } else {
            status = playing.isPlaying ? .playing : .paused
        }
        let refreshed = SharedWidgetPayload(
            title: playing.title,
            artist: playing.artist,
            currentLine: position.currentLine ?? "",
            previousLines: position.previousLines,
            nextLine: position.nextLine,
            upcomingLines: position.upcomingLines,
            isPlaying: playing.isPlaying,
            progress: position.trackProgress,
            status: status.rawValue,
            trackStartEpochMs: nowMs - playing.progressMs,
            durationMs: playing.durationMs,
            lines: lines.map { SharedLyricLine(timeMs: $0.timeMs, text: $0.text) },
            source: "spotify"
        )
        SharedWidgetStore.write(refreshed)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func fraction(_ positionMs: Int, _ durationMs: Int) -> Double {
        guard durationMs > 0 else { return 0 }
        return min(1, max(0, Double(positionMs) / Double(durationMs)))
    }

    // MARK: - Spotify

    private static func spotifyNowPlaying(token: String) async -> NowPlaying? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = json["item"] as? [String: Any],
              let title = item["name"] as? String else { return nil }
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        return NowPlaying(
            title: title,
            artist: artists.joined(separator: ", "),
            durationMs: item["duration_ms"] as? Int ?? 0,
            progressMs: json["progress_ms"] as? Int ?? 0,
            isPlaying: json["is_playing"] as? Bool ?? false
        )
    }

    // MARK: - LRCLIB (free, keyless — same endpoint the app's provider uses)

    private static func syncedLyrics(title: String, artist: String, durationMs: Int) async -> [LRCLine] {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int((Double(durationMs) / 1000).rounded()))),
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Caraoke/0.1 (https://github.com/caraoke/caraoke)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = json["syncedLyrics"] as? String else { return [] }
        return LRCParser.parse(synced)
    }
}
