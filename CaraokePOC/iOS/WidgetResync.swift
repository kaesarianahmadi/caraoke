import Foundation
import UIKit
import os

/// Widget-side resync. One repair, two triggers: `ResyncWidgetIntent` when the
/// user taps a widget's record/cover, and the widget provider itself when a
/// timeline wake finds its payload spent.
///
/// Ask Spotify what is playing, then re-anchor the same track or build a
/// fresh payload. Concurrent calls in this process share that work.

enum WidgetResync {
    private static let automaticRepair = AutomaticWidgetRepair()

    static func refreshAutomatically(timeout: TimeInterval) async -> WidgetRepairOutcome {
        await automaticRepair.refresh { await refreshNowPlaying(timeout: timeout) }
    }

    static func run() async {
        _ = await automaticRepair.refresh(force: true) { await refreshNowPlaying(timeout: 6) }
        SharedWidgetStore.requestReload(reason: "manual-resync")
    }

    /// Asks the player what is on right now and rewrites the shared payload
    /// from the answer. Two triggers share this one repair (build 56): the
    /// cover tap, and the widget's own timeline wake when it finds its payload
    /// spent. The self-fetch is what keeps the tile following the music when
    /// the app has been suspended and cannot reload us.
    ///
    /// `timeout` is per request — the timeline wake runs on WidgetKit's clock
    /// and must not outlive it, because an overrunning extension is killed and
    /// the old timeline is kept.
    private static func refreshNowPlaying(timeout: TimeInterval) async -> WidgetRepairOutcome {
        guard let original = await SharedWidgetStore.read() else { return .idle }

        let log = Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
        guard original.source == "spotify" else {
            log.notice("timeline self-repair requires app for source=\(original.source, privacy: .public)")
            return .unavailable
        }
        guard let token = await TransportControl.accessToken() else {
            log.error("timeline self-repair failed: Spotify credentials unavailable")
            return .unavailable
        }
        let playing: NowPlayingState
        switch await spotifyNowPlaying(token: token, timeout: timeout) {
        case .idle: return await SharedWidgetStore.replace(original, with: .spotifyIdle)
        case .unavailable: return .unavailable
        case .track(let track): playing = track
        }
        // Match the app poller's request-midpoint clock. Token refresh and
        // network time must not move the playback anchor back to request start.
        let nowMs = Int(playing.capturedAt.timeIntervalSince1970 * 1000)

        let sameTrack = playing.title == original.title && playing.artist == original.artist && playing.album == original.album
        let durationMs = playing.durationMs ?? 0
        var payload: SharedWidgetPayload
        if sameTrack, !original.lines.isEmpty {
            payload = original
            if payload.artworkData == nil,
               let cover = await UIImage.fetchWidgetArtwork(playing.artworkURL, timeout: timeout) {
                payload.artworkData = cover.data
                payload.artworkColorHex = cover.hex
            }
        } else {
            async let artwork = UIImage.fetchWidgetArtwork(playing.artworkURL, timeout: timeout)
            let signature = TrackSignature(title: playing.title, artist: playing.artist, album: playing.album,
                                           durationMs: durationMs > 0 ? durationMs : nil)
            let track: LyricTrack?
            let status: LyricStatus
            do {
                track = try await LRCLIBLyricsProvider(timeout: timeout).lyrics(for: signature)
                status = track == nil ? .noLyrics : (playing.isPlaying ? .playing : .paused)
            } catch {
                // Spotify confirmed the new track even if lyrics are unavailable.
                track = nil
                status = .loading
            }
            let cover = await artwork
            payload = SharedWidgetPayload(
                title: playing.title, artist: playing.artist, album: playing.album, currentLine: "",
                isPlaying: playing.isPlaying, progress: 0, status: status.rawValue,
                lines: track?.lines.map {
                    SharedLyricLine(timeMs: $0.startMs, text: $0.text, translation: $0.translation)
                } ?? [], artworkData: cover?.data ?? (sameTrack ? original.artworkData : nil),
                artworkColorHex: cover == nil && sameTrack ? original.artworkColorHex : cover?.hex,
                source: "spotify"
            )
        }
        let elapsedMs = playing.isPlaying ? max(0, Int(Date().timeIntervalSince(playing.capturedAt) * 1000)) : 0
        let position = SyncEngine.position(
            atMs: playing.positionMs + elapsedMs,
            lines: payload.lines.map { LRCLine(timeMs: $0.timeMs, text: $0.text, translation: $0.translation) },
            durationMs: playing.durationMs, isPlaying: playing.isPlaying
        )
        payload.currentLine = position.currentLine ?? ""
        payload.currentTranslation = position.currentTranslation
        payload.previousLines = position.previousLines
        payload.nextLine = position.nextLine
        payload.upcomingLines = position.upcomingLines
        payload.isPlaying = playing.isPlaying
        payload.progress = position.trackProgress
        if !payload.lines.isEmpty {
            payload.status = (playing.isPlaying ? LyricStatus.playing : .paused).rawValue
        }
        payload.trackStartEpochMs = nowMs - playing.positionMs
        payload.durationMs = durationMs
        payload.resyncingUntilMs = 0
        return await SharedWidgetStore.replace(original, with: payload)
    }

    // MARK: - Spotify

    private static func spotifyNowPlaying(token: String, timeout: TimeInterval) async -> SpotifyPlayback {
        let url = URL(string: "https://api.spotify.com/v1/me/player")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        let requestedAt = Date()
        let log = Logger(subsystem: "com.caraoke.poc", category: "widgetintent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            let capturedAt = requestedAt.addingTimeInterval(Date().timeIntervalSince(requestedAt) / 2)
            if http.statusCode != 200 {
                log.notice("Spotify resync response HTTP \(http.statusCode, privacy: .public)")
            }
            return try SpotifyPlayback.decode(data, statusCode: http.statusCode, capturedAt: capturedAt)
        } catch {
            log.error("Spotify resync request failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }
}
